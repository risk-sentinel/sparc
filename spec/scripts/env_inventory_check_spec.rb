# frozen_string_literal: true

require "rails_helper"
require "open3"
require "tmpdir"
require "fileutils"

# Loads EnvInventory without running the command: the script guards its entry
# point with `$PROGRAM_NAME == __FILE__`. The checks run in-process so coverage
# sees them; the command itself is still run as a process for its exit codes.
require Rails.root.join("bin/env_inventory_check.rb").to_s

# #1120 — every SPARC_* setting the code reads is documented, and every
# setting the documents describe is read. Six documented settings were read by
# nothing, and 16 read settings were documented nowhere, before this check.
RSpec.describe "bin/env_inventory_check.rb" do
  let(:script) { Rails.root.join("bin/env_inventory_check.rb").to_s }

  def run(root, *args)
    Open3.capture2e({ "ENV_INVENTORY_ROOT" => root }.compact, "ruby", script, *args)
  end

  it "finds no drift in this repository" do
    out, status = run(nil)
    expect(status).to be_success, out
  end

  describe "on a scratch tree" do
    around { |example| Dir.mktmpdir("env-inventory-") { |dir| @dir = dir; example.run } }

    before { allow(EnvInventory).to receive(:root).and_return(@dir) }

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
      expect(EnvInventory.problems).to be_empty
      expect(EnvInventory.summary).to start_with("2 variables read in code")
    end

    it "fails on a setting the code reads that the reference does not document" do
      write("lib/new.rb", "ENV.fetch(\"SPARC_BRAND_NEW\", \"1\")\n")
      expect(EnvInventory.problems).to include(
        "SPARC_BRAND_NEW is read (lib/new.rb:1) but docs/ENVIRONMENT_VARIABLES.md does not document it"
      )
    end

    it "fails on a documented setting that nothing reads" do
      write("docs/ENVIRONMENT_VARIABLES.md",
            "#{header}| SPARC_READ_ONE | a |\n| SPARC_READ_TWO | b |\n| ~~SPARC_OLD_FLAG~~ | r |\n" \
            "| SPARC_DEAD | d |\n")
      expect(EnvInventory.problems).to include(
        "docs/ENVIRONMENT_VARIABLES.md documents SPARC_DEAD as current, but nothing reads it"
      )
    end

    it "fails on a retired setting that is still read" do
      write("app/jobs/stale.rb", "ENV[\"SPARC_OLD_FLAG\"]\n")
      expect(EnvInventory.problems).to include(
        "SPARC_OLD_FLAG is retired (SparcConfig::RETIRED_VARIABLES) but still read at app/jobs/stale.rb:1"
      )
    end

    it "fails on a retired setting the reference does not strike through" do
      write("docs/ENVIRONMENT_VARIABLES.md", "#{header}| SPARC_READ_ONE | a |\n| SPARC_READ_TWO | b |\n")
      expect(EnvInventory.problems).to include(
        "SPARC_OLD_FLAG is retired but docs/ENVIRONMENT_VARIABLES.md does not list it struck through (~~SPARC_OLD_FLAG~~)"
      )
    end

    it "says to strike a retired setting the reference still lists as current" do
      write("docs/ENVIRONMENT_VARIABLES.md",
            "#{header}| SPARC_READ_ONE | a |\n| SPARC_READ_TWO | b |\n| SPARC_OLD_FLAG | still here |\n")
      expect(EnvInventory.problems).to include(
        "docs/ENVIRONMENT_VARIABLES.md documents SPARC_OLD_FLAG as current, but nothing reads it " \
        "(it is retired: strike it through)"
      )
    end

    it "fails on a wiki row or .env example for a setting nothing reads" do
      write("wiki/Configuration.md", "| Variable | Default |\n|---|---|\n| `SPARC_OLD_FLAG` | x |\n")
      write(".env.example", "# SPARC_OLD_FLAG=true\n")
      expect(EnvInventory.problems).to include(
        "wiki/Configuration.md shows SPARC_OLD_FLAG as a setting, but nothing reads it",
        ".env.example shows SPARC_OLD_FLAG as a setting, but nothing reads it"
      )
    end

    it "--list says where each setting is read and how it is documented" do
      write("lib/xlsx.rb", "ENV[\"SPARC_ENABLE_XLSX_UPLOADS\"]\n")
      write("lib/new.rb", "ENV.fetch(\"SPARC_BRAND_NEW\", \"1\")\n")
      listing = EnvInventory.list.join("\n")

      expect(listing).to include("SPARC_READ_ONE\n    read: app/models/sparc_config.rb:8\n    documented")
      expect(listing).to include("SPARC_OLD_FLAG\n    read: nowhere\n    documented as retired")
      expect(listing).to include("SPARC_BRAND_NEW\n    read: lib/new.rb:1\n    UNDOCUMENTED")
      expect(listing).to include("undocumented on purpose (#479")
    end

    describe ".main" do
      it "returns 0 and says so on a tree in step" do
        expect { expect(EnvInventory.main([])).to eq(0) }.to output(/No drift between the code and the documents/).to_stdout
      end

      it "returns 1 on drift, listing each finding" do
        write("lib/new.rb", "ENV.fetch(\"SPARC_BRAND_NEW\", \"1\")\n")
        expect { expect(EnvInventory.main([])).to eq(1) }.to output(/1 drift finding\(s\):\n  - SPARC_BRAND_NEW is read/).to_stdout
      end

      it "returns 0 on drift with --report" do
        write("lib/new.rb", "ENV.fetch(\"SPARC_BRAND_NEW\", \"1\")\n")
        expect { expect(EnvInventory.main([ "--report" ])).to eq(0) }.to output(/SPARC_BRAND_NEW/).to_stdout
      end

      it "returns 0 with --list, ending with the summary" do
        expect { expect(EnvInventory.main([ "--list" ])).to eq(0) }.to output(/SPARC_READ_ONE\n    read: .*\n\n2 variables read in code/m).to_stdout
      end
    end

    # The command, run as the gate runs it.
    describe "the command" do
      before { write("lib/new.rb", "ENV.fetch(\"SPARC_BRAND_NEW\", \"1\")\n") }

      it "exits 1 on drift and names it" do
        out, status = run(@dir)
        expect(status.exitstatus).to eq(1)
        expect(out).to include("SPARC_BRAND_NEW")
      end

      it "--report lists drift but exits 0" do
        out, status = run(@dir, "--report")
        expect(status).to be_success
        expect(out).to include("SPARC_BRAND_NEW")
      end
    end
  end
end
