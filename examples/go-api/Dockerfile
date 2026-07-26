# Multi-stage build: compile a fully static binary (frontend embedded via
# go:embed), ship it in scratch. Final image is ~10 MB with no shell or libc.
FROM golang:1.23-alpine AS build
WORKDIR /src

COPY go.mod .
COPY main.go .
COPY static ./static
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /server .

# Pre-create the data dir so its ownership survives the COPY into scratch
# (a named volume mounted at /data inherits it on first use)
RUN mkdir -p /data && chown 65534:65534 /data

FROM scratch
COPY --from=build /server /server
COPY --from=build --chown=65534:65534 /data /data

ENV PORT=5003
EXPOSE 5003

# Non-root (nobody). scratch has no /etc/passwd, so use the numeric UID.
USER 65534

# The binary probes itself — no wget/curl needed in scratch
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
  CMD ["/server", "-healthcheck"]

ENTRYPOINT ["/server"]
