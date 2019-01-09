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

If development packages was not installed, you may need the follow runtime depedency packages installed:

* libevent-2.0-5
* libgdal1i

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

## Install as ```systemd``` Service

Example ```systemd``` service file at ```/etc/systemd/system/moidem.service```:

```shell
[Unit]
Description=moidem elevation service
Requires=network.target
After=multi-user.target

[Service]
Type=simple
Restart=always
RestartSec=10
StartLimitIntervalSec=0
ExecStart=/usr/local/sbin/moidemd /etc/dem_20m.tif

[Install]
WantedBy=multi-user.target
```

To enable this service:

```shell
sudo systemctl enable moidem.service
```

To start the service:

```shell
sudo systemctl start moidem.service
```

To check status of the service:

```shell
systemctl status moidem.service
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
