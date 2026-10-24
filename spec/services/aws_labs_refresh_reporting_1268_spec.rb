# frozen_string_literal: true

require "rails_helper"

# #1268 — an AWS Labs refresh that imported nothing looked, everywhere an
# operator could look, like one that worked. These pin what each layer now says.
RSpec.describe "AWS Labs refresh reporting (#1268)" do
  let(:fixture_dir) { Rails.root.join("spec/fixtures/files/components/aws_labs") }
  let(:client) { instance_double(AwsLabsCdefSourceClient) }
  let(:log) { StringIO.new }
  let(:logger) { Logger.new(log) }
  let(:tree) do
    [ { "type" => "blob", "path" => "component-definitions/s3/s3-cd.json", "sha" => "sha-s3" },
      { "type" => "blob", "path" => "component-definitions/ec2/ec2-cd.json", "sha" => "sha-ec2" } ]
  end

  before do
    allow(SparcConfig).to receive(:aws_labs_cdef_enabled?).and_return(true)
    allow(client).to receive_messages(current_commit_sha: "commit-sha", list_component_definition_files: tree)
    { "component-definitions/s3/s3-cd.json" => [ "sha-s3", "s3-cd-v1.0.1.json" ],   # oscal-version 1.1.2
      "component-definitions/ec2/ec2-cd.json" => [ "sha-ec2", "ec2-cd.json" ] }      # oscal-version 1.0.4
      .each do |path, (sha, file)|
        allow(client).to receive(:fetch_file).with(path: path)
          .and_return(path: path, sha: sha, html_url: "https://example.com/#{path}", content: fixture_dir.join(file).read)
      end
  end

  describe "SparcConfig.parse_version_list" do
    {
      "1.2.1, 1.2.2" => %w[1.2.1 1.2.2],
      "1.2.1 1.2.2" => %w[1.2.1 1.2.2],
      "1.2.1;1.2.2" => %w[1.2.1 1.2.2],
      '["1.2.1","1.2.2"]' => %w[1.2.1 1.2.2],
      "v1.2.1,V1.2.2" => %w[1.2.1 1.2.2],
      "\"1.2.1, 1.2.2\"" => %w[1.2.1 1.2.2],
      "1.2.1,,1.2.1 " => %w[1.2.1]
    }.each do |raw, parsed|
      it "reads #{raw.inspect} as #{parsed.inspect}" do
        expect(SparcConfig.parse_version_list(raw)).to eq(parsed)
      end
    end
  end

  describe AwsLabsCdefImportService do
    def run_with(versions)
      described_class.new(client: client, allowed_oscal_versions: versions, logger: logger).run(force: true)
    end

    it "counts and names the files the version filter skipped" do
      allow(client).to receive(:remember_tree_etag!)

      result = run_with(%w[1.1.2])

      expect(result.kept).to eq(1)
      expect(result.skipped_by_version).to eq("1.0.4" => 1)
      expect(result.kept_nothing?).to be(false)
      expect(log.string).to match(/WARN.*Version filter skipped 1 of 2 files\. Found: 1\.0\.4 \(1 files\)\. Allowed .*: 1\.1\.2\./)
    end

    it "reports a run that kept nothing as an error, and does not remember the listing" do
      expect(client).not_to receive(:remember_tree_etag!)

      result = run_with(%w[1.2.3])

      expect(result.kept_nothing?).to be(true)
      expect(result.skipped_by_version).to eq("1.1.2" => 1, "1.0.4" => 1)
      expect(log.string).to match(/ERROR.*Nothing was kept/)
    end

    it "remembers the listing once a run imported something" do
      expect(client).to receive(:remember_tree_etag!).once

      expect(run_with(%w[1.1.2 1.0.4]).imported).to eq(2)
    end

    it "warns about an allowed version SPARC has no schema for" do
      allow(OscalSchema).to receive_message_chain(:distinct, :pluck).and_return(%w[1.1.2 1.2.3])
      allow(client).to receive(:remember_tree_etag!)

      run_with(%w[1.1.2 9.9.9])

      expect(log.string).to match(/WARN.*names 9\.9\.9, which SPARC has no OSCAL schema for/)
    end
  end

  describe AwsLabsCdefSourceClient do
    let(:real) { described_class.new(repo: "o/r", branch: "main", token: nil) }
    let(:cache) { ActiveSupport::Cache::MemoryStore.new }
    let(:key) { "aws_labs_cdef:etag:tree:o/r:main" }

    before do
      allow(Rails).to receive(:cache).and_return(cache)
      response = Net::HTTPOK.new("1.1", "200", "OK")
      allow(response).to receive(:body).and_return({ "tree" => [] }.to_json)
      response["etag"] = 'W/"abc"'
      allow(real).to receive(:get).and_return(response)
    end

    it "holds the listing's ETag until the import remembers it" do
      real.list_component_definition_files
      expect(cache.read(key)).to be_nil

      real.remember_tree_etag!
      expect(cache.read(key)).to eq('W/"abc"')
    end
  end

  describe AwsLabsCdefRefreshJob do
    let(:service) { instance_double(AwsLabsCdefImportService) }

    before { allow(AwsLabsCdefImportService).to receive(:new).and_return(service) }

    def result(**overrides)
      AwsLabsCdefImportService::Result.new(discovered: 2, imported: 0, skipped_unchanged: 0, superseded: 0,
                                           errors: [], kept: 0, skipped_by_version: { "1.1.2" => 2 },
                                           allowed_versions: %w[1.2.3], **overrides)
    end

    it "records that it started and that it kept nothing" do
      allow(service).to receive(:run).and_return(result)

      described_class.perform_now(force: true)

      expect(AuditEvent.where(action: "aws_labs_cdef_refresh_started")).to exist
      kept_nothing = AuditEvent.find_by(action: "aws_labs_cdef_refresh_kept_nothing")
      expect(kept_nothing.metadata).to include("discovered" => 2, "kept" => 0, "skipped_by_version" => { "1.1.2" => 2 })
      expect(AwsLabsRefreshStatus.current.state).to eq(:kept_nothing)
    end

    it "records a completed run" do
      allow(service).to receive(:run).and_return(result(kept: 2, imported: 2, skipped_by_version: {}))

      described_class.perform_now(force: true)

      expect(AwsLabsRefreshStatus.current.message).to match(/2 imported, 0 unchanged, 0 failed, of 2 upstream files\.\z/)
    end

    it "records a failure and still raises it" do
      allow(service).to receive(:run).and_raise(AwsLabsCdefSourceClient::RateLimitedError, "Invented limit")

      expect { described_class.perform_now(force: true) }.to raise_error(AwsLabsCdefSourceClient::RateLimitedError)
      expect(AwsLabsRefreshStatus.current.message).to match(/failed: AwsLabsCdefSourceClient::RateLimitedError: Invented limit/)
    end
  end

  describe AwsLabsRefreshStatus do
    def event(action, at: Time.current, **metadata)
      AuditEvent.log(action: action, metadata: metadata).tap { _1.update_columns(created_at: at) }
    end

    it "says when nothing has been recorded" do
      expect(described_class.current.state).to eq(:never)
    end

    it "says a refresh was queued, then that it never started" do
      event("aws_labs_cdef_refresh_requested")
      expect(described_class.current.state).to eq(:queued)

      AuditEvent.update_all(created_at: 20.minutes.ago)
      expect(described_class.current.message).to match(/never started\. Check that the job worker is running/)
    end

    it "says a refresh is running, then that it is stuck" do
      event("aws_labs_cdef_refresh_started")
      expect(described_class.current.state).to eq(:running)

      AuditEvent.update_all(created_at: 20.minutes.ago)
      expect(described_class.current.state).to eq(:stuck)
    end

    it "names the versions a run that kept nothing skipped, and the versions allowed" do
      event("aws_labs_cdef_refresh_kept_nothing", discovered: 230, kept: 0,
            skipped_by_version: { "1.2.1" => 230 }, allowed_versions: %w[1.2.3])

      status = described_class.current
      expect(status.tone).to eq(:warning)
      expect(status.message).to match(/imported nothing: the version filter kept none of the 230 upstream files\. /)
      expect(status.message).to end_with("Skipped by OSCAL version: 1.2.1 (230); SPARC_AWS_LABS_OSCAL_VERSIONS allows 1.2.3.")
    end

    it "reads the latest event only" do
      event("aws_labs_cdef_refresh_failed", at: 2.hours.ago, error_class: "X", error_message: "y")
      event("aws_labs_cdef_refresh_completed", discovered: 0)

      expect(described_class.current.state).to eq(:unchanged)
    end
  end
end
