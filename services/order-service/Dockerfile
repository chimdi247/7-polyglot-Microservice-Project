# syntax=docker/dockerfile:1
FROM python:3.12-slim
WORKDIR /app

RUN apt-get update \
    && apt-get install -y --no-install-recommends curl \
    && rm -rf /var/lib/apt/lists/* \
    && addgroup --system app && adduser --system --ingroup app app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app ./app

USER app

EXPOSE 8084

HEALTHCHECK --interval=15s --timeout=5s --start-period=10s --retries=5 \
  CMD curl -f http://localhost:8084/health || exit 1

# opentelemetry-instrument: zero-code auto-instrumentation, patches
# FastAPI/httpx/psycopg2/logging automatically at startup based on the
# opentelemetry-instrumentation-* packages installed (requirements.txt)
# and OTEL_* environment variables (docker-compose.yml). See
# observability/README.md.
CMD ["opentelemetry-instrument", "uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8084"]
