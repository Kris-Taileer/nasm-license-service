FROM debian:bookworm-slim AS builder
RUN apt-get update && apt-get install -y --no-install-recommends nasm binutils make \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /build
COPY Makefile .
COPY src ./src
RUN make

FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends socat \
    && rm -rf /var/lib/apt/lists/*
COPY --from=builder /build/license-service /usr/local/bin/license-service
EXPOSE 4444
CMD ["socat", "TCP-LISTEN:4444,reuseaddr,fork", "EXEC:/usr/local/bin/license-service"]
