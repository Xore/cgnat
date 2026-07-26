# Static Go binary in a scratch image (~7 MB, no shell/libc).
FROM golang:1.26-alpine AS build
WORKDIR /src
COPY go.mod .
COPY *.go .
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /gateway .

FROM scratch
COPY --from=build /gateway /gateway

ENV LISTEN_ADDR=:8080
EXPOSE 8080

# Non-root (nobody). scratch has no /etc/passwd, so use the numeric UID.
USER 65534

# The gateway serves an unauthenticated /_auth/health for Docker/Traefik probes
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
  CMD ["/gateway", "-healthcheck"]

ENTRYPOINT ["/gateway"]
