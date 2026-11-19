# hdf: the mitre/hdf-libs CLI, built from source as the Dockerfile and CI do.
# The version is read from the Dockerfile's ARG so the three cannot drift
# (script/ci/hdf_pins.sh checks the same line). A version bump there needs new
# hashes here; the build fails with the right ones when they are stale.
_: {
  perSystem =
    {
      config,
      pkgs,
      lib,
      ...
    }:
    let
      dockerfile = builtins.readFile ../../Dockerfile;
      version = lib.head (builtins.match ".*\nARG HDF_LIBS_VERSION=([0-9.]+)\n.*" dockerfile);
    in
    {
      packages.hdf = pkgs.buildGoModule {
        pname = "hdf";
        inherit version;
        src = pkgs.fetchFromGitHub {
          owner = "mitre";
          repo = "hdf-libs";
          rev = "v${version}";
          hash = "sha256-/8TCg0CrpYAUUSFVD4NYVJNkSXA3k8onn8WT7mccUPo=";
        };
        modRoot = "hdf-cli";
        subPackages = [ "cmd/hdf" ];
        # go.work resolves golang.org/x/text above what hdf-cli/go.mod alone asks for
        # (the Dockerfile asserts that floor), so build through the workspace:
        # proxyVendor downloads modules instead of `go mod vendor`, which refuses one.
        proxyVendor = true;
        vendorHash = "sha256-2toMpzaOKndHidmQ86jAWh/kiVt8oXVhl82mHTjRISQ=";
        env.CGO_ENABLED = 0;
        ldflags = [
          "-s"
          "-w"
          "-X github.com/mitre/hdf-libs/hdf-cli/v3/cmd/hdf/cmd.version=${version}"
        ];
        meta = {
          description = "Heimdall Data Format CLI (mitre/hdf-libs)";
          mainProgram = "hdf";
        };
      };
      sparc.sets.hdf = {
        packages = [ config.packages.hdf ];
        banner = [ "hdf ${version}" ];
      };
    };
}
