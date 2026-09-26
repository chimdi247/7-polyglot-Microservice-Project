# syntax=docker/dockerfile:1
FROM node:20-alpine
WORKDIR /app

RUN apk add --no-cache curl \
    && addgroup -S app && adduser -S app -G app

COPY package*.json ./
# Not `npm ci`: package.json now includes prom-client and OpenTelemetry
# packages that aren't in the committed package-lock.json (that lock
# predates them). `npm install` resolves and updates the lock here.
RUN npm install --omit=dev

COPY src ./src

USER app

EXPOSE 8083

HEALTHCHECK --interval=15s --timeout=5s --start-period=10s --retries=5 \
  CMD curl -f http://localhost:8083/health || exit 1

CMD ["npm", "start"]
