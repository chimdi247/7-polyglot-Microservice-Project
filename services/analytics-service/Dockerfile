# syntax=docker/dockerfile:1
FROM php:8.3-cli-alpine
WORKDIR /app

# curl (CLI, for HEALTHCHECK) + curl-dev/postgresql-dev (headers, to build the
# PHP curl and pdo_pgsql extensions router.php needs) + $PHPIZE_DEPS (build
# toolchain for docker-php-ext-install), removed again once extensions are built.
RUN apk add --no-cache curl postgresql-dev curl-dev \
    && apk add --no-cache --virtual .build-deps $PHPIZE_DEPS \
    && docker-php-ext-install pdo pdo_pgsql curl \
    && apk del .build-deps \
    && addgroup -S app && adduser -S app -G app

COPY router.php .

USER app

EXPOSE 8087

HEALTHCHECK --interval=15s --timeout=5s --start-period=10s --retries=5 \
  CMD curl -f http://localhost:8087/health || exit 1

CMD ["php", "-S", "0.0.0.0:8087", "router.php"]
