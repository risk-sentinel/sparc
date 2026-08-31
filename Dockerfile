# syntax=docker/dockerfile:1
# ── SPARC production image — Red Hat UBI9 (Iron Bank / DISA-aligned) (#742, v1.12.0). ──
# Ruby + jemalloc compiled from source (UBI9 ships neither a ruby:3.4 image nor a
# jemalloc package); native gems build via microdnf. Retires the Debian perl/glibc
# CVE-disposition treadmill. Multi-arch (amd64 + arm64) in build-sign-publish.
# The prior Debian image is preserved as Dockerfile_debian for rollback; see
# docs/dev/ubi9_migration_findings.md for the migration validation + A/B evidence.
ARG RUBY_VERSION=3.4.10
ARG RUBY_MAJOR=3.4
ARG JEMALLOC_VERSION=5.3.0
ARG HDF_LIBS_VERSION=3.5.1
# Digest-pinned manifest-list (multi-arch: amd64, arm64, ppc64le, s390x) for
# reproducibility (#742 / folded #639 pinning policy). Currently ubi-minimal 9.8.
# Digest-only (no version tag) so the reference is unambiguous (SonarQube
# docker:S6596 — don't pin tag AND digest).
# Bump deliberately when RH ships a patch — a stale pin is how baked-in base
# packages quietly rot. Bumped 2026-08-04 (9.7 -> 9.8) to take the fixes for six
# HIGH CVEs the v1.15.4 scanner audit found with fixes available upstream:
#   gnutls  3.8.3-10.el9_7    -> 3.8.10-4.el9_8    CVE-2026-33845/-33846/-42009/-42010
#   libacl  2.3.1-4.el9       -> 2.4.0-1.el9_8     CVE-2026-54369
#   glib2   2.68.4-18.el9_7.2 -> 2.68.4-19.el9_8.2 CVE-2026-58016
# The base already carries them, so a digest bump is sufficient — no `microdnf
# update`, which would trade reproducibility for the same result.
#
# Bumped again 2026-08-20 (9.8 -> 9.8, newer build) for #1001. The 9.8 pin above
# was three months of errata behind, and the register's Debian->UBI9 re-base
# found the same CVEs still in the image under their RHEL package names.
# Measured with `rpm -q` on both digests rather than read off an advisory:
#   libgcrypt      1.10.0-11.el9    -> 1.10.0-13.el9_8    CVE-2026-41989
#   curl-minimal   7.76.1-40.el9    -> 7.76.1-40.el9_8.5  CVE-2026-1965/-3783
#   libcurl-minimal 7.76.1-40.el9   -> 7.76.1-40.el9_8.5  (same pair)
#   glib2          2.68.4-19.el9_8.2 -> 2.68.4-19.el9_8.9
#   libarchive     3.5.3-9.el9_7    -> 3.5.3-11.el9_8
# That is three of the four fixable findings in #1001; the fourth is the Go
# stdlib CVE in hdf-cli, which no base bump can reach — see the hdf-builder
# stage below.
#
# NOTE the header's "Iron Bank / DISA-aligned" is a description of the UBI9
# LINEAGE, not the source: this pulls Red Hat's PUBLIC registry, not
# registry1.dso.mil. Nothing here holds Iron Bank pull credentials.
#
# Bumped 2026-08-27 for two HIGH sqlite-libs CVEs the release gate caught. This
# is the first finding the #711 in-runner gate blocked on its own PR, which is
# what it was built for: nothing in that branch touched the image, and the
# container simply acquired two new HIGHs against CI-1's measured `high: 4`
# baseline (6 received, 4 allowed).
#   sqlite-libs  3.34.1-10.el9_8 -> 3.34.1-11.el9_8   CVE-2026-11822/-11824
# Measured with `rpm -q` on both digests, per the practice above. The bump is
# surgical: 109 packages before and after, nothing added or removed, and
# sqlite-libs is the ONLY version change — so the blast radius is the fix.
ARG UBI_IMAGE=registry.access.redhat.com/ubi9/ubi-minimal@sha256:580752f96d36c4132bffd30f9c34865bf4bd87f6aa161c969d117f21732e50f7

# ── hdf-builder: hdf-cli compiled from source, toolchain pinned (#1001) ──────
# This used to be a release-tarball download (script/dev/install-hdf.sh, then
# at bin/). Same tool,
# same org, two strategies — and only one of them can fix a Go stdlib CVE.
#
# Measured with `go version -m` on the binary that shipped in v1.16.0-rc:
# hdf 3.5.1 (the NEWEST published release, 2026-08-12) is built with go1.26.5,
# and the GO-2026-5026 fix line is go1.26.6. No version bump reaches it —
# choosing the toolchain does. risk-sentinel/container-build-sign reached the
# same conclusion for its ci-runner and sparc-auditor images (#234, #246);
# this stage is a port of the one in containers/ci-runner/Dockerfile, and the
# two should be kept in step.
#
# This is NOT a weaker supply chain than the tarball it replaces. The download
# verified a SHA-256 against the release checksums; this clones the signed
# v3.5.1 tag from the same canonical repo and then asserts, twice, on what the
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

# Security bump of a TRANSITIVE dependency, ahead of upstream. hdf-libs v3.5.1
# pins golang.org/x/text v0.27.0, which carries CVE-2026-56852 (HIGH):
# norm.Iter can enter an infinite loop on invalid UTF-8. Fixed in v0.39.0.
# Confirmed present in the shipped binary before this change. We build here
# precisely so the upgrade clock is ours; accepting a fixable HIGH when we
# control the compile would be declining to use the capability.
# REMOVE once hdf-libs ships x/text >= 0.39.0 — the assertion below reports
# that the bump was undone, never that it became redundant.
ARG XTEXT_VERSION=0.39.0
# `go mod edit` + `go mod download`, not `go get`: edit sets the requirement
# mechanically with no version resolution and download records the hash in
# go.sum. `go get` resolves a module graph at build time — less predictable,
# and what SonarQube flags as a non-lock-file command.
RUN go mod edit -require="golang.org/x/text@v${XTEXT_VERSION}" \
    && go mod download golang.org/x/text

# hadolint ignore=DL3003
RUN COMMIT="$(git -C /src rev-parse --short HEAD)" \
    && DATE="$(git -C /src show -s --format=%cI HEAD)" \
    && PKG="github.com/mitre/hdf-libs/hdf-cli/v3/cmd/hdf/cmd" \
    && CGO_ENABLED=0 GOOS="${TARGETOS:-linux}" GOARCH="${TARGETARCH}" go build -trimpath \
         -ldflags "-s -w -X ${PKG}.version=${HDF_LIBS_VERSION} -X ${PKG}.commit=${COMMIT} -X ${PKG}.date=${DATE}" \
         -o /out/hdf ./cmd/hdf

# The x/text bump is silent if it stops applying — a later hdf-libs could pin a
# newer x/text, or the requirement could stop resolving, and the build would
# still succeed carrying a vulnerable copy. Read it back out of the ACTUAL
# binary rather than trusting the instruction above.
RUN go version -m /out/hdf | grep -E "golang.org/x/text[[:space:]]+v${XTEXT_VERSION}" \
      || { echo "FAIL: /out/hdf does not carry x/text v${XTEXT_VERSION} (CVE-2026-56852)" >&2; \
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

# ── Drop curl and the package manager from the runtime image (#1001) ─────────
# MEASURED, not assumed. Every ELF in the runtime image that links libcurl:
# /usr/bin/curl, /usr/bin/microdnf, /usr/lib64/libdnf.so.2, /usr/lib64/librepo.so.0.
# Nothing of ours. The application never shells out to curl and never links it:
# every outbound fetch — the DISA CCI refresh, the AWS Labs CDEF ingest, source
# federation, Security Hub — goes through Ruby's Net::HTTP / open-uri on Ruby's
# OpenSSL bindings, `ldd` on the compiled ruby reports zero libcurl references,
# and hdf-cli is a static Go binary. No gem in Gemfile.lock links it either
# (no curb / typhoeus / ethon / patron).
#
# That left curl-minimal and libcurl-minimal carrying ~16 findings, two of them
# HIGH, for code nothing in the image calls. They cannot be removed with
# microdnf: rpm declares a dependency on the curl BINARY and librepo on
# libcurl, so a depsolve refuses. `rpm -e --nodeps` removes them along with the
# package manager that needs them, which is the right posture for an immutable
# runtime anyway — a container that cannot install packages cannot have
# packages installed into it.
#
# RPM ITSELF IS DELIBERATELY KEPT. Grype and Trivy enumerate OS packages by
# reading the rpm database; removing rpm would make the image scan clean by
# making it unreadable, which is the same lie #1001 was filed about. 107
# packages remain enumerable after this, down from 112.
#
# Verified in the built image before this was written: rpm -qa still lists,
# `require "pg"` loads, `rails zeitwerk:check` eager loads clean, hdf runs, and
# update-ca-trust and pg_isready — the two runtime tools that matter — survive,
# since both come from ca-certificates/p11-kit and postgresql, not from curl.
# The runtime CA mechanism in bin/lib/ca-trust.sh uses neither curl nor dnf.
RUN rpm -e --nodeps curl-minimal libcurl-minimal microdnf libdnf librepo \
    && rm -rf /var/cache/dnf /var/cache/yum \
    && ! command -v curl \
    && ! ls /usr/lib64/libcurl.so.4 2>/dev/null \
    && rpm -qa | wc -l

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
# setup below to keep this a single layer (sonar docker:S7031).
RUN ruby /rails/bin/prune-shadowed-gems.rb \
    && bundle check \
    && bundle exec ruby -e 'require "net/imap"; require "rails"' \
    && groupadd --system --gid 1000 rails \
    && useradd rails --uid 1000 --gid 1000 --create-home --shell /bin/bash \
    && mkdir -p db log storage tmp \
    && chown -R rails:rails db log storage tmp

USER 1000:1000
ENTRYPOINT ["/rails/bin/docker-entrypoint"]
EXPOSE 3000
CMD ["./bin/rails", "server", "-b", "0.0.0.0", "-p", "3000"]
