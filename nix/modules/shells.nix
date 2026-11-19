# The shell builder every devShell uses. A shell is the *core* (git, jq, the banner) plus the *sets* it names. A set
# is a bundle of packages, hook lines, banner facts and menu entries that one toolchain contributes, declared where
# the toolchain is defined (ruby.nix, postgres.nix, hdf.nix, browser.nix, python.nix, scanners.nix):
#
#   sparc.mkShell { name = "sparc-scan"; sets = [ "scanners" ]; }
#
# A menu entry is { name, help, cmd, category }: `menu` lists the shell's entries by category, `menu pick` is a
# fuzzy picker, and every entry is a command of its own (_menu.nix writes the wrapper when `cmd` is set).
_: {
  perSystem =
    {
      config,
      pkgs,
      lib,
      ...
    }:
    let
      t = lib.types;
      menuEntry = t.submodule {
        options = {
          name = lib.mkOption {
            type = t.str;
            description = "What is typed: the command's name in the shell and in `menu`.";
          };
          help = lib.mkOption {
            type = t.str;
            description = "One line: what it does.";
          };
          cmd = lib.mkOption {
            type = t.nullOr t.lines;
            default = null;
            description = "The script, run from the repo root. Leave unset when `name` is already a program in the shell.";
          };
          category = lib.mkOption {
            type = t.str;
            default = "app";
          };
        };
      };
      toolSet = t.submodule {
        options = {
          packages = lib.mkOption {
            type = t.listOf t.package;
            default = [ ];
          };
          shellHook = lib.mkOption {
            type = t.lines;
            default = "";
          };
          banner = lib.mkOption {
            type = t.listOf t.str;
            default = [ ];
            description = "Facts for the entry banner, e.g. \"ruby 3.4.12\".";
          };
          menu = lib.mkOption {
            type = t.listOf menuEntry;
            default = [ ];
          };
        };
      };
      renderMenu = import ./_menu.nix pkgs;
    in
    {
      options.sparc = {
        menu = lib.mkOption {
          type = t.listOf menuEntry;
          default = [ ];
          description = "Core menu entries: in every sparc.mkShell shell.";
        };
        sets = lib.mkOption {
          type = t.attrsOf toolSet;
          default = { };
          description = "Named toolchain bundles a shell opts into with `sets = [ ... ]`.";
        };
        mkShell = lib.mkOption {
          type = t.functionTo t.package;
          readOnly = true;
          description = "pkgs.mkShell with the core and the chosen sets folded in.";
        };
      };

      config.sparc.mkShell =
        {
          name,
          sets ? [ ],
          packages ? [ ],
          shellHook ? "",
          menu ? [ ],
        }:
        let
          picked = map (
            n:
            config.sparc.sets.${n}
              or (throw "sparc.mkShell ${name}: no tool set '${n}' (have: ${lib.concatStringsSep ", " (lib.attrNames config.sparc.sets)})")
          ) sets;
          entries = config.sparc.menu ++ lib.concatMap (s: s.menu) picked ++ menu;
          rendered = renderMenu name entries;
          facts = lib.concatStringsSep " · " (lib.concatMap (s: s.banner) picked);
        in
        pkgs.mkShell {
          inherit name;
          packages = [
            pkgs.git
            pkgs.jq
            config.packages.sparc-hello
            config.packages.sparc-onefetch
          ]
          ++ lib.concatMap (s: s.packages) picked
          ++ packages
          ++ rendered.wrappers
          ++ [ rendered.menu ];
          shellHook = lib.concatStringsSep "\n" (
            [
              ''
                export SPARC_ROOT="$(git rev-parse --show-toplevel)"
                export SPARC_SHELL="${name}"
              ''
            ]
            ++ map (s: s.shellHook) picked
            ++ [
              shellHook
              # Printed once when a person enters a shell, never into a pipe or a `-c` command.
              ''
                export SPARC_TOOLS="${facts}"
                if [ -t 1 ] && [ -z "''${SPARC_NO_BANNER:-}" ]; then hello; fi
              ''
            ]
          );
        };
    };
}
