# syntax=docker/dockerfile:1
# check=error=true

ARG RUBY_VERSION=3.4.4

# ────────────────────────────────────────
# Base image
FROM docker.io/library/ruby:${RUBY_VERSION}-slim AS base

WORKDIR /rails

# Step 1: Bootstrap – install keyring + essentials, clean cache in same layer
RUN apt-get update -qq --allow-releaseinfo-change --allow-insecure-repositories && \
    apt-get install --no-install-recommends -y \
      debian-archive-keyring ca-certificates curl gnupg && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/* && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Step 2: Switch to secure signed-by sources using the just-installed keyring
RUN rm -f /etc/apt/sources.list /etc/apt/sources.list.d/* && \
    echo "deb [signed-by=/usr/share/keyrings/debian-archive-keyring.gpg] http://deb.debian.org/debian bookworm main" > /etc/apt/sources.list && \
    echo "deb [signed-by=/usr/share/keyrings/debian-archive-keyring.gpg] http://deb.debian.org/debian bookworm-updates main" >> /etc/apt/sources.list && \
    echo "deb [signed-by=/usr/share/keyrings/debian-archive-keyring.gpg] http://security.debian.org/debian-security bookworm-security main" >> /etc/apt/sources.list

# Step 3: Now install runtime deps securely
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
      libjemalloc2 libvips postgresql-client && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*

# Production env (unchanged)
ENV RAILS_ENV="production" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development test" \
    BUNDLE_IGNORE_CONFIGURED_GROUPS_WITHOUT=true

# ────────────────────────────────────────
# Build stage (unchanged from your last working version)
FROM base AS build

RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
      build-essential git libpq-dev libyaml-dev pkg-config nodejs && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*

COPY Gemfile Gemfile.lock ./
RUN bundle install && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git && \
    bundle exec bootsnap precompile --gemfile

COPY . .

RUN SECRET_KEY_BASE_DUMMY=1 ./bin/rails assets:precompile
RUN bundle exec bootsnap precompile app/ lib/

# Final stage (unchanged)
FROM base

COPY --from=build "${BUNDLE_PATH}" "${BUNDLE_PATH}"
COPY --from=build /rails /rails

RUN groupadd --system --gid 1000 rails && \
    useradd rails --uid 1000 --gid 1000 --create-home --shell /bin/bash && \
    chown -R rails:rails db log storage tmp

USER 1000:1000

ENTRYPOINT ["/rails/bin/docker-entrypoint"]

EXPOSE 80
CMD ["./bin/thrust", "./bin/rails", "server", "-b", "0.0.0.0"]