# frozen_string_literal: true

require "rails_helper"
require "open3"
require "tmpdir"
require "fileutils"

# #1120 — every SPARC_* setting the code reads is documented, and every
# setting the documents describe is read. Six documented settings were read by
# nothing, and 16 read settings were documented nowhere, before this check.
RSpec.describe "bin/env_inventory_check.rb" do
  let(:script) { Rails.root.join("bin/env_inventory_check.rb").to_s }

  def run(root = nil)
    env = root ? { "ENV_INVENTORY_ROOT" => root } : {}
    Open3.capture2e(env, "ruby", script)
  end

  it "finds no drift in this repository" do
    out, status = run
    expect(status).to be_success, out
  end

  describe "on a scratch tree" do
    around { |example| Dir.mktmpdir("env-inventory-") { |dir| @dir = dir; example.run } }

    def write(path, content)
      full = File.join(@dir, path)
      FileUtils.mkdir_p(File.dirname(full))
      File.write(full, content)
    end

    def header = "| Variable | Description |\n| --- | --- |\n"

    before do
      write("app/models/sparc_config.rb", <<~RUBY)
        module SparcConfig
          RETIRED_VARIABLES = {
            "SPARC_OLD_FLAG" => "gone"
          }.freeze

          SPARC_ROLES = %w[a b].freeze

          def a = ENV.fetch("SPARC_READ_ONE", nil)
          # SPARC_ONLY_IN_A_COMMENT is not a read
          def b = ENV["SPARC_DB_\#{part}"]
        end
      RUBY
      write("bin/lib/helper.sh", "x=\"${SPARC_READ_TWO:-}\"\n")
      write("docs/ENVIRONMENT_VARIABLES.md",
            "#{header}| SPARC_READ_ONE | a |\n| SPARC_READ_TWO | b |\n| ~~SPARC_OLD_FLAG~~ | retired |\n")
      write("wiki/Configuration.md", "| Variable | Default |\n|---|---|\n| `SPARC_READ_ONE` | x |\n")
      write(".env.example", "# SPARC_READ_TWO=1\n")
      write(".env.production.example", "SPARC_READ_ONE=1\n")
    end

    it "passes a tree in step, ignoring comments, constants and interpolated prefixes" do
      out, status = run(@dir)
      expect(status).to be_success, out
      expect(out).to include("2 variables read in code")
    end

    it "fails on a setting the code reads that the reference does not document" do
      write("lib/new.rb", "ENV.fetch(\"SPARC_BRAND_NEW\", \"1\")\n")
      out, status = run(@dir)
      expect(status).not_to be_success
      expect(out).to include("SPARC_BRAND_NEW is read (lib/new.rb:1) but docs/ENVIRONMENT_VARIABLES.md does not document it")
    end

    it "fails on a documented setting that nothing reads" do
      write("docs/ENVIRONMENT_VARIABLES.md",
            "#{header}| SPARC_READ_ONE | a |\n| SPARC_READ_TWO | b |\n| ~~SPARC_OLD_FLAG~~ | r |\n" \
            "| SPARC_DEAD | d |\n")
      out, status = run(@dir)
      expect(status).not_to be_success
      expect(out).to include("documents SPARC_DEAD as current, but nothing reads it")
    end

    it "fails on a retired setting that is still read" do
      write("app/jobs/stale.rb", "ENV[\"SPARC_OLD_FLAG\"]\n")
      out, status = run(@dir)
      expect(status).not_to be_success
      expect(out).to include("SPARC_OLD_FLAG is retired (SparcConfig::RETIRED_VARIABLES) but still read at app/jobs/stale.rb:1")
    end

    it "fails on a retired setting the reference does not strike through" do
      write("docs/ENVIRONMENT_VARIABLES.md", "#{header}| SPARC_READ_ONE | a |\n| SPARC_READ_TWO | b |\n")
      out, status = run(@dir)
      expect(status).not_to be_success
      expect(out).to include("SPARC_OLD_FLAG is retired but docs/ENVIRONMENT_VARIABLES.md does not list it struck through")
    end

    it "fails on a wiki row or .env example for a setting nothing reads" do
      write("wiki/Configuration.md", "| Variable | Default |\n|---|---|\n| `SPARC_OLD_FLAG` | x |\n")
      write(".env.example", "# SPARC_OLD_FLAG=true\n")
      out, status = run(@dir)
      expect(status).not_to be_success
      expect(out).to include("wiki/Configuration.md shows SPARC_OLD_FLAG as a setting, but nothing reads it")
      expect(out).to include(".env.example shows SPARC_OLD_FLAG as a setting, but nothing reads it")
    end

    it "--report lists drift but exits 0" do
      write("lib/new.rb", "ENV.fetch(\"SPARC_BRAND_NEW\", \"1\")\n")
      out, status = Open3.capture2e({ "ENV_INVENTORY_ROOT" => @dir }, "ruby", script, "--report")
      expect(status).to be_success
      expect(out).to include("SPARC_BRAND_NEW")
    end
  end
end
