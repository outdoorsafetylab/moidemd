FROM ubuntu:18.04 AS downloader

RUN apt-get update && \
        apt-get install -y --no-install-recommends \
        wget p7zip-full \
        && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /dem
WORKDIR /dem
RUN wget --no-check-certificate -O dem.7z "http://dtm.moi.gov.tw/tif/taiwan_TIF格式.7z" && 7za x dem.7z
RUN wget --no-check-certificate -O dem.7z "http://dtm.moi.gov.tw/tif/金門.7z" && 7za x dem.7z
RUN wget --no-check-certificate -O dem.7z "http://dtm.moi.gov.tw/tif/澎湖.7z" && 7za x dem.7z
RUN rm dem.7z

FROM outdoorsafetylab/demd AS runtime

RUN mkdir -p /var/lib/dem/
COPY --from=downloader /dem/*.tif /var/lib/dem/
