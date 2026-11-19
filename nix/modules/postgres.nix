# A Postgres private to the shell, as the `postgres` set: data in .devshell/pg (gitignored), listening on a unix
# socket only, so it cannot collide with the compose stack's 5433 or a system Postgres. config/database.yml names
# no host or user, so libpq's PGHOST (the socket directory) and the OS user are all Rails needs.
# fsync is off: this database holds dev and test data that `setup` rebuilds.
_:
let
  db = import ./_entry.nix "db";
in
{
  perSystem =
    { pkgs, ... }:
    let
      postgres = pkgs.postgresql_15; # CI's upgrade_path job pins postgres:15
    in
    {
      sparc.sets.postgres = {
        packages = [ postgres ];
        banner = [ "postgres ${postgres.version}" ];
        shellHook = ''
          export PGHOST="$SPARC_ROOT/.devshell/pg"
          export PGDATA="$PGHOST/data"
          mkdir -p "$PGHOST"
        '';
        menu = [
          (db "db-up" ''
            if [ ! -s "$PGDATA/PG_VERSION" ]; then
              initdb --auth=trust --encoding=UTF8 --locale=C.UTF-8 >/dev/null
            fi
            if pg_ctl status >/dev/null 2>&1; then
              echo "Postgres is already running ($PGHOST)"
            else
              pg_ctl start --wait --log="$PGHOST/postgres.log" \
                -o "-c listen_addresses= -c unix_socket_directories=$PGHOST -c fsync=off -c full_page_writes=off"
            fi
          '' "start the shell's Postgres (creates it on first use)")
          (db "db-down" "pg_ctl stop --mode=fast" "stop the shell's Postgres")
          (db "db-status" "pg_ctl status" "is the shell's Postgres running")
          (db "db-shell" ''exec psql "''${1:-ssp_tpr_manager_development}"''
            "psql into the dev database (or the one named)"
          )
          (db "db-reset" ''
            pg_ctl stop --mode=fast >/dev/null 2>&1 || true
            rm -rf "$PGDATA"
            echo "deleted $PGDATA; run setup to rebuild"
          '' "stop Postgres and delete its data directory")
        ];
      };
    };
}
