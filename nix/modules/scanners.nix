# The scanners security.yml runs that need no credentials, as the `scanners` set. Versions come from nixpkgs and
# are newer than CI's pins (trivy 0.69.3, grype 0.115.0, syft 1.50.0, gitleaks 8.24.0), so a local result is a
# preview of the gate, not the gate.
_:
let
  scan = import ./_entry.nix "scan";
in
{
  perSystem =
    { pkgs, ... }:
    {
      sparc.sets.scanners = {
        packages = [
          pkgs.gitleaks
          pkgs.trivy
          pkgs.grype
          pkgs.syft
          pkgs.nodejs_22 # cdxgen and saf are npm tools in CI
        ];
        menu = [
          (scan "secrets-scan" "exec gitleaks detect --source . --no-banner" "gitleaks over the git history")
          (scan "fs-scan" "exec trivy fs --severity CRITICAL,HIGH --scanners vuln ."
            "trivy over the working tree, CRITICAL and HIGH"
          )
          (scan "sbom" "exec syft dir:. -o cyclonedx-json=sbom.cdx.json" "write a CycloneDX SBOM of the tree")
        ];
      };
    };
}
