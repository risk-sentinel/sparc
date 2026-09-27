# frozen_string_literal: true

require "rails_helper"
require "open3"
require "tmpdir"

# #1151 — the boot gate: a web container whose schema does not match its image
# never starts its server.
#
# Runs the REAL bin/docker-entrypoint with `pg_isready`, `bundle` and `rails`
# replaced on PATH by stubs that record their arguments. So what is asserted is
# the script's own control flow — the order of the steps, and that a failed
# schema gate stops the container before `exec` — without a database or an
# image. What the rake tasks themselves do is covered by their own specs.
RSpec.describe "bin/docker-entrypoint" do
  around do |example|
    Dir.mktmpdir("entrypoint") do |dir|
      @dir = dir
      @log = File.join(dir, "calls.log")
      stub("pg_isready", "exit 0")
      # Fails the call whose arguments match $FAIL_ON, records every call.
      stub("bundle", <<~SH)
        echo "bundle $*" >> "#{@log}"
        if [ -n "${FAIL_ON:-}" ] && [[ "$*" == *"$FAIL_ON"* ]]; then echo "stub: failing $*" >&2; exit 1; fi
        exit 0
      SH
      stub("rails", %(echo "SERVER STARTED $*" >> "#{@log}"))
      example.run
    end
  end

  def stub(name, body)
    path = File.join(@dir, name)
    File.write(path, "#!/usr/bin/env bash\n#{body}\n")
    File.chmod(0o755, path)
  end

  def boot(*command, fail_on: nil)
    env = { "PATH" => "#{@dir}:#{ENV.fetch('PATH')}", "SPARC_DB_HOST" => "db", "SPARC_DB_PORT" => "5432" }
    env["FAIL_ON"] = fail_on if fail_on
    %w[DATABASE_URL DB_CREDENTIALS SPARC_EXTRA_CA_CERTS SPARC_RUN_SEEDS LD_PRELOAD].each { |k| env[k] = nil }
    out, err, status = Open3.capture3(env, Rails.root.join("bin/docker-entrypoint").to_s, *command)
    [ out + err, status, File.exist?(@log) ? File.readlines(@log, chomp: true) : [] ]
  end

  it "reconciles and verifies the schema after db:prepare and before the server starts" do
    _output, status, calls = boot("rails", "server")

    expect(status).to be_success
    prepare = calls.index("bundle exec rails db:prepare")
    gate = calls.index("bundle exec rails db:reconcile_schema db:verify_schema")
    server = calls.index { |c| c.start_with?("SERVER STARTED") }
    expect([ prepare, gate, server ]).to all(be_an(Integer))
    expect(prepare).to be < gate
    expect(gate).to be < server
  end

  it "gates the schema BEFORE seeding, which assumes the schema is there" do
    _output, _status, calls = boot("rails", "server")

    expect(calls.index("bundle exec rails db:reconcile_schema db:verify_schema"))
      .to be < calls.index("bundle exec rails db:seed")
  end

  it "refuses to start the server when the schema gate fails — the v1.16.2 case" do
    output, status, calls = boot("rails", "server", fail_on: "db:verify_schema")

    expect(status).not_to be_success
    expect(calls.grep(/SERVER STARTED/)).to be_empty
    expect(calls).not_to include("bundle exec rails db:seed")
    expect(output).to include("refusing to start the web server")
  end

  it "refuses when reconciliation refuses, too" do
    _output, status, calls = boot("rails", "server", fail_on: "db:reconcile_schema")

    expect(status).not_to be_success
    expect(calls.grep(/SERVER STARTED/)).to be_empty
  end

  it "leaves non-server commands alone — only the web container prepares the database" do
    _output, status, calls = boot("rails", "console")

    expect(status).to be_success
    expect(calls.grep(/db:/)).to be_empty
  end
end
