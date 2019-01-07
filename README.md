# Elevation Service for DTM from Taiwan MOI

This project provides an elevation service with REST API. It is implemented in C++, with GDAL, libevent, and JSON-C.

## How to Build

This project was developed on Ubuntu 16.04 LTS. You will need to install the following packages by ```apt-get``` before building it:

* build-essential
* libgdal-dev
* libevent-dev
* libjson-c-dev

To build:

```shell
make
```

A executable file ```moidemd``` will be created. You can run it to see the help:

```shell
$ ./moidemd
Usage: ./moidemd [options] <DEM file>
Options:
    -a <addr> : Address to bind HTTP (default: 0.0.0.0)
    -p <port> : Port to bind HTTP (default: 80)
    -u <URI>  : URI to serve REST (default: /v1/elevations)
    -s <SRS>  : SRS of requested coordinates (default: WGS84)
```

## How to Run

Before running the daemon, you should download [MOI DTM](https://data.gov.tw/dataset/35430) file first. For now only the ```dem_20m.tif``` of whole Taiwan island was tested.

To run a test daemon with ```dem_20m.tif```  on 8080 port:

```shell
$ ./moidemd -p 8080 dem_20m.tif
Serving dem_20m.tif: http://0.0.0.0:8080/v1/elevations
```

To query the elevation of Mt. Jade of this test daemon:

```shell
$ curl -XPOST --data '[[120.957283,23.47]]' http://127.0.0.1:8080/v1/elevations
[ 3946.000000 ]
```

## API Specification

### POST /v1/elevations

#### Request Body

Array of coordinates to query elevations. Each coordinate is another array consist of geographical X and Y value. For WGS84, they are longitude and latitude respectively.

Upon unexpected request body, ```400 Bad Request``` will be replied.

#### Response Body

Array of elevations, in ```double```,  corresponding to input coordinates. Upon the following scenario, ```null``` will be returned as elevation value:

* The requested coordinate was outside the DEM.
* The requested coordinate was inside the DEM, but elevation was not defined.
