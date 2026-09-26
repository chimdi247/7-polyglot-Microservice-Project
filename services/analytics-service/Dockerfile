# syntax=docker/dockerfile:1
FROM php:8.3-cli-alpine

WORKDIR /app

# curl (CLI, for HEALTHCHECK) + curl-dev/postgresql-dev (headers, to build the
# PHP curl and pdo_pgsql extensions router.php needs) + $PHPIZE_DEPS (build
# toolchain for docker-php-ext-install / pecl), removed again once extensions
# are built. apcu is a PECL extension (not bundled with the php image), used
# here as a small shared-memory counter store for the /metrics endpoint --
# PHP's built-in server starts a fresh script execution per request with no
# persistent process state by default, so APCu is what lets request counts
# actually accumulate across requests. See observability/README.md.
RUN apk add --no-cache curl postgresql-dev curl-dev \
    && apk add --no-cache --virtual .build-deps $PHPIZE_DEPS \
    && docker-php-ext-install pdo pdo_pgsql curl \
    && pecl install apcu \
    && docker-php-ext-enable apcu \
    && apk del .build-deps \
    && addgroup -S app && adduser -S app -G app

RUN echo "apc.enable_cli=1" >> /usr/local/etc/php/conf.d/apcu.ini

COPY router.php .

USER app

EXPOSE 8087

HEALTHCHECK --interval=15s --timeout=5s --start-period=10s --retries=5 \
  CMD curl -f http://localhost:8087/health || exit 1

CMD ["php", "-S", "0.0.0.0:8087", "router.php"]
