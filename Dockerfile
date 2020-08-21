FROM alpine:3.12

RUN apk add --no-cache crystal shards \
                       musl-dev zlib-dev openssl-dev \
 && adduser --uid 7865 --system rory
USER rory

ADD --chown=rory:nogroup . /src
WORKDIR /src

RUN shards build --release
CMD ["/src/bin/rory"]
