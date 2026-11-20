# frozen_string_literal: true

require "rails_helper"

# #1354 — a demo instance's boundary holds the FedRAMP sample package as
# received documents, waiting for review, so the Received documents screen
# has something to show on a fresh install.
RSpec.describe "db/seeds/fedramp_package_samples.rb" do
  let(:seed_path) { Rails.root.join("db/seeds/fedramp_package_samples.rb") }
  let(:manifest) { JSON.parse(Rails.root.join("samples/fedramp-package-demo/manifest.json").read) }

  def run_seed
    original = $stdout
    $stdout = StringIO.new
    load seed_path
    $stdout.string
  ensure
    $stdout = original
  end

  context "with the demo boundary" do
    let!(:boundary) { create(:authorization_boundary, name: "Cloud Web Application ATO") }

    it "stores every valid sample as an upload waiting for review, with no uploader" do
      run_seed

      docs = ReceivedDocument.where(authorization_boundary: boundary)
      expect(docs.count).to eq(manifest["documents"].size)
      expect(docs.pluck(:filename)).to match_array(manifest["documents"].map { |d| d["file"] })
      expect(docs.pluck(:state).uniq).to eq([ "pending_review" ])
      expect(docs.pluck(:source).uniq).to eq([ "upload" ])
      expect(docs.pluck(:valid_document).uniq).to eq([ true ])
      expect(docs.pluck(:received_by_id).uniq).to eq([ nil ])
    end

    it "stores nothing on a second run: each stream already holds the bytes" do
      run_seed

      expect { expect(run_seed).to include("0 stored, #{manifest['documents'].size} already held") }
        .not_to change(ReceivedDocument, :count)
    end
  end

  it "skips, storing nothing, without the demo boundary" do
    expect { expect(run_seed).to include("Skipped the FedRAMP sample package") }.not_to change(ReceivedDocument, :count)
  end

  it "runs as its own demo section, so an existing demo install picks it up" do
    expect(SeedRunner::CURRENT_VERSIONS).to include("demo_fedramp_package_samples" => "1.0.0")
    seeds = Rails.root.join("db/seeds.rb").read
    section = seeds[/^if SEED_DEMO\nSeedRunner\.run_section\("demo_fedramp_package_samples"\) do\n.*?\nend # if SEED_DEMO/m]
    expect(section).to include('load Rails.root.join("db/seeds/fedramp_package_samples.rb")')
  end
end
