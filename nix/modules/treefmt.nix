# treefmt-nix: `nix fmt` and the `treefmt` flake check, for the Nix files only. Ruby, YAML and Python
# keep the linters CI already runs (rubocop, yamllint, ruff).
{ inputs, ... }:
let
  nix = import ./_entry.nix "nix";
in
{
  imports = [ inputs.treefmt-nix.flakeModule ];
  perSystem = _: {
    treefmt = {
      projectRootFile = "flake.nix";
      programs = {
        nixfmt.enable = true;
        deadnix.enable = true;
        statix.enable = true;
      };
    };
    sparc.menu = [
      (nix "fmt" "exec nix fmt" "format the Nix files (nixfmt, deadnix, statix)")
      (nix "check" "exec nix flake check" "nix flake check: formatting and every shell evaluates")
      (nix "update" "exec nix flake update" "update flake.lock (review the diff before committing)")
    ];
  };
}
