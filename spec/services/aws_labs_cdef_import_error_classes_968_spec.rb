# frozen_string_literal: true

require "rails_helper"

# #968 hazard 1 — a failure reduced to a count.
#
# The per-candidate loop used a bare `rescue => e`, so a NoMethodError in SPARC's
# own code landed in the same `errors` array as an upstream schema gap. The run
# then returned `errors=39` for both, and an operator reading that number could
# not tell "someone else's content is wrong" from "our code is broken" — which is
# the difference between filing upstream and fixing a bug.
#
# Both directions are asserted, because the fix is only meaningful if the
# expected classes are STILL counted. A change that made everything raise would
# pass a one-sided test and break every real import.
RSpec.describe AwsLabsCdefImportService, "rescued error classes (#968)" do
  let(:fixture_dir) { Rails.root.join("spec/fixtures/files/components/aws_labs") }
  let(:s3)  { fixture_dir.join("s3-cd-v1.0.0.json").read }
  let(:client) { instance_double(AwsLabsCdefSourceClient) }

  before do
    allow(SparcConfig).to receive(:aws_labs_cdef_enabled?).and_return(true)
    allow(SparcConfig).to receive(:aws_labs_cdef_repo).and_return("awslabs/oscal-content-for-aws-services")
    allow(SparcConfig).to receive(:aws_labs_cdef_branch).and_return("main")
    allow(client).to receive(:current_commit_sha).and_return("commit-sha-aaaa")
    allow(client).to receive(:list_component_definition_files).and_return([
      { "type" => "blob", "path" => "component-definitions/s3/s3-cd.json", "sha" => "sha-s3" }
    ])
    allow(client).to receive(:fetch_file).and_return(
      path: "component-definitions/s3/s3-cd.json",
      sha: "sha-s3",
      html_url: "https://github.com/awslabs/oscal-content-for-aws-services/blob/main/s3-cd.json",
      content: s3
    )
  end

  def run_with_parse_raising(error_class, message)
    allow_any_instance_of(CdefJsonParserService).to receive(:parse)
      .and_raise(error_class, message)
    described_class.new(client: client).run
  end

  context "a problem with someone else's content" do
    it "is counted, not raised — the run still reports on the rest" do
      result = nil
      expect { result = run_with_parse_raising(CdefMutationService::ValidationError, "bad OSCAL") }
        .not_to raise_error

      expect(result.errors.length).to eq(1)
      expect(result.errors.first[:error]).to include("CdefMutationService::ValidationError")
    end

    it "counts a DocumentParseError the same way" do
      result = nil
      expect { result = run_with_parse_raising(DocumentParseError, "no component-definition") }
        .not_to raise_error

      expect(result.errors.length).to eq(1)
    end
  end

  context "a bug in SPARC" do
    # THE POINT. Before #968 this was absorbed into `errors` and reported as
    # though awslabs had shipped a bad file.
    it "propagates instead of being absorbed into the error count" do
      expect { run_with_parse_raising(NoMethodError, "undefined method 'oops' for nil") }
        .to raise_error(NoMethodError, /oops/)
    end

    it "propagates a TypeError rather than counting it" do
      expect { run_with_parse_raising(TypeError, "no implicit conversion") }
        .to raise_error(TypeError)
    end
  end
end
