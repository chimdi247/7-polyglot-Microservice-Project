<?php
declare(strict_types=1);

header("Content-Type: application/json");
header("Access-Control-Allow-Origin: *");
header("Access-Control-Allow-Headers: Content-Type, Authorization");
header("Access-Control-Allow-Methods: GET, POST, OPTIONS");

if ($_SERVER["REQUEST_METHOD"] === "OPTIONS") {
    http_response_code(204);
    exit;
}

// ------------------------------------------------------------------
// Metrics (Prometheus text exposition), backed by APCu.
//
// PHP's built-in server (php -S) runs each request as a fresh script
// execution with no persistent in-process state -- a plain PHP
// variable can't accumulate a counter across requests the way a
// long-running Node/Java/Go process can. APCu is shared memory scoped
// to the PHP process itself, so it survives across requests here
// (see Dockerfile). Scraped directly at /metrics, see
// observability/prometheus/prometheus.yml.
//
// Full OpenTelemetry trace auto-instrumentation was intentionally
// left out for this service specifically -- see
// observability/README.md for why (PHP's true zero-code
// auto-instrumentation needs a compiled PECL extension whose exact
// setup couldn't be verified without running it).
// ------------------------------------------------------------------
function metrics_record(string $method, string $path, int $status, float $durationSeconds): void {
    if (!function_exists("apcu_enabled") || !apcu_enabled()) {
        return;
    }
    $counterKey = "http_requests_total:{$method}:{$path}:{$status}";
    apcu_add($counterKey, 0);
    apcu_inc($counterKey);

    // A small fixed-bucket histogram, tracked manually since APCu only
    // stores scalars/arrays, not a Prometheus client object.
    $buckets = [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10];
    foreach ($buckets as $bucket) {
        if ($durationSeconds <= $bucket) {
            $bucketKey = "http_request_duration_seconds_bucket:{$method}:{$path}:{$bucket}";
            apcu_add($bucketKey, 0);
            apcu_inc($bucketKey);
        }
    }
    $sumKey = "http_request_duration_seconds_sum:{$method}:{$path}";
    $countKey = "http_request_duration_seconds_count:{$method}:{$path}";
    apcu_add($sumKey, 0.0);
    // PHP's built-in server (see Dockerfile's CMD) handles requests
    // one at a time, not concurrently, so there's no real race here --
    // a plain fetch-then-store is enough (apcu_cas() only supports
    // integers, not floats, so it isn't an option for this counter
    // anyway).
    $currentSum = apcu_fetch($sumKey);
    apcu_store($sumKey, ($currentSum === false ? 0.0 : $currentSum) + $durationSeconds);
    apcu_add($countKey, 0);
    apcu_inc($countKey);
}

function metrics_render(): string {
    if (!function_exists("apcu_enabled") || !apcu_enabled()) {
        return "# APCu not available\n";
    }
    $lines = [
        "# HELP http_requests_total Total HTTP requests, by method/path/status",
        "# TYPE http_requests_total counter",
    ];
    $iterator = new APCUIterator("/^http_requests_total:/");
    foreach ($iterator as $entry) {
        [, $method, $path, $status] = explode(":", $entry["key"], 4);
        $lines[] = sprintf('http_requests_total{method="%s",path="%s",status="%s"} %d', $method, $path, $status, $entry["value"]);
    }

    $lines[] = "# HELP http_request_duration_seconds HTTP request duration in seconds";
    $lines[] = "# TYPE http_request_duration_seconds histogram";
    $bucketIterator = new APCUIterator("/^http_request_duration_seconds_bucket:/");
    foreach ($bucketIterator as $entry) {
        [, $method, $path, $bucket] = explode(":", $entry["key"], 4);
        $lines[] = sprintf('http_request_duration_seconds_bucket{method="%s",path="%s",le="%s"} %d', $method, $path, $bucket, $entry["value"]);
    }
    $sumIterator = new APCUIterator("/^http_request_duration_seconds_sum:/");
    foreach ($sumIterator as $entry) {
        [, $method, $path] = explode(":", $entry["key"], 3);
        $lines[] = sprintf('http_request_duration_seconds_sum{method="%s",path="%s"} %s', $method, $path, $entry["value"]);
    }
    $countIterator = new APCUIterator("/^http_request_duration_seconds_count:/");
    foreach ($countIterator as $entry) {
        [, $method, $path] = explode(":", $entry["key"], 3);
        $lines[] = sprintf('http_request_duration_seconds_count{method="%s",path="%s"} %d', $method, $path, $entry["value"]);
    }

    return implode("\n", $lines) . "\n";
}

$__requestStart = microtime(true);
$__requestMethod = $_SERVER["REQUEST_METHOD"];
$__requestPath = parse_url($_SERVER["REQUEST_URI"] ?? "/", PHP_URL_PATH) ?: "/";
if ($__requestPath !== "/metrics") {
    register_shutdown_function(function () use ($__requestStart, $__requestMethod, $__requestPath) {
        metrics_record($__requestMethod, $__requestPath, http_response_code() ?: 200, microtime(true) - $__requestStart);
    });
}

$dbDsn = getenv("ANALYTICS_DB_DSN") ?: "pgsql:host=127.0.0.1;port=5432;dbname=analytics_db";
$dbUser = getenv("DB_USER") ?: "microapp";
$dbPassword = getenv("DB_PASSWORD") ?: "microapp123";

$catalogUrl = getenv("CATALOG_URL") ?: "http://localhost:8082";
$inventoryUrl = getenv("INVENTORY_URL") ?: "http://localhost:8083";
$orderUrl = getenv("ORDER_URL") ?: "http://localhost:8084";
$paymentUrl = getenv("PAYMENT_URL") ?: "http://localhost:8085";

function respond(int $status, array $payload): never {
    http_response_code($status);
    echo json_encode($payload, JSON_UNESCAPED_SLASHES);
    exit;
}

try {
    $pdo = new PDO($dbDsn, $dbUser, $dbPassword, [
        PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
    ]);
    $pdo->exec("
        CREATE TABLE IF NOT EXISTS analytics_snapshots (
            id BIGSERIAL PRIMARY KEY,
            payload JSONB NOT NULL,
            created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
        )
    ");
} catch (Throwable $e) {
    respond(500, ["error" => "analytics database connection failed", "detail" => $e->getMessage()]);
}

function apiGet(string $url): array {
    $ch = curl_init($url);
    curl_setopt_array($ch, [
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_CONNECTTIMEOUT => 2,
        CURLOPT_TIMEOUT => 5,
        CURLOPT_HTTPHEADER => ["Accept: application/json"],
    ]);
    $body = curl_exec($ch);
    $status = (int) curl_getinfo($ch, CURLINFO_HTTP_CODE);
    $error = curl_error($ch);
    curl_close($ch);

    if ($body === false || $status >= 400) {
        throw new RuntimeException("API call failed for {$url}: HTTP {$status} {$error}");
    }

    $decoded = json_decode($body, true);
    return is_array($decoded) ? $decoded : [];
}

function buildSummary(string $catalogUrl, string $inventoryUrl, string $orderUrl, string $paymentUrl): array {
    $products = apiGet($catalogUrl . "/products");
    $inventory = apiGet($inventoryUrl . "/inventory");
    $orders = apiGet($orderUrl . "/orders");
    $payments = apiGet($paymentUrl . "/payments");

    $capturedRevenue = 0.0;
    $refunded = 0.0;

    foreach ($payments as $payment) {
        $amount = (float)($payment["amount"] ?? 0);
        if (($payment["status"] ?? "") === "CAPTURED") $capturedRevenue += $amount;
        if (($payment["status"] ?? "") === "REFUNDED") $refunded += $amount;
    }

    $statusBreakdown = [];
    foreach ($orders as $order) {
        $status = $order["status"] ?? "UNKNOWN";
        $statusBreakdown[$status] = ($statusBreakdown[$status] ?? 0) + 1;
    }

    $lowStock = array_values(array_filter(
        $inventory,
        fn($x) => (bool)($x["low_stock"] ?? false)
    ));

    $gross = array_reduce(
        $orders,
        fn($sum, $o) => $sum + (float)($o["total"] ?? 0),
        0.0
    );

    return [
        "generated_at" => gmdate("c"),
        "products" => count($products),
        "orders" => count($orders),
        "payments" => count($payments),
        "captured_revenue" => round($capturedRevenue, 2),
        "refunded_amount" => round($refunded, 2),
        "gross_order_value" => round($gross, 2),
        "average_order_value" => count($orders) ? round($gross / count($orders), 2) : 0,
        "low_stock_count" => count($lowStock),
        "low_stock" => $lowStock,
        "order_status" => $statusBreakdown,
        "languages" => ["Java", "Go", "Node.js", "Python", "C#", "Ruby", "PHP"],
    ];
}

$path = parse_url($_SERVER["REQUEST_URI"], PHP_URL_PATH);
$method = $_SERVER["REQUEST_METHOD"];

if ($path === "/health" && $method === "GET") {
    $pdo->query("SELECT 1");
    respond(200, ["service" => "analytics-service", "status" => "UP", "language" => "PHP"]);
}

if ($path === "/metrics" && $method === "GET") {
    header("Content-Type: text/plain; version=0.0.4");
    echo metrics_render();
    exit;
}

if ($path === "/analytics/summary" && $method === "GET") {
    try {
        respond(200, buildSummary($catalogUrl, $inventoryUrl, $orderUrl, $paymentUrl));
    } catch (Throwable $e) {
        respond(503, ["error" => "one or more upstream services are unavailable", "detail" => $e->getMessage()]);
    }
}

if ($path === "/analytics/snapshot" && $method === "POST") {
    try {
        $summary = buildSummary($catalogUrl, $inventoryUrl, $orderUrl, $paymentUrl);
        $stmt = $pdo->prepare(
            "INSERT INTO analytics_snapshots(payload) VALUES(CAST(:payload AS jsonb)) RETURNING id"
        );
        $stmt->execute([":payload" => json_encode($summary)]);
        $id = (int)$stmt->fetchColumn();
        respond(201, ["id" => $id, "summary" => $summary]);
    } catch (Throwable $e) {
        respond(503, ["error" => "could not create snapshot", "detail" => $e->getMessage()]);
    }
}

if ($path === "/analytics/snapshots" && $method === "GET") {
    $rows = $pdo->query(
        "SELECT id,payload,created_at FROM analytics_snapshots ORDER BY id DESC LIMIT 20"
    )->fetchAll(PDO::FETCH_ASSOC);

    $result = array_map(function($row) {
        return [
            "id" => (int)$row["id"],
            "payload" => json_decode($row["payload"], true),
            "created_at" => $row["created_at"],
        ];
    }, $rows);

    respond(200, ["snapshots" => $result]);
}

respond(404, ["error" => "route not found"]);
