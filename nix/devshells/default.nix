# The shells. `nix develop` is everything CI's lint, test and local-runnable scan jobs install on a runner.
# `nix develop .#scan` is the scanners alone: no Ruby, no database, nothing to compile.
_:
let
  check = import ../modules/_entry.nix "check";
in
{
  perSystem =
    { config, ... }:
    {
      devShells = {
        default = config.sparc.mkShell {
          name = "sparc";
          sets = [
            "ruby"
            "postgres"
            "hdf"
            "browser"
            "python"
            "scanners"
          ];
          menu = [
            (check "lint" ''
              rubocop
              yaml-lint
              py-lint
            '' "all three of CI's lint jobs")
          ];
        };
        scan = config.sparc.mkShell {
          name = "sparc-scan";
          sets = [ "scanners" ];
        };
      };
    };
}
