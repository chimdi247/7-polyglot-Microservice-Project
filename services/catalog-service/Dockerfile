# syntax=docker/dockerfile:1
FROM golang:1.22-alpine AS build
WORKDIR /app

COPY . .
# Tidy must run after the source is copied: it scans the .go files for
# imports, and go.sum predates the Prometheus/OpenTelemetry dependencies.
RUN go mod tidy
RUN CGO_ENABLED=0 GOOS=linux go build -o /catalog-service .

# ---- Runtime ----
FROM alpine:3.20 AS runtime
WORKDIR /app

RUN apk add --no-cache curl ca-certificates \
    && addgroup -S app && adduser -S app -G app
USER app

COPY --from=build /catalog-service .

EXPOSE 8082

HEALTHCHECK --interval=15s --timeout=5s --start-period=15s --retries=5 \
  CMD curl -f http://localhost:8082/health || exit 1

ENTRYPOINT ["./catalog-service"]
