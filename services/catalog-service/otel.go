package main

import (
	"context"
	"log"
	"os"

	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracegrpc"
	"go.opentelemetry.io/otel/sdk/resource"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
	semconv "go.opentelemetry.io/otel/semconv/v1.26.0"
)

// setupTracing wires up OpenTelemetry tracing: catalog-service uses the
// otelhttp middleware (see main.go) to auto-instrument every request/
// response and outgoing DB call span-wise, so no manual span code is
// needed at each handler. Traces export via OTLP to the otel-collector.
//
// Go has no bytecode-weaving equivalent of the Java/Python "attach an
// agent and get every library instrumented for free" approach, so this
// is a few lines of explicit SDK setup rather than truly zero-code --
// see observability/README.md for the full picture across languages.
//
// Returns a shutdown func; on any setup error it logs a warning and
// returns a no-op shutdown so a broken/unreachable collector can never
// stop the service itself from starting.
func setupTracing(ctx context.Context) func(context.Context) error {
	endpoint := os.Getenv("OTEL_EXPORTER_OTLP_ENDPOINT")
	if endpoint == "" {
		log.Println("OTEL_EXPORTER_OTLP_ENDPOINT not set, tracing disabled")
		return func(context.Context) error { return nil }
	}

	exporter, err := otlptracegrpc.New(ctx, otlptracegrpc.WithEndpointURL(endpoint), otlptracegrpc.WithInsecure())
	if err != nil {
		log.Printf("failed to create OTLP trace exporter, continuing without tracing: %v", err)
		return func(context.Context) error { return nil }
	}

	serviceName := os.Getenv("OTEL_SERVICE_NAME")
	if serviceName == "" {
		serviceName = "catalog-service"
	}

	res, err := resource.New(ctx, resource.WithAttributes(semconv.ServiceNameKey.String(serviceName)))
	if err != nil {
		res = resource.Default()
	}

	tp := sdktrace.NewTracerProvider(
		sdktrace.WithBatcher(exporter),
		sdktrace.WithResource(res),
	)
	otel.SetTracerProvider(tp)

	return tp.Shutdown
}
