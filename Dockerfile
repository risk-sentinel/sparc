# syntax=docker/dockerfile:1
# ── SPARC production image — Red Hat UBI 10 minimal, hardened (#1200; UBI9 since #742, v1.12.0). ──
# Ruby + jemalloc compiled from source (UBI ships neither a ruby:3.4 image nor a
# jemalloc package); native gems build via microdnf. Retires the Debian perl/glibc
# CVE-disposition treadmill. Multi-arch (amd64 + arm64) in build-sign-publish.
# The prior Debian image is preserved as Dockerfile_debian for rollback; see
# docs/dev/ubi9_migration_findings.md for the migration validation + A/B evidence.
ARG RUBY_VERSION=3.4.10
ARG RUBY_MAJOR=3.4
ARG JEMALLOC_VERSION=5.3.0
ARG HDF_LIBS_VERSION=3.7.0
# Digest-pinned manifest-list (multi-arch: amd64, arm64, ppc64le, s390x) for
# reproducibility (#742 / folded #639 pinning policy). Currently ubi-minimal 10.2.
# Digest-only (no version tag) so the reference is unambiguous (SonarQube
# docker:S6596 — don't pin tag AND digest). Bump deliberately when Red Hat ships
# a patch — a stale pin is how baked-in base packages quietly rot — and measure
# the bump with the scanners and the rpm database, not an advisory.
#
# WHY UBI 10 (#1189 spike, #1200). Measured 2026-09-29 with grype 0.114.0 (DB
# v6.1.9) on the FINISHED image, not the bare base, against the 33 register
# entries the UBI9 image carried:
#
#                                  retired  left, no fix  HIGH left  new HIGH
#   UBI9, current digest + fresh     18         15            4          0
#   UBI9 + strip below               23         10            3          0
#   UBI10, no strip                  26          7            9          6
#   UBI10 + strip below              28          5            2          0
#
# The strip is half the win: el10's util-linux 2.40 and rpm-sequoia carry six
# HIGHs of their own, and nothing at runtime loads either. UBI10 also moves the
# Postgres client tools off 13 (end of life) to 16. The full #1189 result is on
# the issue; the UBI9 bump history (gnutls, libacl, glib2, openssl, libevent,
# libgcrypt, curl, libarchive, sqlite) is in `git log -- Dockerfile`.
#
# NOTE "DISA-aligned" describes the UBI LINEAGE, not the source: this pulls Red
# Hat's PUBLIC registry, not registry1.dso.mil. Nothing here holds Iron Bank
# pull credentials.
ARG UBI_IMAGE=registry.access.redhat.com/ubi10/ubi-minimal@sha256:a9f9316ec3a1419a2de6ce4d2d9f034d477e97cdf2a16d6f04b7bd632ac753c4

# ── hdf-builder: hdf-cli compiled from source, toolchain pinned (#1001) ──────
# This used to be a release-tarball download (script/dev/install-hdf.sh, then
# at bin/). Same tool,
# same org, two strategies — and only one of them can fix a Go stdlib CVE.
#
# Measured with `go version -m` on the binary that shipped in v1.16.0-rc:
# hdf 3.5.1 (then the newest release) is built with go1.26.5, and the
# GO-2026-5026 fix line is go1.26.6. No version bump reaches it — choosing the
# toolchain does. risk-sentinel/container-build-sign reached the same
# conclusion for its ci-runner and sparc-auditor images (#234, #246); this
# stage is a port of the one in containers/ci-runner/Dockerfile, and the two
# should be kept in step.
#
# 3.7.0's PUBLISHED binary is built with go1.26.6, so that specific gap is
# closed upstream. This stage still compiles from source, because the reason to
# keep it is not only the toolchain: it asserts on what the emitted binary
# ACTUALLY contains, which no download does, and it keeps the upgrade clock
# ours rather than upstream's.
#
# This is NOT a weaker supply chain than the tarball it replaces. The download
# verified a SHA-256 against the release checksums; this clones the signed
# version tag from the same canonical repo and then asserts, twice, on what the
# emitted binary actually contains — which the tarball path never did.
#
# The download script is KEPT, demoted to script/dev/install-hdf.sh, as a
# local developer convenience only. CI's security_gate builds from source
# the same way this stage does, so no surface that gates or ships a
# release depends on the published binary any more.
#
# Pin the patch (golang:1.26.6), not the minor (golang:1.26) — a floating minor
# does not deterministically clear a stdlib CVE, which is the entire point.
FROM --platform=$BUILDPLATFORM golang:1.26.6-bookworm AS hdf-builder
ARG HDF_LIBS_VERSION
ARG TARGETOS
ARG TARGETARCH

RUN git clone --depth 1 --branch "v${HDF_LIBS_VERSION}" \
        https://github.com/mitre/hdf-libs.git /src
WORKDIR /src/hdf-cli

# golang.org/x/text MINIMUM, not a forced version. hdf-libs v3.5.1 pinned
# x/text v0.27.0, carrying CVE-2026-56852 (HIGH) — norm.Iter can loop forever
# on invalid UTF-8 — so this stage used to force v0.39.0 with `go mod edit`
# ahead of upstream.
#
# v3.7.0 ships v0.39.0 itself, which is the condition the old comment named for
# removing the bump. Forcing it now would be worse than redundant: `go mod edit
# -require` pins EXACTLY, so the day upstream moves to v0.40.x this would pull
# it back DOWN, and an equality assertion would report success while doing it.
#
# So the requirement is gone and the floor stays, asserted against the emitted
# binary below.
ARG XTEXT_VERSION=0.39.0

# hadolint ignore=DL3003
RUN COMMIT="$(git -C /src rev-parse --short HEAD)" \
    && DATE="$(git -C /src show -s --format=%cI HEAD)" \
    && PKG="github.com/mitre/hdf-libs/hdf-cli/v3/cmd/hdf/cmd" \
    && CGO_ENABLED=0 GOOS="${TARGETOS:-linux}" GOARCH="${TARGETARCH}" go build -trimpath \
         -ldflags "-s -w -X ${PKG}.version=${HDF_LIBS_VERSION} -X ${PKG}.commit=${COMMIT} -X ${PKG}.date=${DATE}" \
         -o /out/hdf ./cmd/hdf

# Read the floor back out of the ACTUAL binary. A `>=` comparison, not `==`:
# equality would fail the build the day upstream ships a NEWER x/text, which is
# the outcome we want, not a regression. `sort -V` does the version compare, so
# 0.100.0 sorts above 0.39.0 rather than below it as a string would.
RUN ACTUAL="$(go version -m /out/hdf | awk '$2 == "golang.org/x/text" { print $3 }' | sed 's/^v//')" \
    && [ -n "${ACTUAL}" ] \
    && [ "$(printf '%s\n%s\n' "${XTEXT_VERSION}" "${ACTUAL}" | sort -V | head -1)" = "${XTEXT_VERSION}" ] \
      || { echo "FAIL: /out/hdf carries x/text v${ACTUAL:-<none>}, below the v${XTEXT_VERSION} floor (CVE-2026-56852)" >&2; \
           go version -m /out/hdf | grep "golang.org/x/text" >&2; exit 1; }
# And assert the toolchain, which is the finding this stage exists to close.
# `go build` silently uses whatever toolchain the image carries; if the FROM
# above is ever downgraded, GO-2026-5026 comes back with no other signal.
# A real version comparison, not a pattern match: `sort -V -C` succeeds only
# when the floor sorts at or before what the binary reports, so a newer Go
# (1.27.0, 1.30.x) passes while anything below the fix line fails.
ARG GO_FIX_LINE=1.26.6
RUN actual="$(go version -m /out/hdf | head -1 | awk '{ print $2 }' | sed 's/^go//')" \
    && printf '%s\n%s\n' "${GO_FIX_LINE}" "${actual}" | sort -V -C \
      || { echo "FAIL: /out/hdf built with go${actual}, older than the GO-2026-5026 fix line go${GO_FIX_LINE}" >&2; \
           exit 1; }

# ── builder: toolchain + Ruby/jemalloc from source + hdf-cli + gems + assets ──
FROM ${UBI_IMAGE} AS builder
ARG RUBY_VERSION
ARG RUBY_MAJOR
ARG JEMALLOC_VERSION
ARG HDF_LIBS_VERSION

# Required -devel for a Rails Ruby: openssl (TLS), zlib, libyaml (psych), libffi
# (fiddle) + libpq (pg). nodejs for assets:precompile. readline/gdbm -devel are
# NOT in the UBI repos (measured on 9 and 10; ncurses-devel is on 10) and all
# three are optional (Ruby 3.4 uses pure-Ruby reline).
RUN microdnf install -y --nodocs --setopt=install_weak_deps=0 \
      gcc gcc-c++ make git tar gzip bzip2 xz findutils \
      openssl-devel zlib-devel libyaml-devel libffi-devel \
      pkgconf-pkg-config postgresql-devel nodejs \
    && microdnf clean all

# jemalloc from source -> /usr/local/lib/libjemalloc.so.2 (LD_PRELOAD'd at runtime)
RUN curl -sSfL --proto '=https' --tlsv1.2 "https://github.com/jemalloc/jemalloc/releases/download/${JEMALLOC_VERSION}/jemalloc-${JEMALLOC_VERSION}.tar.bz2" -o /tmp/jemalloc.tar.bz2 \
    && mkdir -p /tmp/jemalloc && tar -xjf /tmp/jemalloc.tar.bz2 -C /tmp/jemalloc --strip-components=1 \
    && cd /tmp/jemalloc && ./configure --prefix=/usr/local && make -j"$(nproc)" && make install \
    && rm -rf /tmp/jemalloc*

# Ruby from source -> /usr/local
RUN curl -sSfL --proto '=https' --tlsv1.2 "https://cache.ruby-lang.org/pub/ruby/${RUBY_MAJOR}/ruby-${RUBY_VERSION}.tar.gz" -o /tmp/ruby.tar.gz \
    && mkdir -p /tmp/ruby && tar -xzf /tmp/ruby.tar.gz -C /tmp/ruby --strip-components=1 \
    && cd /tmp/ruby && ./configure --prefix=/usr/local --enable-shared --disable-install-doc \
    && make -j"$(nproc)" && make install && rm -rf /tmp/ruby*

# AWS RDS global CA bundle (#785, NIST SC-8(1)) — fetched HERE in the builder,
# not in the runtime stage, because runtime deliberately carries no curl and
# only `openssl-libs` (shared libraries, no CLI). Adding either to runtime just
# to download a file would enlarge the production image and its CVE surface.
#
# ADD (not RUN curl) is the native fetch instruction and needs no shell tool
# (sonar docker:S7026). The URL is a literal https:// source, not an ARG, so the
# scheme is fixed at build time — there is no dynamic value that could resolve to
# plaintext (sonar docker:S6506). To build against a mirror, edit this line.
ADD https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem /tmp/rds-global-bundle.pem
# Validated in a separate step — a silently absent, empty, or non-PEM bundle
# would otherwise surface as a production boot error, a far worse place to find
# it. Content check (not the openssl CLI) because the runtime image has neither.
RUN grep -q "BEGIN CERTIFICATE" /tmp/rds-global-bundle.pem \
    && test "$(grep -c 'BEGIN CERTIFICATE' /tmp/rds-global-bundle.pem)" -gt 50

# hdf-cli, compiled from source with a pinned Go toolchain (#1001). Lands in
# /usr/local/bin so it rides the existing `COPY --from=builder /usr/local` into
# the runtime stage, exactly as the downloaded binary did.
COPY --from=hdf-builder /out/hdf /usr/local/bin/hdf
# A bare `hdf version` asserts nothing: built from source, a binary with drifted
# ldflags reports `development` and still exits 0. Match the pinned version so a
# wrong build fails here instead of shipping. This stage runs on the TARGET
# platform, so the binary is executable here even though it was cross-compiled.
# DL4006: grep's exit status is the gate; pipefail not needed.
# hadolint ignore=DL4006
RUN out="$(hdf version 2>&1)"; \
    echo "$out"; \
    echo "$out" | grep -q "${HDF_LIBS_VERSION}" \
      || { echo "FAIL: hdf CLI missing or not version ${HDF_LIBS_VERSION}" >&2; exit 1; }

# LANG/LC_ALL (#750): UBI minimal ships no locale, so with LANG unset Ruby's
# Encoding.default_external falls back to US-ASCII — ERB then reads templates as
# ASCII-8BIT and any non-ASCII byte (e.g. the login layout's box-drawing chars)
# raises Encoding::CompatibilityError at render (500 on every full-layout page).
# glibc provides the built-in C.UTF-8 locale (2.34 on UBI9, 2.39 on UBI10;
# re-measured on 10: unset LANG still yields US-ASCII) — no glibc-langpack-* needed.
ENV PATH=/usr/local/bin:$PATH \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    BUNDLE_PATH=/usr/local/bundle \
    BUNDLE_DEPLOYMENT=1 \
    BUNDLE_WITHOUT="development test"

WORKDIR /rails
COPY Gemfile Gemfile.lock ./
# #966 (docker:S8547) — `BUNDLE_DEPLOYMENT=1` above already implies frozen, so
# this changes no behaviour. It states the guarantee AT THE CALL SITE instead of
# depending on an env var set several lines earlier: lock drift fails the build
# loudly rather than quietly resolving something new and shipping it.
# Verified safe before adding: `BUNDLE_FROZEN=true bundle check` exits 0 against
# the committed lock, and Gemfile.lock is clean in git.
RUN gem install bundler --no-document \
    && bundle config set --local frozen true \
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
# ── Build freshness (#1200) ──────────────────────────────────────────────────
# The install below resolves CURRENT packages from Red Hat's repos, but Docker
# reuses its layer until something above it changes. The #1189 spike found the
# shipping UBI9 image carrying postgresql 13.23-5 while the repo held -6, fixing
# 15 CVEs: the layer had been cached before the erratum. Copying the file that
# holds SparcConfig::VERSION in first makes every version bump re-resolve the
# install, so a release can never ship a package layer older than its release.
# A blanket `microdnf update` would instead float every BASE package and defeat
# the digest pin; base packages move only with a deliberate digest bump.
COPY app/models/sparc_config.rb /tmp/sparc-version-key.rb
# Runtime shared libs the compiled Ruby + pg link against, plus the client tools
# the entrypoint needs: pg_isready (postgresql) and bash (docker-entrypoint).
# `update --assumeno` changes nothing: it prints the BASE packages that have a
# newer build in the repo, so a stale digest is visible in every build log.
RUN rm /tmp/sparc-version-key.rb \
    && microdnf install -y --nodocs --setopt=install_weak_deps=0 \
      openssl-libs zlib libyaml libffi libpq tzdata shadow-utils bash postgresql ca-certificates \
    && { microdnf update --assumeno --nodocs 2>&1 | sed -n '/Upgrading/,$p' || true; } \
    && microdnf clean all \
    && rpm -q openssl-libs libpq postgresql libevent

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
# Copied from the builder, which fetched and validated it — runtime carries no
# curl and no openssl CLI, and should not gain either just to download a file.
#
# Non-AWS / private-CA deployments do NOT need to rebuild: point
# SPARC_DB_SSLROOTCERT at a mounted PEM instead. Rebuilding (by adding to
# ./certs/) is only required to change the SYSTEM trust store.
COPY --from=builder /tmp/rds-global-bundle.pem /etc/pki/sparc/rds-global-bundle.pem
RUN chmod 0444 /etc/pki/sparc/rds-global-bundle.pem

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

# ── Image hardening (#862): drop Ruby-shipped gems the bundle already shadows ─
# Ruby's bundled-gem trees stay on disk after Bundler resolves a newer version
# from /usr/local/bundle, so scanners keep reporting their CVEs against code
# that is never loaded — net-imap 0.5.8 alone carried three CRITICALs on that
# basis. Deleting the shadowed copy retires the finding instead of
# re-justifying it every review cycle. DEFAULT gems (erb, zlib, ...) are
# deliberately left alone: their code is the stdlib itself, so removing only
# the gemspec would falsify the scan rather than harden the image. See the
# script header and docs/compliance/sparc-findings.yml.
#
# `bundle check` + a real `bundle exec require` gate the build: a prune that
# strands the bundle fails here rather than at runtime. Merged with the user
# setup and the runtime strip below into a single layer (sonar docker:S7031).
# ── Runtime strip: remove what nothing at runtime loads (#1001, #1200; CM-7) ──
# MEASURED, not assumed, on the finished image (`rpm --whatrequires` + `ldd` over
# ruby, every gem extension, pg_isready, bash and hdf):
#   * curl + libcurl-minimal — nothing of ours calls or links them. Every
#     outbound fetch goes through Ruby's Net::HTTP on Ruby's OpenSSL; hdf is a
#     static Go binary; no gem links libcurl (no curb/typhoeus/ethon/patron).
#   * the package manager and what only it uses — microdnf, libdnf, librepo,
#     libsolv, libmodulemd, librhsm, dnf-data, glib2, gobject-introspection,
#     json-glib, libpeas1, and rpm itself (rpm, rpm-libs, rpm-sequoia,
#     lua-libs). An immutable runtime needs none of it: a container that cannot
#     install packages cannot have packages installed into it.
#   * util-linux's libblkid/libmount/libsmartcols/libuuid — their only consumer
#     is glib2.
# #1204 — and pg must link the SYSTEM libpq (Red Hat's, with Red Hat's
# openssl-libs), never the precompiled gem's bundled libpq-ruby-pg, which
# carried its own out-of-date OpenSSL that no scanner could see. The Gemfile
# forces pg's ruby platform; these two checks fail the build if it ever slips.
#
# `rpm -e --nodeps` because a depsolve refuses (rpm needs the curl binary,
# librepo needs libcurl); the removal is ONE transaction, so rpm removing itself
# is its last act. pcre2 STAYS: libselinux and grep load it.
#
# REMOVING RPM DOES NOT BLIND THE SCANNERS — proven for #1200, reversing the
# #1001 assumption that it would. Grype and Trivy read the rpm DATABASE file,
# not the rpm program, and `rpm -e` leaves the database with every remaining
# package recorded. Measured on the stripped image: 85 packages in
# rpmdb.sqlite, 85 enumerated by grype, 85 by Trivy 0.74, none missing. The
# assertions below keep that true (FILE tests, not `command -v`, which answers
# from the shell's hash of a program it just ran — `rpm` after `rpm -e`): the
# build fails if the database goes missing
# or empty, if any stripped package's files survive, or if anything the runtime
# executes has an unresolved shared library. To query packages in the shipped
# image, read its database from any rpm-bearing container:
#   docker cp <ctr>:/usr/lib/sysimage/rpm/rpmdb.sqlite . && rpm --dbpath . -qa
RUN ruby /rails/bin/prune-shadowed-gems.rb \
    && bundle check \
    && bundle exec ruby -e 'require "net/imap"; require "rails"' \
    && groupadd --system --gid 1000 rails \
    && useradd rails --uid 1000 --gid 1000 --create-home --shell /bin/bash \
    && mkdir -p db log storage tmp \
    && chown -R rails:rails db log storage tmp \
    && rpm -e --nodeps \
      curl libcurl-minimal microdnf libdnf librepo libsolv libmodulemd librhsm dnf-data \
      glib2 gobject-introspection json-glib libpeas1 \
      libblkid libmount libsmartcols libuuid \
      rpm rpm-libs rpm-sequoia lua-libs \
    && rm -rf /var/cache/dnf /var/cache/yum /var/lib/dnf \
    && { test -s /usr/lib/sysimage/rpm/rpmdb.sqlite \
         || { echo "::error::the rpm database is gone — scanners could not inventory this image"; \
              exit 1; }; } \
    && for f in /usr/bin/curl /usr/bin/microdnf /usr/bin/rpm \
                /usr/lib64/libcurl.so.4 /usr/lib64/libglib-2.0.so.0 \
                /usr/lib64/libmount.so.1 /usr/lib64/libblkid.so.1 \
                /usr/lib64/librpm.so.10 /usr/lib64/librpm_sequoia.so.1; do \
         [ ! -e "$f" ] || { echo "::error::$f survived the strip"; exit 1; }; \
       done \
    && unresolved=$( { ldd /usr/local/bin/ruby /usr/local/bin/hdf /usr/bin/pg_isready \
                           /usr/bin/bash /usr/bin/grep 2>&1; \
                       find /usr/local/bundle /usr/local/lib/ruby -name '*.so' \
                            -exec ldd {} \; 2>&1; } | grep 'not found' || true ) \
    && { [ -z "$unresolved" ] \
         || { echo "::error::unresolved libraries after the strip:"; echo "$unresolved"; exit 1; }; } \
    && pgext=$(find /usr/local/bundle -name pg_ext.so | head -1) \
    && { ldd "$pgext" | grep -q ' => /usr/lib64/libpq.so.5 ' \
         || { echo "::error::pg does not link the system libpq (#1204):"; ldd "$pgext"; exit 1; }; } \
    && bundled=$(find / -xdev -name 'libpq-ruby-pg*' 2>/dev/null) \
    && { [ -z "$bundled" ] \
         || { echo "::error::a bundled libpq shipped (#1204): $bundled"; exit 1; }; } \
    && ruby -e 'require "openssl"; require "socket"' \
    && ls -l /usr/lib/sysimage/rpm/rpmdb.sqlite

USER 1000:1000
ENTRYPOINT ["/rails/bin/docker-entrypoint"]
EXPOSE 3000
CMD ["./bin/rails", "server", "-b", "0.0.0.0", "-p", "3000"]
