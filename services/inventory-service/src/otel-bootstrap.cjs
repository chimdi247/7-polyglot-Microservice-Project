// OpenTelemetry bootstrap, loaded before any application code via
// NODE_OPTIONS="--require ./src/otel-bootstrap.cjs" (see
// docker-compose.yml). Named .cjs (not .js) deliberately: this
// service's package.json sets "type": "module", so a plain .js file
// here would be loaded as ESM and `require` wouldn't be defined --
// .cjs forces CommonJS regardless of that setting, which --require
// needs. Zero-code auto-instrumentation: patches Express/HTTP/pg
// automatically via getNodeAutoInstrumentations() -- no source
// changes needed in src/index.js beyond the /metrics endpoint (which
// uses prom-client directly for reliable, known metric names rather
// than routing through OTel -- see observability/README.md).
//
// Wrapped in try/catch: telemetry must never be able to prevent the
// actual service from starting.
try {
  const { NodeSDK } = require("@opentelemetry/sdk-node");
  const {
    getNodeAutoInstrumentations,
  } = require("@opentelemetry/auto-instrumentations-node");
  const {
    OTLPTraceExporter,
  } = require("@opentelemetry/exporter-trace-otlp-proto");

  const sdk = new NodeSDK({
    traceExporter: new OTLPTraceExporter(),
    instrumentations: [getNodeAutoInstrumentations()],
  });

  sdk.start();

  const shutdown = () => {
    sdk
      .shutdown()
      .catch((err) => console.error("Error shutting down OpenTelemetry", err))
      .finally(() => process.exit(0));
  };
  process.on("SIGTERM", shutdown);
  process.on("SIGINT", shutdown);

  console.log("OpenTelemetry auto-instrumentation started");
} catch (error) {
  console.warn("OpenTelemetry failed to initialize, continuing without it:", error);
}
