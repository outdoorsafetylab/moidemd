#ifdef ALPINE
#include <gdal.h>
#include <cpl_string.h>
#include <ogr_spatialref.h>
#else
#include <gdal/gdal.h>
#include <gdal/cpl_string.h>
#include <gdal/ogr_spatialref.h>
#endif

#include "context.h"

static char *sanitizeSRS(const char *);
static int contextGetBounds(context *ctx);
static int contextGetCorner(context *, double *, double *);

struct context {
    GDALDatasetH hSrcDS;
    GDALRasterBandH hBand;
    double NoDataValue;
    OGRSpatialReferenceH hSrcSRS;
    OGRSpatialReferenceH hTrgSRS;
    char *SanitizedSRS;
    OGRCoordinateTransformationH hCT;
    OGRCoordinateTransformationH hInvCT;
    double adfGeoTransform[6];
    double adfInvGeoTransform[6];
    double top;
    double left;
    double bottom;
    double right;
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
    ctx->SanitizedSRS = sanitizeSRS(srs);
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
    ctx->hInvCT = OCTNewCoordinateTransformation(ctx->hTrgSRS, ctx->hSrcSRS);
    if (!ctx->hInvCT) {
        fprintf(stderr, "Failed to inverse coordinate transform: %s\n", strerror(errno));
        ContextFree(ctx);
        return NULL;
    }
    if (!contextGetBounds(ctx)) {
        fprintf(stderr, "Failed to get bounds: %s\n", strerror(errno));
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
    if (ctx->hInvCT) {
        OCTDestroyCoordinateTransformation(ctx->hInvCT);
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

void ContextGetBounds(context *ctx, double *t, double *l, double *b, double *r) {
    *t = ctx->top;
    *l = ctx->left;
    *b = ctx->bottom;
    *r = ctx->right;
}

int contextGetBounds(context *ctx) {
    double upperLeftX = 0, upperLeftY = 0;
    if (!contextGetCorner(ctx, &upperLeftX, &upperLeftY)) {
        return FALSE;
    }
    // printf("upper left: %f,%f\n", upperLeftX, upperLeftY);
    double lowerLeftX = 0, lowerLeftY = GDALGetRasterYSize(ctx->hSrcDS);
    if (!contextGetCorner(ctx, &lowerLeftX, &lowerLeftY)) {
        return FALSE;
    }
    // printf("lower left: %f,%f\n", lowerLeftX, lowerLeftY);
    double upperRightX = GDALGetRasterXSize(ctx->hSrcDS), upperRightY = 0;
    if (!contextGetCorner(ctx, &upperRightX, &upperRightY)) {
        return FALSE;
    }
    // printf("upper right: %f,%f\n", upperRightX, upperRightY);
    double lowerRightX = GDALGetRasterXSize(ctx->hSrcDS), lowerRightY = GDALGetRasterYSize(ctx->hSrcDS);
    if (!contextGetCorner(ctx, &lowerRightX, &lowerRightY)) {
        return FALSE;
    }
    // printf("lower right: %f,%f\n", lowerRightX, lowerRightY);
    ctx->top = upperRightY > upperLeftY ? upperRightY : upperLeftY;
    ctx->bottom = lowerRightY < lowerLeftY ? lowerRightY : lowerLeftY;
    ctx->left = upperLeftX < lowerLeftX ? upperLeftX : lowerLeftX;
    ctx->right = upperRightX > lowerRightX ? upperRightX : lowerRightX;
    // printf("left=%f, top=%f, right=%f, bottom=%f\n", ctx->left, ctx->top, ctx->right, ctx->bottom);
    return TRUE;
}

int contextGetCorner(context *ctx, double *x, double *y) {
    *x = ctx->adfGeoTransform[0] + ctx->adfGeoTransform[1] * (*x)
        + ctx->adfGeoTransform[2] * (*y);
    *y = ctx->adfGeoTransform[3] + ctx->adfGeoTransform[4] * (*x)
        + ctx->adfGeoTransform[5] * (*y);
    double z = 0;
    return OCTTransform(ctx->hInvCT, 1, x, y, &z);
}

char *sanitizeSRS(const char *pszUserInput) {
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
