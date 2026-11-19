# Python for tests/api and tests/ui-smoke, and the two non-Ruby linters CI runs, as the `python` set.
# uv uses the shell's interpreter: one it downloads itself cannot run on NixOS.
_:
let
  check = import ./_entry.nix "check";
in
{
  perSystem =
    { pkgs, lib, ... }:
    {
      sparc.sets.python = {
        packages = [
          pkgs.python312
          pkgs.uv
          pkgs.ruff
          pkgs.yamllint
        ];
        shellHook = ''
          export UV_PYTHON_DOWNLOADS=never
          export UV_PYTHON="${lib.getExe pkgs.python312}"
        '';
        menu = [
          (check "yaml-lint" "exec yamllint config/ .github/ docker-compose*.yaml docs/compliance/"
            "CI's yaml_lint job"
          )
          (check "py-lint" "exec ruff check tests/api tests/ui-smoke" "CI's python_lint job")
        ];
      };
    };
}
