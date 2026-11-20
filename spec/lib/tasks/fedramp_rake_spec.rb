# frozen_string_literal: true

require "rails_helper"
require "rake"

# #1354 — fedramp:marketplace_check validates every package overview in a
# FedRAMP Marketplace data checkout. A local report, not a CI gate: this
# checks it on a tiny marketplace built in a temporary directory.
RSpec.describe "lib/tasks/fedramp.rake", type: :task do
  before(:all) do
    Rails.application.load_tasks if Rake::Task.tasks.empty?
  end

  let(:task) { Rake::Task["fedramp:marketplace_check"] }
  let(:sample) { JSON.parse(Rails.root.join("samples/fedramp-package-demo/certification-package-overview.json").read) }

  before { task.reenable }

  around do |example|
    Dir.mktmpdir("marketplace") do |dir|
      @dir = dir
      example.run
    end
  end

  def write_marketplace(records)
    File.write(File.join(@dir, FedrampMarketplaceCheck::FILE),
               JSON.generate({ "metadata" => { "total_entries" => records.size }, "data" => { "frc-cso-pkg" => records } }))
  end

  def blank_service(record, index)
    record.merge("certifiedServices" => [ { "serviceName" => "S#{index}", "serviceDescription" => "" } ])
  end

  let(:records) do
    no_trust_center = sample.deep_dup.tap { |r| r["serviceProperties"].delete("trustCenter") }
    bad_enum = sample.deep_dup.tap { |r| r["serviceIdentification"]["certificationType"] = "Rev6" }
    meta_schema = sample.merge("$schema" => "https://json-schema.org/draft/2020-12/schema")
    [ sample, no_trust_center, blank_service(sample, 1), blank_service(sample, 2), bad_enum, meta_schema ]
  end

  it "reports totals, the errors by check and count, and trust-center URLs" do
    write_marketplace(records)

    output = capture_stdout { task.invoke(@dir) }

    expect(output).to include("total:                    6")
    expect(output).to include("valid:                    2")
    expect(output).to include("invalid:                  4")
    expect(output).to match(/with a schema error:\s+1$/)
    expect(output).to match(/with a completeness error:\s+2$/)
    expect(output).to match(/with a readable error:\s+1$/)
    expect(output).to include("with a trust-center URL:  5")
    # Array positions fold together: both blank descriptions are one row.
    expect(output).to match(%r{^\s+2\s+2\s+/certifiedServices/\*/serviceDescription  required field is blank$})
    expect(output).to match(%r{^\s+1\s+1\s+/serviceIdentification/certificationType  value at `/serviceIdentification/certificationType` is not one of})
    expect(output).to include("is not a FedRAMP schema SPARC carries")
  end

  it "reads the directory from FEDRAMP_MARKETPLACE_DIR" do
    write_marketplace([ sample ])

    output = with_marketplace_env(@dir) { capture_stdout { task.invoke } }

    expect(output).to include("total:                    1").and include("valid:                    1")
  end

  it "refuses to run without a directory" do
    with_marketplace_env(nil) do
      expect { task.invoke }.to raise_error(SystemExit).and output(/Name the marketplace checkout/).to_stderr
    end
  end

  it "refuses a directory with no marketplace export" do
    expect { task.invoke(@dir) }.to raise_error(SystemExit).and output(/fedramp-frc-cso-pkg\.json not found/).to_stderr
  end

  def with_marketplace_env(value)
    original = ENV.fetch("FEDRAMP_MARKETPLACE_DIR", nil)
    ENV["FEDRAMP_MARKETPLACE_DIR"] = value
    yield
  ensure
    ENV["FEDRAMP_MARKETPLACE_DIR"] = original
  end

  def capture_stdout
    original = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original
  end
end
