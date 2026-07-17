# syntax=docker/dockerfile:1
# check=error=true

ARG RUBY_VERSION=3.4.4
ARG HDF_LIBS_VERSION=3.2.0

# ────────────────────────────────────────
# Bootstrap stage: APT keyring + sources setup + hdf-cli download
# This stage is discarded — only the keyring, sources list, CA certs,
# and the verified hdf binary are copied to the base stage.
# curl, gnupg, perl, and all transitive dependencies
# (libnghttp2, libldap, libgssapi-krb5, libtasn1, libgcrypt, etc.)
# never enter the production image.
# See issue #342 for the full package analysis.
FROM docker.io/library/ruby:${RUBY_VERSION}-slim AS bootstrap

ARG HDF_LIBS_VERSION

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

# Provision MITRE hdf-libs CLI for runtime translation between scanner
# formats and OSCAL/HDF artefacts (#449). Pinned via HDF_LIBS_VERSION;
# tarball SHA-256 verified against checksums.txt from the same release.
COPY bin/install-hdf.sh /tmp/install-hdf.sh
RUN mkdir -p /tmp/hdf-install && \
    HDF_LIBS_VERSION="${HDF_LIBS_VERSION}" HDF_INSTALL_DIR=/tmp/hdf-install \
      /tmp/install-hdf.sh

# ────────────────────────────────────────
# Base image — runtime only, minimal attack surface
FROM docker.io/library/ruby:${RUBY_VERSION}-slim AS base

WORKDIR /rails

# Copy only APT config and certificates from bootstrap — no curl, gnupg, or perl
COPY --from=bootstrap /etc/apt/sources.list /etc/apt/sources.list
COPY --from=bootstrap /usr/share/keyrings/debian-archive-keyring.gpg /usr/share/keyrings/debian-archive-keyring.gpg
COPY --from=bootstrap /etc/ssl/certs/ /etc/ssl/certs/
COPY --from=bootstrap /usr/share/ca-certificates/ /usr/share/ca-certificates/

# hdf-cli static binary (Go) — single file, no transitive runtime deps.
# See bin/install-hdf.sh for SHA-256 verification.
COPY --from=bootstrap /tmp/hdf-install/hdf /usr/local/bin/hdf

# Install runtime deps only — no build tools, no unused packages
# NOTE: libvips was removed — it pulled in ImageMagick, libtiff, libhdf5,
# poppler, OpenJPEG, OpenEXR, libaom and ~200+ CVEs. SPARC uses Active Storage
# for document file storage only (no image transformations/variants).
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
      libjemalloc2 postgresql-client && \
    apt-get upgrade -y && \
    # SI-2: CVE-2026-45447 (#620) — force openssl/libssl3 to the patched
    # bookworm-security build (3.0.20-1~deb12u2). openssl is reachable (TLS for
    # Puma + all outbound connections), so this CRITICAL is remediated, not
    # dispositioned. The explicit --only-upgrade also changes this layer's hash
    # so the gha apt cache can't pin a stale openssl across builds (the cause of
    # the 3.0.19 the scan flagged despite `apt-get upgrade` already running).
    apt-get install --no-install-recommends -y --only-upgrade openssl libssl3 && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/* && \
    ln -sf $(find /usr/lib -name libjemalloc.so.2 -print -quit) /usr/lib/libjemalloc.so.2

# Production env
# LD_PRELOAD: jemalloc replaces glibc malloc — eliminates memory fragmentation
#   that causes ~0.5%/hour RSS growth in Ruby processes. See issue #380.
# MALLOC_ARENA_MAX: limits glibc to 2 arenas (fallback if LD_PRELOAD is overridden).
ENV RAILS_ENV="production" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development test" \
    BUNDLE_IGNORE_CONFIGURED_GROUPS_WITHOUT=true \
    LD_PRELOAD="/usr/lib/libjemalloc.so.2" \
    MALLOC_ARENA_MAX="2"

# ────────────────────────────────────────
# Build stage
FROM base AS build

RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
      build-essential git libpq-dev libyaml-dev pkg-config nodejs zlib1g-dev && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*

COPY Gemfile Gemfile.lock ./
RUN bundle install && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git && \
    bundle exec bootsnap precompile --gemfile

COPY . .

RUN SECRET_KEY_BASE_DUMMY=1 ./bin/rails assets:precompile
RUN bundle exec bootsnap precompile app/ lib/

# #453: Bundle every (version × document_type) OSCAL schema from NIST
# GitHub into lib/oscal_schemas_bundle/ with a manifest.json carrying
# SHA-256 checksums. The seed task at deploy time prefers this bundle
# over a live NIST fetch, so production images validate against all 5
# supported OSCAL versions without runtime network dependency on
# raw.githubusercontent.com.
RUN SECRET_KEY_BASE_DUMMY=1 bin/rails oscal:bundle_schemas

# ────────────────────────────────────────
# Final stage — production image
FROM base

COPY --from=build "${BUNDLE_PATH}" "${BUNDLE_PATH}"
COPY --from=build /rails /rails

RUN groupadd --system --gid 1000 rails && \
    useradd rails --uid 1000 --gid 1000 --create-home --shell /bin/bash && \
    mkdir -p db log storage tmp && \
    chown -R rails:rails db log storage tmp

USER 1000:1000

ENTRYPOINT ["/rails/bin/docker-entrypoint"]

EXPOSE 3000
CMD ["./bin/rails", "server", "-b", "0.0.0.0", "-p", "3000"]
