# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("lib/storage_url/config")

# #785 Pass 2.1 — SPARC_STORAGE_URL: one variable for object storage, scheme →
# provider, with ACTIVE_STORAGE_SERVICE + AWS_BUCKET kept as a fallback.
RSpec.describe StorageUrl do
  around do |ex|
    keys = %w[SPARC_STORAGE_URL ACTIVE_STORAGE_SERVICE AWS_BUCKET AWS_REGION]
    saved = keys.to_h { |k| [ k, ENV[k] ] }
    keys.each { |k| ENV.delete(k) }
    ex.run
    saved.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
  end

  describe "with SPARC_STORAGE_URL set" do
    it "derives an S3 backend from s3://bucket" do
      ENV["SPARC_STORAGE_URL"] = "s3://my-bucket"
      expect(described_class.service).to eq(:amazon)
      expect(described_class.bucket).to eq("my-bucket")
      expect(described_class.local?).to be(false)
    end

    it "takes region from the ?region= query" do
      ENV["SPARC_STORAGE_URL"] = "s3://my-bucket?region=us-gov-west-1"
      expect(described_class.region).to eq("us-gov-west-1")
    end

    it "falls back to AWS_REGION when the URL has no region" do
      ENV["SPARC_STORAGE_URL"] = "s3://my-bucket"
      ENV["AWS_REGION"] = "eu-west-1"
      expect(described_class.region).to eq("eu-west-1")
    end

    it "defaults the region to us-east-1 when nothing supplies one" do
      ENV["SPARC_STORAGE_URL"] = "s3://my-bucket"
      expect(described_class.region).to eq("us-east-1")
    end

    it "wins over the legacy ACTIVE_STORAGE_SERVICE / AWS_BUCKET" do
      ENV["SPARC_STORAGE_URL"] = "s3://new-bucket"
      ENV["ACTIVE_STORAGE_SERVICE"] = "local"
      ENV["AWS_BUCKET"] = "legacy-bucket"
      expect(described_class.service).to eq(:amazon)
      expect(described_class.bucket).to eq("new-bucket")
    end
  end

  describe "legacy fallback (SPARC_STORAGE_URL unset)" do
    it "honours ACTIVE_STORAGE_SERVICE + AWS_BUCKET unchanged" do
      ENV["ACTIVE_STORAGE_SERVICE"] = "amazon"
      ENV["AWS_BUCKET"] = "legacy-bucket"
      ENV["AWS_REGION"] = "us-east-2"
      expect(described_class.service).to eq(:amazon)
      expect(described_class.bucket).to eq("legacy-bucket")
      expect(described_class.region).to eq("us-east-2")
    end
  end

  describe "with nothing set" do
    it "resolves to local (the production posture check turns this into a hard fail)" do
      expect(described_class.service).to eq(:local)
      expect(described_class.local?).to be(true)
    end
  end

  describe "resilience" do
    it "treats a malformed URL as local rather than raising" do
      ENV["SPARC_STORAGE_URL"] = ":: not a url ::"
      expect { described_class.service }.not_to raise_error
      expect(described_class.local?).to be(true)
    end

    it "treats a blank SPARC_STORAGE_URL as unset" do
      ENV["SPARC_STORAGE_URL"] = ""
      expect(described_class.configured?).to be(false)
    end
  end
end

# storage.yml must stay parseable as raw YAML (editors/tooling read it without
# rendering ERB — the #788 lesson).
RSpec.describe "storage.yml" do
  it "parses as raw YAML" do
    expect {
      YAML.load_file(Rails.root.join("config/storage.yml"), aliases: true)
    }.not_to raise_error
  end
end
