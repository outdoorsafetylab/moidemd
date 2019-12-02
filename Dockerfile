FROM ubuntu:18.04 AS builder

ARG BRANCH

RUN apt-get update
RUN apt-get install -y --no-install-recommends \
        build-essential libgdal-dev libevent-dev libjson-c-dev
RUN apt-get install -y --no-install-recommends \
        ca-certificates git unzip

RUN git clone https://github.com/outdoorsafetylab/demd.git /source
WORKDIR /source
RUN git checkout ${BRANCH} && make
RUN mkdir -p /dem
COPY moidem.zip /dem
WORKDIR /dem
RUN unzip moidem.zip

FROM ubuntu:18.04 AS runtime

RUN apt-get update && \
        apt-get install -y --no-install-recommends \ 
        libevent-2.1-6 libgdal20

RUN mkdir -p /usr/sbin/
COPY --from=builder /source/demd /usr/sbin/
RUN mkdir -p /var/lib/moidemd/
COPY --from=builder /dem/*.tif /var/lib/moidemd/

CMD ["sh", "-c", "/usr/sbin/demd -p $PORT /var/lib/moidemd/"]
