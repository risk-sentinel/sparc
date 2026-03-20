#!/usr/bin/env bash
# ============================================================================
# trivy-scan.sh — Local container security scanning for SPARC
#
# Runs Trivy against the SPARC Docker image with the same configuration as CI,
# then converts results to HDF format for MITRE SAF / Heimdall viewing.
#
# Usage:
#   ./scripts/trivy-scan.sh              # Table + HDF output
#   ./scripts/trivy-scan.sh --sarif      # Also generate SARIF
#   ./scripts/trivy-scan.sh --skip-build # Scan existing image (no rebuild)
#   ./scripts/trivy-scan.sh --fs-only    # Filesystem scan only (no Docker)
#
# Prerequisites:
#   - Docker (for container scanning)
#   - Trivy (auto-installed if missing via direct binary download)
#   - SAF CLI (optional, for HDF conversion: npm install -g @mitre/saf)
#
# Output files are written to docs/hdf/ (gitignored).
# ============================================================================
set -euo pipefail

# ── Ensure common local install paths are on PATH ─────────────────────────
export PATH="$HOME/.local/bin:/usr/local/bin:$PATH"

# ── Configuration (mirrors CI workflow) ────────────────────────────────────
IMAGE_NAME="sparc"
IMAGE_TAG="local-scan"
SEVERITY="CRITICAL,HIGH,MEDIUM"
SCANNERS="vuln"
OUTPUT_DIR="docs/hdf"
DOCKERFILE_PATH="./Dockerfile"

# ── Parse arguments ────────────────────────────────────────────────────────
GENERATE_SARIF=false
SKIP_BUILD=false
FS_ONLY=false

for arg in "$@"; do
  case "$arg" in
    --sarif)      GENERATE_SARIF=true ;;
    --skip-build) SKIP_BUILD=true ;;
    --fs-only)    FS_ONLY=true ;;
    --help|-h)
      echo "Usage: $0 [--sarif] [--skip-build] [--fs-only]"
      echo ""
      echo "  --sarif       Also generate SARIF output for GitHub Code Scanning"
      echo "  --skip-build  Scan existing image without rebuilding"
      echo "  --fs-only     Run filesystem scan only (no Docker build required)"
      echo ""
      exit 0
      ;;
    *)
      echo "Unknown argument: $arg"
      echo "Run $0 --help for usage"
      exit 1
      ;;
  esac
done

# ── Color helpers ──────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

info()  { echo -e "${BLUE}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
fail()  { echo -e "${RED}[FAIL]${NC}  $*"; }

# ── Ensure Trivy is installed ──────────────────────────────────────────────
ensure_trivy() {
  if command -v trivy &>/dev/null; then
    ok "Trivy found: $(trivy --version 2>&1 | head -1)"
    return
  fi

  info "Trivy not found. Installing via direct binary download..."
  info "(No brew/apt required — downloads from GitHub releases)"

  mkdir -p "$HOME/.local/bin"
  if ! curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sh -s -- -b "$HOME/.local/bin"; then
    fail "Trivy installation failed."
    echo ""
    echo "Manual install options:"
    echo "  mkdir -p ~/.local/bin"
    echo "  curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sh -s -- -b ~/.local/bin"
    echo "  # or download from: https://github.com/aquasecurity/trivy/releases"
    exit 1
  fi

  ok "Trivy installed: $(trivy --version 2>&1 | head -1)"
}

# ── Check SAF CLI availability ─────────────────────────────────────────────
check_saf() {
  if command -v saf &>/dev/null; then
    ok "SAF CLI found: $(saf --version 2>&1 | head -1)"
    return 0
  fi

  warn "SAF CLI not found. HDF conversion will be skipped."
  echo "  Install with: npm install -g @mitre/saf"
  echo "  HDF format is required for MITRE SAF Heimdall viewer."
  echo ""
  return 1
}

# ── Create output directory ────────────────────────────────────────────────
mkdir -p "$OUTPUT_DIR"

# ── Main ───────────────────────────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  SPARC Container Security Scan (Local)                      ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

ensure_trivy
HAS_SAF=false
check_saf && HAS_SAF=true

# ── Filesystem scan ────────────────────────────────────────────────────────
info "Running Trivy filesystem scan..."
trivy fs \
  --severity "$SEVERITY" \
  --scanners "$SCANNERS" \
  --ignorefile .trivyignore \
  --format table \
  . 2>&1 || true

# Generate FS CycloneDX for HDF conversion
trivy fs \
  --severity "$SEVERITY" \
  --scanners "$SCANNERS" \
  --ignorefile .trivyignore \
  --format cyclonedx \
  --output "$OUTPUT_DIR/trivy-fs-local.cdx.json" \
  . 2>/dev/null || true

if [[ "$HAS_SAF" == "true" ]] && [[ -f "$OUTPUT_DIR/trivy-fs-local.cdx.json" ]]; then
  info "Converting filesystem scan to HDF..."
  saf convert cyclonedx_sbom2hdf \
    -i "$OUTPUT_DIR/trivy-fs-local.cdx.json" \
    -o "$OUTPUT_DIR/trivy-fs-local.hdf.json" 2>/dev/null || warn "FS HDF conversion failed"
  [[ -f "$OUTPUT_DIR/trivy-fs-local.hdf.json" ]] && ok "FS HDF: $OUTPUT_DIR/trivy-fs-local.hdf.json"
fi

if [[ "$FS_ONLY" == "true" ]]; then
  echo ""
  ok "Filesystem scan complete. Skipping container scan (--fs-only)."
  exit 0
fi

# ── Build Docker image ─────────────────────────────────────────────────────
if [[ "$SKIP_BUILD" == "false" ]]; then
  info "Building Docker image: ${IMAGE_NAME}:${IMAGE_TAG}..."
  if ! docker build -t "${IMAGE_NAME}:${IMAGE_TAG}" -f "$DOCKERFILE_PATH" .; then
    fail "Docker build failed. Fix build errors before scanning."
    exit 1
  fi
  ok "Docker image built: ${IMAGE_NAME}:${IMAGE_TAG}"
else
  info "Skipping Docker build (--skip-build)"
  if ! docker image inspect "${IMAGE_NAME}:${IMAGE_TAG}" &>/dev/null; then
    fail "Image ${IMAGE_NAME}:${IMAGE_TAG} not found. Run without --skip-build first."
    exit 1
  fi
fi

# ── Container scan (table output to console) ───────────────────────────────
echo ""
info "Running Trivy container scan (severity: ${SEVERITY})..."
trivy image \
  --severity "$SEVERITY" \
  --scanners "$SCANNERS" \
  --ignorefile .trivyignore \
  --format table \
  "${IMAGE_NAME}:${IMAGE_TAG}" 2>&1 || true

# ── Container scan (CycloneDX for HDF conversion) ─────────────────────────
info "Generating CycloneDX SBOM..."
trivy image \
  --severity "$SEVERITY" \
  --scanners "$SCANNERS" \
  --ignorefile .trivyignore \
  --format cyclonedx \
  --output "$OUTPUT_DIR/trivy-container-local.cdx.json" \
  "${IMAGE_NAME}:${IMAGE_TAG}" 2>/dev/null || warn "CycloneDX generation failed"

# ── Convert to HDF via SAF CLI ─────────────────────────────────────────────
if [[ "$HAS_SAF" == "true" ]] && [[ -f "$OUTPUT_DIR/trivy-container-local.cdx.json" ]]; then
  info "Converting container scan to HDF format..."
  saf convert cyclonedx_sbom2hdf \
    -i "$OUTPUT_DIR/trivy-container-local.cdx.json" \
    -o "$OUTPUT_DIR/trivy-container-local.hdf.json" 2>/dev/null || warn "Container HDF conversion failed"
  [[ -f "$OUTPUT_DIR/trivy-container-local.hdf.json" ]] && ok "Container HDF: $OUTPUT_DIR/trivy-container-local.hdf.json"
fi

# ── Optional SARIF output ──────────────────────────────────────────────────
if [[ "$GENERATE_SARIF" == "true" ]]; then
  info "Generating SARIF output..."
  trivy image \
    --severity "$SEVERITY" \
    --scanners "$SCANNERS" \
    --ignorefile .trivyignore \
    --format sarif \
    --output "$OUTPUT_DIR/trivy-container-local.sarif" \
    "${IMAGE_NAME}:${IMAGE_TAG}" 2>/dev/null || warn "SARIF generation failed"
  [[ -f "$OUTPUT_DIR/trivy-container-local.sarif" ]] && ok "SARIF: $OUTPUT_DIR/trivy-container-local.sarif"
fi

# ── Summary ────────────────────────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  Scan Complete                                              ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
info "Output files in $OUTPUT_DIR/:"
ls -la "$OUTPUT_DIR"/trivy-*-local.* 2>/dev/null || warn "No output files generated"
echo ""
if [[ "$HAS_SAF" == "true" ]]; then
  info "View HDF results in Heimdall: https://heimdall-lite.mitre.org"
  info "  Upload: $OUTPUT_DIR/trivy-container-local.hdf.json"
fi
echo ""
