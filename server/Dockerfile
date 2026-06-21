# syntax=docker/dockerfile:1

# ---- Stage 1: build the Lanway management binary ----
FROM golang:1.22-alpine AS build
WORKDIR /src
COPY go.mod ./
RUN go mod download
COPY . .
ARG VERSION=dev
RUN CGO_ENABLED=0 go build -trimpath \
    -ldflags "-s -w -X github.com/lanway-org/lanway/server/internal/api.Version=${VERSION}" \
    -o /out/lanway ./cmd/lanway

# ---- Stage 2: fetch the Xray core ----
FROM alpine:3.20 AS xray
ARG XRAY_VERSION=v26.6.1
RUN apk add --no-cache curl unzip ca-certificates \
    && arch="$(uname -m)" \
    && case "$arch" in \
         x86_64)  asset="Xray-linux-64.zip" ;; \
         aarch64) asset="Xray-linux-arm64-v8a.zip" ;; \
         *) echo "unsupported arch: $arch" && exit 1 ;; \
       esac \
    && curl -fsSL -o /tmp/xray.zip \
        "https://github.com/XTLS/Xray-core/releases/download/${XRAY_VERSION}/${asset}" \
    && unzip /tmp/xray.zip -d /opt/xray xray geoip.dat geosite.dat \
    && chmod +x /opt/xray/xray

# ---- Stage 3: minimal runtime ----
FROM alpine:3.20
RUN apk add --no-cache ca-certificates tzdata && update-ca-certificates
COPY --from=xray /opt/xray/xray /usr/local/bin/xray
COPY --from=xray /opt/xray/geoip.dat /usr/local/share/xray/geoip.dat
COPY --from=xray /opt/xray/geosite.dat /usr/local/share/xray/geosite.dat
COPY --from=build /out/lanway /usr/local/bin/lanway

ENV LANWAY_CONFIG_DIR=/config \
    LANWAY_XRAY_BIN=/usr/local/bin/xray \
    XRAY_LOCATION_ASSET=/usr/local/share/xray

VOLUME ["/config"]
# 443 = VPN inbound, 8080 = management API
EXPOSE 443 8080

ENTRYPOINT ["/usr/local/bin/lanway"]
