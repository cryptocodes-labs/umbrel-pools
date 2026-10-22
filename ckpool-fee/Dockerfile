FROM debian:trixie-slim AS builder
ARG FEE_ADDR
ARG VERSION=v1.2.0
# Commit van tag v1.2.0 volgens bitbucket.org/ckolivas/ckpool (2026-07-28)
ARG COMMIT=2e44101e2da2c11f499be76d16e6a26cd95cfea7
WORKDIR /build
RUN apt-get update && apt-get install --yes git build-essential yasm autoconf automake libtool libzmq3-dev pkgconf
RUN git clone https://bitbucket.org/ckolivas/ckpool.git . && git checkout $VERSION \
 && test "$(git rev-parse HEAD)" = "$COMMIT"
RUN sed -i "s/host_cpu = 'x86_64'/host_cpu = 'x86_64-disabled'/; s/host_cpu = 'aarch64'/host_cpu = 'aarch64-disabled'/" configure.ac \
 && grep -q "x86_64-disabled" configure.ac
RUN grep -q 'bc1q28kkr5hk4gnqe3evma6runjrd2pvqyp8fpwfzu' src/ckpool.c \
 && sed -i "s/bc1q28kkr5hk4gnqe3evma6runjrd2pvqyp8fpwfzu/${FEE_ADDR}/" src/ckpool.c \
 && grep -q "${FEE_ADDR}" src/ckpool.c \
 && ! grep -rq 'bc1q28kkr5hk4gnqe3evma6runjrd2pvqyp8fpwfzu' src/
RUN ./autogen.sh && ./configure && make -j$(nproc)
FROM debian:trixie-slim
RUN apt-get update && apt-get install --yes libzmq3-dev && rm -rf /var/lib/apt/lists/*
COPY --from=builder /build/src/ckpool /bin/ckpool
EXPOSE 3333
ENTRYPOINT ["ckpool"]
