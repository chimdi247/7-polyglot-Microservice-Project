module devopsshack/catalog-service

go 1.22

require (
	github.com/lib/pq v1.10.9
	github.com/prometheus/client_golang v1.20.5
	go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp v0.56.0
	go.opentelemetry.io/otel v1.31.0
	go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracegrpc v1.31.0
	go.opentelemetry.io/otel/sdk v1.31.0
)
