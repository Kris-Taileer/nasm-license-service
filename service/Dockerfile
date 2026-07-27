FROM debian:bookworm-slim AS builder
RUN apt-get update && apt-get install -y --no-install-recommends nasm binutils make \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /build
COPY Makefile .
COPY src ./src
RUN make

FROM debian:bookworm-slim
RUN useradd --system --create-home --home-dir /app --shell /usr/sbin/nologin license
COPY --from=builder /build/license-service /usr/local/bin/license-service
WORKDIR /app
USER license
EXPOSE 4444
CMD ["/usr/local/bin/license-service"]
