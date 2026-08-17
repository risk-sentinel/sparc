# frozen_string_literal: true

require "rails_helper"

# #939 — what a FAILED AWS Labs import leaves behind.
#
# The filed cause ("GitHub rate limiting") did not survive measurement: the
# per-candidate import loop holds `candidate[:content]` already and performs no
# network I/O, so it cannot be counting rate limits. The real defect was
# structural and is what these examples pin.
#
# `write_through_parser` created the CdefDocument BEFORE the parse. The parser
# opens its own transaction and rolls back cleanly, but the `create!` above it
# did not, so a parse failure left a shell row: status "processing", zero
# controls, and no `source_type` — which put it outside
# `CdefDocument.aws_labs_sourced`, so the dedupe could not see it, and the next
# refresh leaked another one instead of reusing it. 82 were measured on one
# instance after four passes.
#
# The corpus imports cleanly on current main (a live pass measured
# discovered=230 imported=230 errors=0), so these examples induce the failure
# rather than waiting for upstream content to misbehave. That is the point: the
# leak is latent, not gone.
RSpec.describe AwsLabsCdefImportService, "failure handling (#939)" do
  let(:fixture_dir) { Rails.root.join("spec/fixtures/files/components/aws_labs") }
  let(:s3)  { fixture_dir.join("s3-cd-v1.0.0.json").read }
  let(:ec2) { fixture_dir.join("ec2-cd.json").read }

  let(:client) { instance_double(AwsLabsCdefSourceClient) }

  before do
    allow(SparcConfig).to receive(:aws_labs_cdef_enabled?).and_return(true)
    allow(SparcConfig).to receive(:aws_labs_cdef_repo).and_return("awslabs/oscal-content-for-aws-services")
    allow(SparcConfig).to receive(:aws_labs_cdef_branch).and_return("main")
    allow(client).to receive(:current_commit_sha).and_return("commit-sha-aaaa")
  end

  def tree_entry(path:, sha:)
    { "type" => "blob", "path" => path, "sha" => sha }
  end

  def file_entry(path:, sha:, content:)
    {
      path: path,
      sha: sha,
      html_url: "https://github.com/awslabs/oscal-content-for-aws-services/blob/main/#{path}",
      content: content
    }
  end

  describe "a file whose parse fails" do
    before do
      allow(client).to receive(:list_component_definition_files).and_return([
        tree_entry(path: "component-definitions/s3/s3-cd.json",   sha: "sha-s3"),
        tree_entry(path: "component-definitions/ec2/ec2-cd.json", sha: "sha-ec2")
      ])
      allow(client).to receive(:fetch_file)
        .with(path: "component-definitions/s3/s3-cd.json")
        .and_return(file_entry(path: "component-definitions/s3/s3-cd.json", sha: "sha-s3", content: s3))
      allow(client).to receive(:fetch_file)
        .with(path: "component-definitions/ec2/ec2-cd.json")
        .and_return(file_entry(path: "component-definitions/ec2/ec2-cd.json", sha: "sha-ec2", content: ec2))

      # Fail the parse for S3 only. Raising from the parser is the shape every
      # real failure took — CdefMutationService::ValidationError, a
      # RecordInvalid, or a parse error all arrive here identically.
      allow_any_instance_of(CdefJsonParserService).to receive(:parse).and_wrap_original do |original, *args|
        doc = original.receiver.instance_variable_get(:@document)
        raise CdefMutationService::ValidationError, "induced failure" if doc.name.to_s.include?("s3")

        original.call(*args)
      end
    end

    it "leaves NO document behind for the failed file" do
      expect { described_class.new(client: client).run }
        .not_to change { CdefDocument.unscoped.where("name LIKE ?", "%s3%").count }.from(0)
    end

    it "leaves no orphan in the shape that was invisible to cleanup" do
      described_class.new(client: client).run

      orphans = CdefDocument.unscoped.select do |d|
        d.status == "processing" &&
          d.cdef_controls.count.zero? &&
          (d.import_metadata || {})["source_type"].nil?
      end

      expect(orphans).to be_empty
    end

    it "still imports the files that did not fail" do
      result = described_class.new(client: client).run

      expect(result.imported).to eq(1)
      expect(CdefDocument.aws_labs_sourced.count).to eq(1)
      expect(CdefDocument.aws_labs_sourced.first.name).to include("ec2")
    end

    it "reports the failure with its error class rather than only a count" do
      result = described_class.new(client: client).run

      expect(result.errors.length).to eq(1)
      expect(result.errors.first[:path]).to eq("component-definitions/s3/s3-cd.json")
      expect(result.errors.first[:error]).to include("CdefMutationService::ValidationError")
    end

    it "records a degraded-run audit event an operator can find" do
      expect { described_class.new(client: client).run }
        .to change { AuditEvent.where(action: "aws_labs_cdef_refresh_degraded").count }.by(1)

      event = AuditEvent.where(action: "aws_labs_cdef_refresh_degraded").last
      expect(event.metadata["failed_files"]).to eq(1)
      expect(event.metadata["by_error_class"]).to include("CdefMutationService")
    end

    # This is the property that makes the existing "Refresh from AWS Labs"
    # button sufficient to repair a partial run, which is the whole reason the
    # separate re-pull UI was dropped from this issue. It only holds because the
    # failed file left no row: the dedupe keys on source_url + source_sha within
    # `aws_labs_sourced`, so a leaked untagged shell was invisible to it and the
    # retry leaked another rather than healing.
    it "imports the failed file on a later refresh, once it stops failing" do
      described_class.new(client: client).run
      expect(CdefDocument.aws_labs_sourced.count).to eq(1)

      allow_any_instance_of(CdefJsonParserService).to receive(:parse).and_call_original

      described_class.new(client: client).run

      expect(CdefDocument.aws_labs_sourced.count).to eq(2)
      expect(CdefDocument.aws_labs_sourced.map(&:name).join(" ")).to include("s3")
    end
  end

  describe "a file whose FETCH fails" do
    before do
      allow(client).to receive(:list_component_definition_files).and_return([
        tree_entry(path: "component-definitions/s3/s3-cd.json",   sha: "sha-s3"),
        tree_entry(path: "component-definitions/ec2/ec2-cd.json", sha: "sha-ec2")
      ])
      allow(client).to receive(:fetch_file)
        .with(path: "component-definitions/s3/s3-cd.json")
        .and_raise(AwsLabsCdefSourceClient::RateLimitedError, "GitHub API rate limit hit")
      allow(client).to receive(:fetch_file)
        .with(path: "component-definitions/ec2/ec2-cd.json")
        .and_return(file_entry(path: "component-definitions/ec2/ec2-cd.json", sha: "sha-ec2", content: ec2))
    end

    # Before #939 only JSON::ParserError was rescued at the fetch stage, so one
    # rate-limited blob raised out of `run` and discarded the entire pass. This
    # is the site where transient failure actually happens.
    it "does not abandon the whole pass" do
      result = nil
      expect { result = described_class.new(client: client).run }.not_to raise_error

      expect(result.imported).to eq(1)
      expect(CdefDocument.aws_labs_sourced.first.name).to include("ec2")
    end

    it "reports the fetch failure with its class" do
      result = described_class.new(client: client).run

      expect(result.errors.map { |e| e[:path] }).to include("component-definitions/s3/s3-cd.json")
      expect(result.errors.map { |e| e[:error] }.join).to include("RateLimitedError")
    end

    # An unexpected error class is a bug in SPARC, not a problem with someone
    # else's repository, and must not be absorbed into a per-file error count.
    # See #968.
    it "still raises on an error class that is not a fetch failure" do
      allow(client).to receive(:fetch_file)
        .with(path: "component-definitions/s3/s3-cd.json")
        .and_raise(NoMethodError, "undefined method 'boom'")

      expect { described_class.new(client: client).run }.to raise_error(NoMethodError)
    end
  end
end
