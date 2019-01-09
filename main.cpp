#include <stdio.h>
#include <gdal/gdal.h>
#include <gdal/cpl_string.h>
#include <gdal/ogr_spatialref.h>
#include <signal.h>
#include <event2/event.h>
#include <event2/buffer.h>
#include <event2/http.h>
#include <json-c/json.h>
#include <math.h>

static double GetAltitude(GDALDatasetH, int, int, int);
static char *SanitizeSRS(const char *);

struct context;
static context *ContextCreate(const char *, const char *);
static void ContextFree(context *);
static double ContextGetAltitude(context *, double, double);

static void do_term(int sig, short events, void *arg) {
	struct event_base *base = (struct event_base *) arg;
	event_base_loopbreak(base);
	fprintf(stderr, "Got signal %d, terminating...\n", sig);
}

static void elevation_request_cb(struct evhttp_request *req, void *arg);

static const char *contentType = "application/json";
static const char *defaultAddress = "0.0.0.0";
static const int defaultPort = 80;
static const char *defaultSRS = "WGS84";
static const char *defaultURI = "/v1/elevations";

int main(int argc, char **argv) {
    context *ctx = NULL;
    struct event_base *base = NULL;
    struct evhttp *http = NULL;
    struct evhttp_bound_socket *handle = NULL;
	struct event *term = NULL;
    int opt, ret = 0, port = defaultPort;
    const char *addr = defaultAddress;
    const char *srs = defaultSRS;
    const char *uri = defaultURI;

    while ((opt = getopt(argc, argv, "a:p:u:s:")) != -1) {
		switch (opt) {
			case 'a': addr = optarg; break;
			case 'p': port = atoi(optarg); break;
			case 'u': uri = optarg; break;
			case 's': srs = optarg; break;
			default : fprintf(stderr, "Unknown option %c\n", opt); break;
		}
	}

    if (optind >= argc || (argc-optind) > 1) {
		fprintf(stdout, "Usage: %s [options] <DEM file>\n", argv[0]);
		fprintf(stdout, "Options:\n");
		fprintf(stdout, "    -a <addr> : Address to bind HTTP (default: %s)\n", defaultAddress);
		fprintf(stdout, "    -p <port> : Port to bind HTTP (default: %d)\n", defaultPort);
		fprintf(stdout, "    -u <URI>  : URI to serve REST (default: %s)\n", defaultURI);
		fprintf(stdout, "    -s <SRS>  : SRS of requested coordinates (default: %s)\n", defaultSRS);
		exit(1);
	}

    const char *filename = argv[optind];
    GDALAllRegister();
    ctx = ContextCreate(filename, srs);
    if (!ctx) {
		ret = 1;
		goto err;
    }

    if (signal(SIGPIPE, SIG_IGN) == SIG_ERR) {
		fprintf(stderr, "Failed to ignore SIGPIPE: %s\n", strerror(errno));
		ret = 1;
		goto err;
	}

    base = event_base_new();
    if (!base) {
		fprintf(stderr, "Failed to create event_base: %s\n", strerror(errno));
		ret = 1;
		goto err;
	}

    http = evhttp_new(base);
	if (!http) {
		fprintf(stderr, "Failed to create evhttp: %s\n", strerror(errno));
		ret = 1;
		goto err;
	}

    evhttp_set_cb(http, uri, elevation_request_cb, ctx);

    handle = evhttp_bind_socket_with_handle(http, addr, port);
	if (!handle) {
		fprintf(stderr, "Failed to bind port %d: %s\n", port, strerror(errno));
		ret = 1;
		goto err;
	}

    term = evsignal_new(base, SIGINT, do_term, base);
	if (!term) {
		fprintf(stderr, "Failed to create signal handler: %s\n", strerror(errno));
		ret = 1;
		goto err;
    }

	if (event_add(term, NULL)) {
		fprintf(stderr, "Failed to enable signal handler: %s\n", strerror(errno));
		ret = 1;
		goto err;
    }

    fprintf(stderr, "Serving %s: http://%s:%d%s\n", filename, addr, port, uri);
	ret = event_base_dispatch(base);

err:
	if (http) {
		evhttp_free(http);
    }
	if (term) {
		event_free(term);
    }
	if (base) {
		event_base_free(base);
    }
    if (ctx) {
        ContextFree(ctx);
    }
    GDALDestroyDriverManager();
	return ret;
}

void elevation_request_cb(struct evhttp_request *req, void *arg) {
    context *ctx = (context *)arg;
    char *data = NULL;
    json_object *coords, *json = NULL, *result = NULL;
    size_t len;
    int n;
    evbuffer *input, *output = NULL;

    switch (evhttp_request_get_command(req)) {
    case EVHTTP_REQ_POST:
        break;
    default:
        evhttp_send_error(req, 405, NULL);
        return;
    }

    output = evbuffer_new();
    if (!output) {
        fprintf(stderr, "Failed to allocate output buffer: %s\n", strerror(errno));
        goto err;
    }

    input = evhttp_request_get_input_buffer(req);
    if (!input) {
        fprintf(stderr, "Failed to get input buffer: %s\n", strerror(errno));
        goto err;
    }

    len = evbuffer_get_length(input);
    if (len <= 0) {
        evhttp_send_error(req, 400, NULL);
        goto done;
    }

    data = (char *) malloc(len);
    if (evbuffer_copyout(input, data, len) != len) {
        fprintf(stderr, "Failed to drain input buffer: %s\n", strerror(errno));
        goto err;
    }

    json = json_tokener_parse(data);
    if (!json) {
        fprintf(stderr, "Failed to parse input buffer: %s\n", strerror(errno));
        goto err;
    }
    
    if (!json_object_is_type(json, json_type_array)) {
        evhttp_send_error(req, 400, NULL);
        goto done;
    }

    n = json_object_array_length(json);
    if (n < 0) {
        evhttp_send_error(req, 400, NULL);
        goto done;
    } else if (n == 0) {
        evbuffer_add(output, "[]", 2);
    } else {
        result = json_object_new_array();
        if (!result) {
            fprintf(stderr, "Failed to create JSON array for results: %s\n", strerror(errno));
            goto err;
        }
        for (int i = 0; i < n; i++) {
            coords = json_object_array_get_idx(json, i);
            if (json_object_array_length(coords) != 2) {
                evhttp_send_error(req, 400, NULL);
                goto done;
            }
            json_object *x = json_object_array_get_idx(coords, 0);
            json_object *y = json_object_array_get_idx(coords, 1);
            double xVal = json_object_get_double(x);
            if (errno == EINVAL) {
                evhttp_send_error(req, 400, NULL);
                goto done;
            }
            double yVal = json_object_get_double(y);
            if (errno == EINVAL) {
                evhttp_send_error(req, 400, NULL);
                goto done;
            }
            double alt = ContextGetAltitude(ctx, xVal, yVal);
            json_object *val = NULL;
            if (!isnan(alt)) {
                val = json_object_new_double(alt);
            }
            json_object_array_add(result, val);
        }
        const char *string = json_object_to_json_string(result);
        if (evbuffer_add(output, string, strlen(string)) != 0
                || evbuffer_add(output, "\n", 1) != 0) {
            fprintf(stderr, "Failed to dump JSON string: %s\n", strerror(errno));
            goto err;
        }
    }
    evhttp_add_header(evhttp_request_get_output_headers(req), "Content-Type", contentType);
    evhttp_send_reply(req, 200, "OK", output);
    goto done;
err:
    evhttp_send_error(req, 500, NULL);
done:
    if (output) {
        evbuffer_free(output);
    }
    if (result) {
        json_object_put(result);
    }
    if (json) {
        json_object_put(json);
    }
    if (data) {
        free(data);
    }
}

char *SanitizeSRS(const char *pszUserInput) {
    OGRSpatialReferenceH hSRS;
    char *pszResult = NULL;

    CPLErrorReset();
    
    hSRS = OSRNewSpatialReference( NULL );
    if (OSRSetFromUserInput(hSRS, pszUserInput) == OGRERR_NONE) {
        OSRExportToWkt(hSRS, &pszResult);
    } else {
        return NULL;
    }
    
    OSRDestroySpatialReference(hSRS);
    return pszResult;
}

struct context {
    GDALDatasetH hSrcDS;
    GDALRasterBandH hBand;
    double NoDataValue;
    OGRSpatialReferenceH hSrcSRS;
    OGRSpatialReferenceH hTrgSRS;
    char *SanitizedSRS;
    OGRCoordinateTransformationH hCT;
    double adfGeoTransform[6];
    double adfInvGeoTransform[6];
};

context *ContextCreate(const char *filename, const char *srs) {
    context *ctx = (context *) calloc(sizeof(context), 1);
    ctx->hSrcDS = GDALOpen(filename, GA_ReadOnly);
    if (!ctx->hSrcDS) {
        fprintf(stderr, "Failed to open '%s': %s\n", filename, strerror(errno));
        ContextFree(ctx);
        return NULL;
    }
    int count = GDALGetRasterCount(ctx->hSrcDS);
    if (count != 1) {
        fprintf(stderr, "Unexpected number of band '%s': %d\n", filename, count);
        ContextFree(ctx);
        return NULL;
    }
    ctx->hBand = GDALGetRasterBand(ctx->hSrcDS, 1);
    if (!ctx->hBand) {
        fprintf(stderr, "Failed to get raster band '%s': %s\n", filename, strerror(errno));
        ContextFree(ctx);
        return NULL;
    }
    if (GDALDataTypeIsComplex(GDALGetRasterDataType(ctx->hBand))) {
        fprintf(stderr, "Unexpected data type '%s'\n", filename);
        ContextFree(ctx);
        return NULL;
    }
    ctx->NoDataValue = GDALGetRasterNoDataValue(ctx->hBand, NULL);
    if (GDALGetGeoTransform(ctx->hSrcDS, ctx->adfGeoTransform) != CE_None) {
        fprintf(stderr, "Failed to get geotransform %s: %s\n", filename, strerror(errno));
        ContextFree(ctx);
        return NULL;
    }
    if (!GDALInvGeoTransform(ctx->adfGeoTransform, ctx->adfInvGeoTransform)) {
        fprintf(stderr, "Failed to invert geotransform %s: %s\n", filename, strerror(errno));
        ContextFree(ctx);
        return NULL;
    }
    ctx->SanitizedSRS = SanitizeSRS(srs);
    if (!ctx->SanitizedSRS) {
        fprintf(stderr, "Failed to sanitize SRS '%s': %s\n", srs, strerror(errno));
        ContextFree(ctx);
        return NULL;
    }
    ctx->hSrcSRS = OSRNewSpatialReference(ctx->SanitizedSRS);
    if (!ctx->hSrcSRS) {
        fprintf(stderr, "Failed to create source SRS: %s\n", strerror(errno));
        ContextFree(ctx);
        return NULL;
    }
    ctx->hTrgSRS = OSRNewSpatialReference(GDALGetProjectionRef(ctx->hSrcDS));
    if (!ctx->hSrcSRS) {
        fprintf(stderr, "Failed to create target SRS: %s\n", strerror(errno));
        ContextFree(ctx);
        return NULL;
    }
    ctx->hCT = OCTNewCoordinateTransformation(ctx->hSrcSRS, ctx->hTrgSRS);
    if (!ctx->hCT) {
        fprintf(stderr, "Failed to create coordinate transform: %s\n", strerror(errno));
        ContextFree(ctx);
        return NULL;
    }
    return ctx;
}

void ContextFree(context *ctx) {
    if (!ctx) {
        return;
    }
    if (ctx->hCT) {
        OCTDestroyCoordinateTransformation(ctx->hCT);
    }
    if (ctx->SanitizedSRS) {
        free(ctx->SanitizedSRS);
    }
    if (ctx->hTrgSRS) {
        OSRDestroySpatialReference(ctx->hTrgSRS);
    }
    if (ctx->hSrcSRS) {
        OSRDestroySpatialReference(ctx->hSrcSRS);
    }
    if (ctx->hSrcDS) {
        GDALClose(ctx->hSrcDS);
    }
    free(ctx);
}

double ContextGetAltitude(context *ctx, double dfGeoX, double dfGeoY) {
    if (!OCTTransform(ctx->hCT, 1, &dfGeoX, &dfGeoY, NULL)) {
        return NAN;
    }
    int iPixel, iLine;
    iPixel = (int) floor(
        ctx->adfInvGeoTransform[0] 
        + ctx->adfInvGeoTransform[1] * dfGeoX
        + ctx->adfInvGeoTransform[2] * dfGeoY);
    iLine = (int) floor(
        ctx->adfInvGeoTransform[3] 
        + ctx->adfInvGeoTransform[4] * dfGeoX
        + ctx->adfInvGeoTransform[5] * dfGeoY);
    if (iPixel < 0 || iLine < 0 
            || iPixel >= GDALGetRasterXSize(ctx->hSrcDS)
            || iLine  >= GDALGetRasterYSize(ctx->hSrcDS)) {
        errno = ERANGE;
        return NAN;
    }
    double adfPixel[2];    
    if (GDALRasterIO(ctx->hBand, GF_Read, iPixel, iLine, 1, 1, 
                        adfPixel, 1, 1, GDT_CFloat64, 0, 0) == CE_None) {
        if (adfPixel[0] == ctx->NoDataValue) {
            return NAN;
        } else {
            return adfPixel[0];
        }
    }
    return NAN;
}
