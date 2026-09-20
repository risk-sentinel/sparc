# frozen_string_literal: true

require "rails_helper"

# Issue #1103 — regions on the upload path.
#
# AWS publishes regions as their own component definition (COMPONENTS.md:
# `aws_regions.oscal.json` "contains one OSCAL component for each AWS Region"),
# and a service references region availability "via `provided-by` links to the
# AWS Regions component definition". The dependency crosses files by design.
#
# CdefComponentIndexer resolves those links against regions ALREADY indexed, so
# whichever file arrives first cannot see the other. AwsLabsCdefImportService
# had an ordering pass and a repair pass for its own path; neither was reachable
# from an upload, and the upload path enqueues a job per file in browser order,
# so a service uploaded first kept empty region_ids permanently.
RSpec.describe CdefRegionReindexService do
  subject(:service) { described_class.new }

  let(:regions_path) { Rails.root.join("spec/fixtures/files/components/aws_labs/regions-cd.json") }
  let(:service_path) { Rails.root.join("spec/fixtures/files/components/aws_labs/kinesis-cd.json") }

  let(:regions_oscal) { JSON.parse(File.read(regions_path)) }
  let(:service_oscal) { JSON.parse(File.read(service_path)) }

  # A document as the upload path leaves it: parsed, indexed, attachment kept
  # (#680 retains source blobs by default) so the source resolves from disk.
  def upload!(name, path)
    document = create(:cdef_document, name: name, file_type: "json", status: "completed")
    document.file.attach(io: File.open(path), filename: File.basename(path),
                         content_type: "application/json")
    CdefComponentIndexer.new(document, JSON.parse(File.read(path))).index!
    document
  end

  describe "#defines_regions?" do
    it "recognises a regions component definition" do
      expect(service.defines_regions?(regions_oscal)).to be(true)
    end

    it "does not mistake a service definition for one" do
      expect(service.defines_regions?(service_oscal)).to be(false)
    end
  end

  # The reported ordering. This is the one that was permanently broken.
  describe "direction A — a regions CDEF arrives after the services" do
    it "re-indexes a service that had resolved no regions" do
      svc = upload!("Kinesis", service_path)
      expect(svc.cdef_components.pluck(:region_ids).flatten).to be_empty

      regions = upload!("aws_regions", regions_path)
      service.call(regions, content: regions_oscal)

      expect(svc.reload.cdef_components.pluck(:region_ids).flatten).to include("us-east-1")
    end

    it "leaves a service that already resolved its regions alone" do
      upload!("aws_regions", regions_path)
      svc = upload!("Kinesis", service_path)
      expect(svc.cdef_components.pluck(:region_ids).flatten).to include("us-east-1")
      before = svc.cdef_components.pluck(:content_hash).sort

      regions2 = upload!("aws_regions_again", regions_path)
      service.call(regions2, content: regions_oscal)

      expect(svc.reload.cdef_components.pluck(:content_hash).sort).to eq(before)
    end

    # AWS Labs documents are ordered by `regions_first` and repaired by their own
    # importer. Re-indexing them here would make CdefSourceResolver re-FETCH each
    # one over the network from inside an upload job.
    it "does not reach into AWS Labs-sourced documents" do
      svc = upload!("Kinesis", service_path)
      svc.update_column(:import_metadata, { "source_type" => "aws_labs" })

      regions = upload!("aws_regions", regions_path)
      expect(CdefSourceResolver).not_to receive(:new)

      service.call(regions, content: regions_oscal)
    end
  end

  describe "direction B — a service CDEF arrives after the regions" do
    it "resolves its regions on import" do
      upload!("aws_regions", regions_path)
      svc = upload!("Kinesis", service_path)

      expect(service.call(svc, content: service_oscal)).to eq(0)
      expect(svc.reload.cdef_components.pluck(:region_ids).flatten).to include("us-east-1")
    end

    # Indexed too early by a caller that did not have the regions yet, then
    # repaired once they exist.
    it "repairs a service indexed before any regions existed" do
      svc = upload!("Kinesis", service_path)
      expect(svc.cdef_components.pluck(:region_ids).flatten).to be_empty

      upload!("aws_regions", regions_path)
      expect(service.call(svc, content: service_oscal)).to eq(1)

      expect(svc.reload.cdef_components.pluck(:region_ids).flatten).to include("us-east-1")
    end

    it "is a no-op when no regions exist at all" do
      svc = upload!("Kinesis", service_path)

      expect(service.call(svc, content: service_oscal)).to eq(0)
      expect(svc.reload.cdef_components.pluck(:region_ids).flatten).to be_empty
    end
  end

  # The import paths hand over the RAW JSON string they fetched; the parser
  # hands over an already-parsed Hash. Passing the string straight through
  # reached `.dig` on a String and took three AWS Labs examples down with it.
  describe "content shapes" do
    it "accepts raw JSON as well as a parsed Hash" do
      svc = upload!("Kinesis", service_path)
      upload!("aws_regions", regions_path)
      svc.cdef_components.update_all(region_ids: [])

      expect(service.call(svc, content: File.read(service_path))).to eq(1)
      expect(svc.reload.cdef_components.pluck(:region_ids).flatten).to include("us-east-1")
    end

    it "declines unparseable content instead of raising" do
      svc = upload!("Kinesis", service_path)

      expect(service.call(svc, content: "{not json")).to eq(0)
    end
  end

  describe "robustness" do
    it "returns zero when the source cannot be resolved" do
      document = create(:cdef_document, file_type: "json", status: "completed")

      expect(service.call(document)).to eq(0)
    end

    it "records a degradation rather than raising when indexing fails" do
      upload!("aws_regions", regions_path)
      svc = upload!("Kinesis", service_path)
      svc.cdef_components.update_all(region_ids: [])
      allow_any_instance_of(CdefComponentIndexer)
        .to receive(:index!).and_raise(ActiveRecord::StatementInvalid, "boom")

      expect { service.call(svc, content: service_oscal) }.not_to raise_error
      expect(svc.reload).to be_component_index_degraded
    end
  end

  # Running it twice must converge — the indexer replaces a document's rows
  # rather than merging, which is what makes the repair safe to re-run.
  describe "idempotency" do
    it "produces the same regions when run twice" do
      svc = upload!("Kinesis", service_path)
      regions = upload!("aws_regions", regions_path)

      service.call(regions, content: regions_oscal)
      first = svc.reload.cdef_components.pluck(:region_ids).flatten.sort

      service.call(regions, content: regions_oscal)

      expect(svc.reload.cdef_components.pluck(:region_ids).flatten.sort).to eq(first)
    end
  end
end
