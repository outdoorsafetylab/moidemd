FROM alpine:3.10.2 as build

LABEL description="Build container - moidemd"

RUN apk update && apk add --no-cache \ 
    --repository http://dl-cdn.alpinelinux.org/alpine/edge/testing \  
    --repository http://dl-cdn.alpinelinux.org/alpine/edge/main \
    build-base g++ make libevent-dev json-c-dev gdal-dev

RUN mkdir /src/
COPY Makefile main.cpp /src/
WORKDIR /src
RUN make CFLAGS=-DALPINE

FROM alpine:3.10.2 as runtime

LABEL description="Run container - moidemd"

RUN apk update && apk add --no-cache \ 
    --repository http://dl-cdn.alpinelinux.org/alpine/edge/testing \  
    --repository http://dl-cdn.alpinelinux.org/alpine/edge/main \
    libstdc++ libevent json-c gdal proj4

COPY --from=build /src/moidemd /usr/local/sbin/
COPY dem_20m.tif /etc/

CMD /usr/local/sbin/moidemd -p 8080 /etc/dem_20m.tif

EXPOSE 8080