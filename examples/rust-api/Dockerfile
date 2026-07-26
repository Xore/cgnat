# Multi-stage build with dependency caching:
# stage 1 builds deps against a dummy main.rs (cached until Cargo.toml changes),
# then compiles the real source. Final image is Alpine + one static musl binary.
FROM rust:1-alpine AS build
RUN apk add --no-cache musl-dev
WORKDIR /src

# Cache dependency compilation
COPY Cargo.toml ./
RUN mkdir src \
    && echo 'fn main() {}' > src/main.rs \
    && cargo build --release \
    && rm -rf src

# Build the real binary (frontend embedded via include_str!)
COPY static ./static
COPY src ./src
RUN touch src/main.rs && cargo build --release

FROM alpine:3.24
RUN adduser -D -H app && mkdir -p /data && chown app /data
COPY --from=build /src/target/release/blog-api /usr/local/bin/blog-api

ENV PORT=5004
EXPOSE 5004
USER app

HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
  CMD wget -q --spider http://127.0.0.1:5004/health || exit 1

CMD ["blog-api"]
