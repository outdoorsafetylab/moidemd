#!/bin/bash -e

mkdir -p /build
cp -a /source /build/src

cd /build/src
make
debuild -b -us -uc

chown -R $USER:$GROUP /build
cp -a /build/*.deb /output/
ls -l /output
