# SPARC API test runner — issue #413 Phase 2.
#
# Build:
#   docker build -t sparc-api-tests tests/api
#
# Run against a SPARC instance on the host:
#   docker run --rm --network=host \
#     --env-file tests/api/.env \
#     sparc-api-tests pytest
#
# Run against a SPARC instance in the same compose network:
#   docker run --rm --network <compose-network> \
#     -e SPARC_TEST_BASE_URL=http://web:3000 \
#     -e SPARC_TEST_ADMIN_TOKEN=... \
#     -e SPARC_TEST_USER_TOKEN=... \
#     sparc-api-tests pytest
#
# The base image ships uv + Python 3.12 (~80 MB). The bake-in flow:
# 1. Copy the pyproject + lockfile only and `uv sync` so the dep layer
#    is cached even when test files change.
# 2. Copy the test sources on top.
# Lockfile drift fails the build (--frozen).

FROM ghcr.io/astral-sh/uv:python3.12-bookworm-slim

WORKDIR /app

# Optimize: only copy the dep manifest first so layer cache holds across
# test-file edits.
COPY pyproject.toml uv.lock ./

# --frozen rejects any drift between pyproject.toml and uv.lock — ensures
# CI-builds and local-builds resolve to the exact same versions.
RUN uv sync --frozen --extra dev

# Now bring in the test sources and the local package skeleton uv installs
# in editable mode.
COPY conftest.py ./
COPY README.md ./
COPY fixtures ./fixtures
COPY test_*.py ./

# Re-sync to register the local package (cheap; the dep layer is cached).
RUN uv sync --frozen --extra dev

# Drop privileges: run the test suite as a non-root user (docker:S6471).
# The base uv/bookworm-slim image otherwise defaults to root. /app (incl. the
# uv .venv) is chowned so the non-root user can run pytest and write caches.
RUN groupadd --system --gid 1000 tester \
    && useradd tester --uid 1000 --gid 1000 --create-home --shell /bin/bash \
    && chown -R tester:tester /app
USER 1000:1000

# Default to running the full suite. Override the entrypoint at run-time
# to scope to a marker or a single module (see header comments above).
ENV PATH="/app/.venv/bin:$PATH"
ENTRYPOINT ["uv", "run"]
CMD ["pytest"]
