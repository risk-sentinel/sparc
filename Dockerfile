# syntax=docker/dockerfile:1
# check=error=true

ARG RUBY_VERSION=3.4.4

# ────────────────────────────────────────
# Bootstrap stage: APT keyring + sources setup
# This stage is discarded — only the keyring, sources list,
# and CA certificates are copied to the base stage.
# curl, gnupg, perl, and all transitive dependencies
# (libnghttp2, libldap, libgssapi-krb5, libtasn1, libgcrypt, etc.)
# never enter the production image.
# See issue #342 for the full package analysis.
FROM docker.io/library/ruby:${RUBY_VERSION}-slim AS bootstrap

RUN apt-get update -qq --allow-releaseinfo-change --allow-insecure-repositories && \
    apt-get install --no-install-recommends -y \
      debian-archive-keyring ca-certificates curl gnupg && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*

# Configure secure signed-by APT sources
RUN rm -f /etc/apt/sources.list /etc/apt/sources.list.d/* && \
    echo "deb [signed-by=/usr/share/keyrings/debian-archive-keyring.gpg] http://deb.debian.org/debian bookworm main" > /etc/apt/sources.list && \
    echo "deb [signed-by=/usr/share/keyrings/debian-archive-keyring.gpg] http://deb.debian.org/debian bookworm-updates main" >> /etc/apt/sources.list && \
    echo "deb [signed-by=/usr/share/keyrings/debian-archive-keyring.gpg] http://security.debian.org/debian-security bookworm-security main" >> /etc/apt/sources.list

# ────────────────────────────────────────
# Base image — runtime only, minimal attack surface
FROM docker.io/library/ruby:${RUBY_VERSION}-slim AS base

WORKDIR /rails

# Copy only APT config and certificates from bootstrap — no curl, gnupg, or perl
COPY --from=bootstrap /etc/apt/sources.list /etc/apt/sources.list
COPY --from=bootstrap /usr/share/keyrings/debian-archive-keyring.gpg /usr/share/keyrings/debian-archive-keyring.gpg
COPY --from=bootstrap /etc/ssl/certs/ /etc/ssl/certs/
COPY --from=bootstrap /usr/share/ca-certificates/ /usr/share/ca-certificates/

# Install runtime deps only — no build tools, no unused packages
# NOTE: libvips was removed — it pulled in ImageMagick, libtiff, libhdf5,
# poppler, OpenJPEG, OpenEXR, libaom and ~200+ CVEs. SPARC uses Active Storage
# for document file storage only (no image transformations/variants).
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
      libjemalloc2 postgresql-client && \
    apt-get upgrade -y && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*

# Production env
ENV RAILS_ENV="production" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development test" \
    BUNDLE_IGNORE_CONFIGURED_GROUPS_WITHOUT=true

# ────────────────────────────────────────
# Build stage
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

# ────────────────────────────────────────
# Final stage — production image
FROM base

COPY --from=build "${BUNDLE_PATH}" "${BUNDLE_PATH}"
COPY --from=build /rails /rails

RUN groupadd --system --gid 1000 rails && \
    useradd rails --uid 1000 --gid 1000 --create-home --shell /bin/bash && \
    chown -R rails:rails db log storage tmp

USER 1000:1000

ENTRYPOINT ["/rails/bin/docker-entrypoint"]

EXPOSE 3000
CMD ["./bin/rails", "server", "-b", "0.0.0.0", "-p", "3000"]
