FROM ubuntu:18.04 as builder

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

COPY --from=builder /src/moidemd /usr/local/sbin/
RUN mkdir /var/lib/moidemd/
COPY DEMg_geoid2014_20m_20190515.tif /var/lib/moidemd/

CMD ["/usr/local/sbin/moidemd", "-p", "8080", "/var/lib/moidemd/DEMg_geoid2014_20m_20190515.tif"]

EXPOSE 8080
