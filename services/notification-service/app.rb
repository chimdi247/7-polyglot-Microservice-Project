require "sinatra"
require "json"
require "pg"
require "prometheus/client"
require "prometheus/client/formatter/text"

# OpenTelemetry auto-instrumentation for Sinatra/pg: wrapped in
# begin/rescue since telemetry setup must never be able to prevent
# the service itself from starting. Once configured, the Sinatra and
# PG instrumentation gems patch request handling and DB calls
# automatically -- no per-route code changes below. Traces export via
# OTLP to the otel-collector (see observability/README.md).
begin
  require "opentelemetry/sdk"
  require "opentelemetry/exporter/otlp"
  require "opentelemetry/instrumentation/sinatra"
  require "opentelemetry/instrumentation/pg"

  OpenTelemetry::SDK.configure do |c|
    c.service_name = ENV.fetch("OTEL_SERVICE_NAME", "notification-service")
    c.use "OpenTelemetry::Instrumentation::Sinatra"
    c.use "OpenTelemetry::Instrumentation::PG"
  end
rescue StandardError => e
  warn "OpenTelemetry failed to initialize, continuing without it: #{e.message}"
end

# Direct Prometheus exposition (rather than routing metrics through
# OpenTelemetry) so metric names are exact and under our control --
# scraped directly at /metrics, see observability/prometheus/prometheus.yml.
prometheus = Prometheus::Client.registry
HTTP_REQUESTS_TOTAL = prometheus.counter(
  :http_requests_total,
  docstring: "Total HTTP requests, by method/path/status",
  labels: [:method, :path, :status]
)
HTTP_REQUEST_DURATION = prometheus.histogram(
  :http_request_duration_seconds,
  docstring: "HTTP request duration in seconds",
  labels: [:method, :path]
)

set :bind, "0.0.0.0"
set :port, 8086
set :server, :puma

# Local/demo environment:
# allow requests forwarded through Vite using the EC2 host/IP
set :host_authorization, { permitted_hosts: [] }

set :protection, except: [:json_csrf]

DB_URL = ENV.fetch(
  "NOTIFICATION_DB_URL",
  "postgres://microapp:microapp123@127.0.0.1:5432/notification_db"
)

def db
  PG.connect(DB_URL)
end

connection = db
connection.exec <<~SQL
  CREATE TABLE IF NOT EXISTS notifications (
    id BIGSERIAL PRIMARY KEY,
    recipient VARCHAR(200) NOT NULL,
    type VARCHAR(50) NOT NULL,
    subject VARCHAR(200) NOT NULL,
    message TEXT NOT NULL,
    is_read BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
  )
SQL

count = connection.exec("SELECT COUNT(*) AS count FROM notifications")[0]["count"].to_i
if count.zero?
  connection.exec_params(
    "INSERT INTO notifications(recipient,type,subject,message) VALUES($1,$2,$3,$4)",
    [
      "admin@devopsshack.com",
      "WELCOME",
      "Polyglot platform is ready",
      "Ruby Notification Service is ready to receive order and payment events."
    ]
  )
end
connection.close

before do
  content_type :json
  headers(
    "Access-Control-Allow-Origin" => "*",
    "Access-Control-Allow-Methods" => "GET,POST,OPTIONS",
    "Access-Control-Allow-Headers" => "Content-Type,Authorization"
  )
  @request_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
end

after do
  # Skip /metrics itself so the scrape endpoint doesn't inflate its
  # own counters on every Prometheus scrape.
  next if request.path_info == "/metrics"
  duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - (@request_start || Process.clock_gettime(Process::CLOCK_MONOTONIC))
  HTTP_REQUESTS_TOTAL.increment(labels: { method: request.request_method, path: request.path_info, status: response.status.to_s })
  HTTP_REQUEST_DURATION.observe(duration, labels: { method: request.request_method, path: request.path_info })
end

get "/metrics" do
  content_type "text/plain"
  Prometheus::Client::Formatter::Text.new.marshal(prometheus)
end

options "*" do
  status 204
end

get "/health" do
  connection = db
  connection.exec("SELECT 1")
  connection.close
  { service: "notification-service", status: "UP", language: "Ruby" }.to_json
end

get "/notifications" do
  connection = db
  recipient = params["recipient"]
  result =
    if recipient && !recipient.strip.empty?
      connection.exec_params(
        "SELECT * FROM notifications WHERE lower(recipient)=lower($1) ORDER BY id DESC",
        [recipient]
      )
    else
      connection.exec("SELECT * FROM notifications ORDER BY id DESC")
    end

  rows = result.map do |row|
    {
      id: row["id"].to_i,
      recipient: row["recipient"],
      type: row["type"],
      subject: row["subject"],
      message: row["message"],
      is_read: row["is_read"] == "t",
      created_at: row["created_at"]
    }
  end
  connection.close
  rows.to_json
end

post "/notifications" do
  payload = JSON.parse(request.body.read)
  required = %w[recipient type subject message]
  missing = required.select { |k| payload[k].nil? || payload[k].to_s.strip.empty? }
  halt 400, { error: "missing fields: #{missing.join(', ')}" }.to_json unless missing.empty?

  connection = db
  result = connection.exec_params(
    "INSERT INTO notifications(recipient,type,subject,message) VALUES($1,$2,$3,$4) RETURNING *",
    [payload["recipient"], payload["type"], payload["subject"], payload["message"]]
  )
  row = result[0]
  connection.close
  status 201
  {
    id: row["id"].to_i,
    recipient: row["recipient"],
    type: row["type"],
    subject: row["subject"],
    message: row["message"],
    is_read: false,
    created_at: row["created_at"]
  }.to_json
rescue JSON::ParserError
  halt 400, { error: "invalid JSON" }.to_json
end

post "/notifications/:id/read" do
  connection = db
  result = connection.exec_params(
    "UPDATE notifications SET is_read=TRUE WHERE id=$1 RETURNING *",
    [params["id"]]
  )
  if result.ntuples.zero?
    connection.close
    halt 404, { error: "notification not found" }.to_json
  end
  row = result[0]
  connection.close
  {
    id: row["id"].to_i,
    recipient: row["recipient"],
    type: row["type"],
    subject: row["subject"],
    message: row["message"],
    is_read: true,
    created_at: row["created_at"]
  }.to_json
end
