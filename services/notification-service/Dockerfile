# syntax=docker/dockerfile:1
FROM ruby:3.3-slim
WORKDIR /app

RUN apt-get update \
    && apt-get install -y --no-install-recommends curl build-essential libpq-dev \
    && rm -rf /var/lib/apt/lists/*

COPY Gemfile Gemfile.lock ./
RUN bundle install

COPY app.rb .

RUN groupadd -r app && useradd -r -g app app
USER app

EXPOSE 8086

HEALTHCHECK --interval=15s --timeout=5s --start-period=10s --retries=5 \
  CMD curl -f http://localhost:8086/health || exit 1

CMD ["bundle", "exec", "ruby", "app.rb"]
