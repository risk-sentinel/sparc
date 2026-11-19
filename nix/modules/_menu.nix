# Builds a shell's commands from its menu entries: { name, help, cmd, category }.
#   menu              the entries grouped by category
#   menu pick         a fuzzy picker (fzf); Enter runs the choice
#   menu <name> ...   runs one
# Every entry is also a command of its own: an entry with a `cmd` gets a wrapper called `name` that runs the
# script from the repo root (arguments arrive as "$@"). An entry without one is a program already in the shell.
# Returns { menu, wrappers }.
pkgs: shell: entries:
let
  inherit (pkgs) lib;
  esc = builtins.fromJSON ''"\u001b"'';
  accent = "${esc}[1;38;2;64;156;255m";
  blue = "${esc}[38;2;90;150;240m";
  bold = "${esc}[1m";
  dim = "${esc}[2m";
  reset = "${esc}[0m";

  order = [
    "app"
    "db"
    "test"
    "check"
    "scan"
    "repo"
    "nix"
  ];
  present = lib.unique (map (e: e.category) entries);
  categories =
    lib.filter (c: lib.elem c present) order
    ++ lib.sort (a: b: a < b) (lib.subtractLists order present);
  width = lib.foldl' lib.max 0 (map (e: lib.stringLength e.name) entries);
  pad = s: s + lib.concatStrings (lib.genList (_: " ") (width - lib.stringLength s));
  section =
    c:
    "  ${accent}${c}${reset}\n"
    + lib.concatMapStrings (e: "    ${bold}${pad e.name}${reset}  ${dim}${e.help}${reset}\n") (
      lib.filter (e: e.category == c) entries
    );
  listing = pkgs.writeText "menu-${shell}.txt" (
    "\n"
    + lib.concatStringsSep "\n" (map section categories)
    + "\n  ${blue}menu pick${reset}${dim} chooses one with a fuzzy search · every name above is a command${reset}\n\n"
  );
  rows = pkgs.writeText "menu-${shell}.tsv" (
    lib.concatMapStrings (e: "${e.name}\t${e.category}\t${e.help}\n") entries
  );

  wrapper =
    e:
    pkgs.writeShellScriptBin e.name ''
      set -euo pipefail
      cd "$(${pkgs.git}/bin/git rev-parse --show-toplevel)"
      ${e.cmd}
    '';
in
{
  wrappers = map wrapper (lib.filter (e: e.cmd != null) entries);
  menu = pkgs.writeShellScriptBin "menu" ''
    set -euo pipefail
    case "''${1:-}" in
      "")
        if [ -t 1 ]; then cat ${listing}; else ${pkgs.gnused}/bin/sed 's/\x1b\[[0-9;]*m//g' ${listing}; fi ;;
      pick)
        choice="$(${pkgs.fzf}/bin/fzf --delimiter '\t' --with-nth '1,3' --tabstop 16 --height '~60%' --reverse \
          --prompt '${shell} > ' --header 'Enter runs it, Esc leaves' < ${rows} | ${pkgs.coreutils}/bin/cut -f1)" || exit 0
        [ -n "$choice" ] || exit 0
        echo "+ $choice"
        exec "$choice" ;;
      -h|--help)
        ${pkgs.gnused}/bin/sed -n '2,4s/^# *//p' ${./_menu.nix} ;;
      *)
        if ${pkgs.coreutils}/bin/cut -f1 ${rows} | ${pkgs.gnugrep}/bin/grep -qxF -- "$1"; then exec "$@"; fi
        echo "menu: no command '$1' in the ${shell} shell" >&2
        exit 1 ;;
    esac
  '';
}
