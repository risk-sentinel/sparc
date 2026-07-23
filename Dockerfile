# syntax=docker/dockerfile:1
# ── SPARC production image — Red Hat UBI9 (Iron Bank / DISA-aligned) (#742, v1.12.0). ──
# Ruby + jemalloc compiled from source (UBI9 ships neither a ruby:3.4 image nor a
# jemalloc package); native gems build via microdnf. Retires the Debian perl/glibc
# CVE-disposition treadmill. Multi-arch (amd64 + arm64) in build-sign-publish.
# The prior Debian image is preserved as Dockerfile_debian for rollback; see
# docs/dev/ubi9_migration_findings.md for the migration validation + A/B evidence.
ARG RUBY_VERSION=3.4.4
ARG RUBY_MAJOR=3.4
ARG JEMALLOC_VERSION=5.3.0
ARG HDF_LIBS_VERSION=3.4.1
# Digest-pinned manifest-list (multi-arch) for reproducibility (#742 / folded #639
# pinning policy). Currently ubi-minimal 9.7. Digest-only (no version tag) so the
# reference is unambiguous (SonarQube docker:S6596 — don't pin tag AND digest).
# Bump deliberately via Dependabot/Renovate when RH ships a patch.
ARG UBI_IMAGE=registry.access.redhat.com/ubi9/ubi-minimal@sha256:907b68736aa798b2d38255b7aa070b2a70acb90803864a40f05d0ec47556ddd0

# ── builder: toolchain + Ruby/jemalloc from source + hdf-cli + gems + assets ──
FROM ${UBI_IMAGE} AS builder
ARG RUBY_VERSION
ARG RUBY_MAJOR
ARG JEMALLOC_VERSION
ARG HDF_LIBS_VERSION

# Required -devel for a Rails Ruby: openssl (TLS), zlib, libyaml (psych), libffi
# (fiddle) + libpq (pg). nodejs for assets:precompile. readline/gdbm/ncurses -devel
# are NOT in the UBI9 repos and are optional (Ruby 3.4 uses pure-Ruby reline).
RUN microdnf install -y --nodocs --setopt=install_weak_deps=0 \
      gcc gcc-c++ make git tar gzip bzip2 xz findutils \
      openssl-devel zlib-devel libyaml-devel libffi-devel \
      pkgconf-pkg-config postgresql-devel nodejs \
    && microdnf clean all

# jemalloc from source -> /usr/local/lib/libjemalloc.so.2 (LD_PRELOAD'd at runtime)
RUN curl -sSfL "https://github.com/jemalloc/jemalloc/releases/download/${JEMALLOC_VERSION}/jemalloc-${JEMALLOC_VERSION}.tar.bz2" -o /tmp/jemalloc.tar.bz2 \
    && mkdir -p /tmp/jemalloc && tar -xjf /tmp/jemalloc.tar.bz2 -C /tmp/jemalloc --strip-components=1 \
    && cd /tmp/jemalloc && ./configure --prefix=/usr/local && make -j"$(nproc)" && make install \
    && rm -rf /tmp/jemalloc*

# Ruby from source -> /usr/local
RUN curl -sSfL "https://cache.ruby-lang.org/pub/ruby/${RUBY_MAJOR}/ruby-${RUBY_VERSION}.tar.gz" -o /tmp/ruby.tar.gz \
    && mkdir -p /tmp/ruby && tar -xzf /tmp/ruby.tar.gz -C /tmp/ruby --strip-components=1 \
    && cd /tmp/ruby && ./configure --prefix=/usr/local --enable-shared --disable-install-doc \
    && make -j"$(nproc)" && make install && rm -rf /tmp/ruby*

# hdf-cli (Go static binary), SHA-256 verified — same script the Debian image uses.
COPY bin/install-hdf.sh /tmp/install-hdf.sh
RUN HDF_LIBS_VERSION="${HDF_LIBS_VERSION}" HDF_INSTALL_DIR=/usr/local/bin /tmp/install-hdf.sh

# LANG/LC_ALL (#750): UBI9 minimal ships no locale, so with LANG unset Ruby's
# Encoding.default_external falls back to US-ASCII — ERB then reads templates as
# ASCII-8BIT and any non-ASCII byte (e.g. the login layout's box-drawing chars)
# raises Encoding::CompatibilityError at render (500 on every full-layout page).
# glibc 2.34 provides the built-in C.UTF-8 locale (no glibc-langpack-* needed).
ENV PATH=/usr/local/bin:$PATH \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    BUNDLE_PATH=/usr/local/bundle \
    BUNDLE_DEPLOYMENT=1 \
    BUNDLE_WITHOUT="development test"

WORKDIR /rails
COPY Gemfile Gemfile.lock ./
RUN gem install bundler --no-document \
    && bundle install \
    && rm -rf ~/.bundle "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git \
    && bundle exec bootsnap precompile --gemfile

COPY . .
RUN SECRET_KEY_BASE_DUMMY=1 ./bin/rails assets:precompile
RUN bundle exec bootsnap precompile app/ lib/
# #453: bake all OSCAL schemas so validation has no runtime network dependency.
RUN SECRET_KEY_BASE_DUMMY=1 bin/rails oscal:bundle_schemas

# ── runtime: ubi-minimal + runtime libs + compiled ruby/jemalloc + app ──
FROM ${UBI_IMAGE} AS runtime
# Runtime shared libs the compiled Ruby + pg link against, plus the client tools
# the entrypoint needs: pg_isready (postgresql) and bash (docker-entrypoint).
RUN microdnf install -y --nodocs --setopt=install_weak_deps=0 \
      openssl-libs zlib libyaml libffi libpq tzdata shadow-utils bash postgresql ca-certificates \
    && microdnf clean all

# Custom/private-CA trust (#774), mechanism 1 — build-time bake-in. Drop PEM/CRT
# files into ./certs/ (empty by default; corporate proxy / DoD-PKI / internal
# CAs) and they are folded into the system trust store here, trusted by ALL
# outbound TLS clients (Ruby OpenSSL, RestClient, AWS SDK, and the #773 LDAP
# default store). Non-cert files (README, .gitkeep) are stripped before
# update-ca-trust. Mechanism 2 (runtime volume mount, no rebuild) lives in
# bin/lib/ca-trust.sh. Runs as root here — the runtime user (UID 1000) cannot.
COPY certs/ /etc/pki/ca-trust/source/anchors/sparc-custom/
RUN find /etc/pki/ca-trust/source/anchors/sparc-custom/ -type f \
      ! \( -name '*.crt' -o -name '*.pem' -o -name '*.cer' \) -delete 2>/dev/null || true; \
    update-ca-trust

# ── Database TLS trust (#785, NIST SC-8(1)) ──────────────────────────────────
# libpq does NOT honour SSL_CERT_FILE, so the runtime CA mechanism above (which
# covers every Ruby OpenSSL client) does not reach Postgres. Postgres verifies
# against `sslrootcert` and nothing else. We therefore bake the AWS RDS global
# CA bundle in at a fixed path so `SPARC_DB_SSLMODE=verify-full` works on RDS
# with no further operator action.
#
# Non-AWS / private-CA deployments do NOT need to rebuild: point
# SPARC_DB_SSLROOTCERT at a mounted PEM instead. Rebuilding (by adding to
# ./certs/) is only required to change the SYSTEM trust store.
ARG RDS_CA_BUNDLE_URL=https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem
RUN mkdir -p /etc/pki/sparc \
    && curl -sSfL --retry 3 "${RDS_CA_BUNDLE_URL}" -o /etc/pki/sparc/rds-global-bundle.pem \
    && openssl x509 -in /etc/pki/sparc/rds-global-bundle.pem -noout -subject >/dev/null \
    && chmod 0444 /etc/pki/sparc/rds-global-bundle.pem
# Fails the build loudly if the bundle is unreachable or not a valid certificate
# — a silently absent trust anchor would downgrade verify-full to a boot error
# in production, which is a far worse place to discover it.

COPY --from=builder /usr/local /usr/local
ENV PATH=/usr/local/bin:$PATH \
    RAILS_ENV=production \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    BUNDLE_DEPLOYMENT=1 \
    BUNDLE_PATH=/usr/local/bundle \
    BUNDLE_WITHOUT="development test" \
    BUNDLE_IGNORE_CONFIGURED_GROUPS_WITHOUT=true \
    LD_PRELOAD=/usr/local/lib/libjemalloc.so.2 \
    MALLOC_ARENA_MAX=2 \
    SPARC_DB_SSLROOTCERT=/etc/pki/sparc/rds-global-bundle.pem

# #750 guard: fail the build if the runtime ever loses its UTF-8 default encoding
# again (base-image locale regression). This exact assertion would have caught the
# v1.12.0 login 500 at build time instead of in production.
RUN ruby -e 'raise unless Encoding.default_external == Encoding::UTF_8' \
    || { echo "::error::default_external is not UTF-8 (is LANG set?) - see #750"; exit 1; }

WORKDIR /rails
COPY --from=builder /rails /rails

RUN groupadd --system --gid 1000 rails \
    && useradd rails --uid 1000 --gid 1000 --create-home --shell /bin/bash \
    && mkdir -p db log storage tmp \
    && chown -R rails:rails db log storage tmp

USER 1000:1000
ENTRYPOINT ["/rails/bin/docker-entrypoint"]
EXPOSE 3000
CMD ["./bin/rails", "server", "-b", "0.0.0.0", "-p", "3000"]
