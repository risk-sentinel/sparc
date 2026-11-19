# The SPARC mark as terminal art (the lightning bolt of public/icon.png, drawn by hand in nix/brand/:
# mark.ansi is the purple one, mark.txt the same without colour) and the two things that show it:
#   hello      what a shell prints on entry: the mark beside the few facts worth a glance
#   onefetch   the repository summary (languages, commits, size) with the mark as its art
_: {
  perSystem =
    { pkgs, ... }:
    let
      brand = pkgs.runCommand "sparc-brand" { } ''
        mkdir -p $out
        cp ${../brand/mark.ansi} $out/mark.ansi
        cp ${../brand/mark.txt} $out/mark.txt
      '';

      onefetch = pkgs.writeShellApplication {
        name = "sparc-onefetch";
        runtimeInputs = [
          pkgs.git
          pkgs.onefetch
        ];
        text = ''
          cd "$(git rev-parse --show-toplevel)"
          exec onefetch --ascii-input "$(cat ${brand}/mark.txt)" "$@"
        '';
      };

      # Nothing here may be slow: no nix, no network, no Ruby. Git, a few file tests and one pg_ctl.
      hello = pkgs.writeShellApplication {
        name = "hello";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.git
          pkgs.gnused
        ];
        text = ''
          root="$(git rev-parse --show-toplevel 2>/dev/null)" || root=""
          e=$(printf '\033')
          label="''${e}[38;2;120;150;255m" accent="''${e}[1;38;2;150;110;255m" bold="''${e}[1m" dim="''${e}[2m" off="''${e}[0m"
          sep=" $dim·$off "
          version=""
          if [ -n "$root" ] && [ -f "$root/app/models/sparc_config.rb" ]; then
            version="$(sed -n 's/^ *VERSION *= *"\(.*\)".*/\1/p' "$root/app/models/sparc_config.rb" | head -1)"
          fi
          info=("" "''${accent}SPARC$off ''${bold}$version$off  ''${dim}NIST 800-53 compliance documentation$off" "")
          row() { info+=("$label$(printf '%-7s' "$1")$off $2"); }
          row shell "''${SPARC_SHELL:-sparc}"
          if [ -n "$root" ]; then
            dirty="$(git -C "$root" status --porcelain 2>/dev/null | wc -l)"
            state="clean"
            [ "$dirty" -gt 0 ] && state="$dirty uncommitted"
            row branch "$(git -C "$root" branch --show-current)$sep$(git -C "$root" rev-parse --short HEAD)$sep$state"
            subject="$(git -C "$root" log -1 --format=%s)"
            [ "''${#subject}" -gt 58 ] && subject="''${subject:0:57}…"
            row last "$subject ''${dim}($(git -C "$root" log -1 --format=%cr))$off"
          fi
          [ -n "''${SPARC_TOOLS:-}" ] && row tools "''${SPARC_TOOLS// · /$sep}"
          if [ -n "''${PGDATA:-}" ]; then
            if [ ! -s "$PGDATA/PG_VERSION" ]; then
              row db "''${dim}not created ·$off ''${bold}setup$off''${dim} builds it$off"
            elif command -v pg_ctl >/dev/null 2>&1 && pg_ctl status >/dev/null 2>&1; then
              row db "running''${sep}socket ''${PGHOST/#$root\//}"
            else
              row db "''${dim}stopped ·$off ''${bold}db-up$off''${dim} starts it$off"
            fi
          fi
          if [ -n "''${GEM_HOME:-}" ]; then
            rails=("$GEM_HOME"/gems/rails-[0-9]*)
            if [ -d "''${rails[0]}" ]; then
              row gems "installed''${sep}''${GEM_HOME/#$root\//}"
            else
              row gems "''${dim}not installed ·$off ''${bold}setup$off''${dim} installs them$off"
            fi
          fi
          info+=("" "''${bold}menu$off''${dim} lists the commands ·$off ''${bold}menu pick$off''${dim} chooses one$off")
          mapfile -t art < <(sed 's/\x1b\[?25[lh]//g' ${brand}/mark.ansi)
          n=''${#art[@]}
          [ "''${#info[@]}" -gt "$n" ] && n=''${#info[@]}
          echo
          for ((i = 0; i < n; i++)); do
            printf ' %s%s\033[34G%s\n' "''${art[i]:-}" "$off" "''${info[i]:-}"
          done
          echo
        '';
      };
    in
    {
      packages = {
        inherit brand;
        sparc-hello = hello;
        sparc-onefetch = onefetch;
      };
      sparc.menu = [
        {
          name = "hello";
          help = "the entry summary again: branch, last commit, database, gems";
          category = "repo";
        }
        {
          name = "onefetch";
          help = "repository summary (languages, commits, size) with the SPARC mark";
          cmd = ''exec sparc-onefetch "$@"'';
          category = "repo";
        }
      ];
    };
}
