FROM ubuntu:18.04 AS builder

ARG BRANCH

RUN apt-get update
RUN apt-get install -y --no-install-recommends \
        build-essential libgdal-dev libevent-dev libjson-c-dev
RUN apt-get install -y --no-install-recommends \
        ca-certificates git wget p7zip-full

RUN git clone https://github.com/outdoorsafetylab/demd.git /source
WORKDIR /source
RUN git checkout ${BRANCH} && make
RUN mkdir -p /dem
WORKDIR /dem
RUN wget --no-check-certificate -O dem.7z "http://dtm.moi.gov.tw/tif/taiwan_TIF格式.7z" && 7za x dem.7z
RUN wget --no-check-certificate -O dem.7z "http://dtm.moi.gov.tw/tif/金門.7z" && 7za x dem.7z
RUN wget --no-check-certificate -O dem.7z "http://dtm.moi.gov.tw/tif/澎湖.7z" && 7za x dem.7z

FROM ubuntu:18.04 AS runtime

RUN apt-get update && \
        apt-get install -y --no-install-recommends \ 
        libevent-2.1-6 libgdal20

RUN mkdir -p /usr/sbin/
COPY --from=builder /source/demd /usr/sbin/
RUN mkdir -p /var/lib/moidemd/
COPY --from=builder /dem/*.tif /var/lib/moidemd/

CMD ["/usr/sbin/demd", "-p", "8080", "/var/lib/moidemd/"]

EXPOSE 8080
