# Ruby and what the bundle's native gems compile against, as the `ruby` set. Gems install into .devshell/gems
# (gitignored), never the store or $HOME. The pg gem builds from source (Gemfile: force_ruby_platform), which is
# why pg_config is here and not only in the postgres set.
_:
let
  app = import ./_entry.nix "app";
  test = import ./_entry.nix "test";
  check = import ./_entry.nix "check";
  scan = import ./_entry.nix "scan";
in
{
  perSystem =
    { pkgs, ... }:
    let
      ruby = pkgs.ruby_3_4; # .ruby-version; the hook warns when the two disagree
    in
    {
      sparc.sets.ruby = {
        packages = [
          ruby
          pkgs.postgresql_15.pg_config
          pkgs.pkg-config
          pkgs.openssl
          pkgs.zlib
          pkgs.libyaml
          pkgs.libffi
        ];
        banner = [ "ruby ${ruby.version}" ];
        shellHook = ''
          export GEM_HOME="$SPARC_ROOT/.devshell/gems"
          export GEM_PATH="$GEM_HOME"
          export PATH="$GEM_HOME/bin:$PATH"
          mkdir -p "$GEM_HOME"
          want="$(sed 's/^ruby-//' "$SPARC_ROOT/.ruby-version")"
          if [ "$want" != "${ruby.version}" ]; then
            echo "warning: .ruby-version wants $want, this shell has ${ruby.version} (nix flake update, or pin ruby in nix/modules/ruby.nix)" >&2
          fi
        '';
        menu = [
          (app "setup" ''
            db-up
            bundle install
            bin/rails db:prepare
            RAILS_ENV=test bin/rails db:test:prepare
          '' "first run: start Postgres, install gems, prepare the dev and test databases")
          (app "server" ''exec bin/rails server "$@"'' "bin/rails server: development mode, hot reloading")
          (app "console" ''exec bin/rails console "$@"'' "bin/rails console")
          (test "spec" ''RAILS_ENV=test exec bundle exec rspec "$@"''
            "the RSpec suite as CI's test job runs it (pass paths to narrow)"
          )
          (check "rubocop" ''exec bundle exec rubocop "$@"'' "CI's lint job")
          (scan "brakeman" ''exec bundle exec brakeman --no-pager --quiet "$@"'' "static security analysis")
          (scan "gem-audit" "exec bundle exec bundler-audit check --update"
            "known-vulnerable gems in Gemfile.lock"
          )
        ];
      };
    };
}
