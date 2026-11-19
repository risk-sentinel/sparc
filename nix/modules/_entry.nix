# A menu entry (see shells.nix), written positionally so a module's entries are one call each:
# `db = import ./_entry.nix "db";` then `(db "db-down" "pg_ctl stop --mode=fast" "stop Postgres")`.
category: name: cmd: help: {
  inherit
    category
    name
    cmd
    help
    ;
}
