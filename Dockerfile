FROM ubuntu:18.04 as build

LABEL description="Build container - moidemd"

RUN apt-get update && apt-get install -y \ 
    build-essential libgdal-dev libevent-dev libjson-c-dev

RUN mkdir /src/
COPY Makefile main.cpp /src/
WORKDIR /src
RUN make

FROM ubuntu:18.04 as runtime

LABEL description="Run container - moidemd"

RUN apt-get update && apt-get install -y \ 
    libevent-2.1-6 libgdal20

COPY --from=build /src/moidemd /usr/local/sbin/
COPY DEM_20m.tif /etc/

CMD /usr/local/sbin/moidemd -p 8080 /etc/DEM_20m.tif

EXPOSE 8080