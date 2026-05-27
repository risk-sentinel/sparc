# frozen_string_literal: true

require "rails_helper"

# v1.8.2 — covers the cross-doc UUID collision regression that
# crashed v1.8.1 deploys mid-migration. Two docs that legitimately
# reference the same OSCAL back-matter UUID must both promote
# successfully (fresh BMR uuid, source uuid stashed in resource_data).
RSpec.describe BackMatterPromotable do
  # Anonymous service class that includes the concern — lets us
  # exercise the private method without booting a real parser.
  let(:host_class) do
    Class.new do
      include BackMatterPromotable
      attr_accessor :document
      def initialize(doc)
        @document = doc
      end
      def promote(resources)
        promote_back_matter_resources(resources)
      end
    end
  end

  let(:cdef_a) { create(:cdef_document, name: "Doc A") }
  let(:cdef_b) { create(:cdef_document, name: "Doc B") }
  let(:shared_source_uuid) { "11111111-2222-4333-8444-555555555555" }
  let(:back_matter_resource) do
    {
      "uuid"        => shared_source_uuid,
      "title"       => "NIST SP 800-53 Rev 5",
      "description" => "Shared catalog reference",
      "rlinks"      => [ { "href" => "https://csrc.nist.gov/sp800-53r5", "media-type" => "application/json" } ]
    }
  end

  describe "v1.8.2 — cross-doc UUID collision (regression)" do
    it "promotes the same source uuid to TWO docs without crashing on the global BMR.uuid unique index" do
      host_class.new(cdef_a).promote([ back_matter_resource ])
      expect {
        host_class.new(cdef_b).promote([ back_matter_resource ])
      }.not_to raise_error

      expect(cdef_a.back_matter_resources.count).to eq(1)
      expect(cdef_b.back_matter_resources.count).to eq(1)
    end

    it "gives each doc its own fresh BMR.uuid (NOT the source uuid)" do
      host_class.new(cdef_a).promote([ back_matter_resource ])
      host_class.new(cdef_b).promote([ back_matter_resource ])

      bmr_a = cdef_a.back_matter_resources.first
      bmr_b = cdef_b.back_matter_resources.first

      expect(bmr_a.uuid).not_to eq(shared_source_uuid)
      expect(bmr_b.uuid).not_to eq(shared_source_uuid)
      expect(bmr_a.uuid).not_to eq(bmr_b.uuid)
    end

    it "preserves the source uuid in resource_data['source_uuid'] on each promoted BMR" do
      host_class.new(cdef_a).promote([ back_matter_resource ])
      host_class.new(cdef_b).promote([ back_matter_resource ])

      expect(cdef_a.back_matter_resources.first.resource_data["source_uuid"]).to eq(shared_source_uuid)
      expect(cdef_b.back_matter_resources.first.resource_data["source_uuid"]).to eq(shared_source_uuid)
    end
  end

  describe "per-doc idempotency on re-run" do
    it "skips re-promotion when the source uuid was already promoted (new resource_data path)" do
      host_class.new(cdef_a).promote([ back_matter_resource ])
      expect {
        host_class.new(cdef_a).promote([ back_matter_resource ])
      }.not_to change { cdef_a.back_matter_resources.count }
    end

    it "skips re-promotion when a LEGACY (pre-v1.8.2) BMR exists with uuid == source uuid" do
      # Simulate a v1.8.0 import that stored source uuid as BMR.uuid
      # directly. v1.8.2 must recognize this as already-promoted.
      cdef_a.back_matter_resources.create!(
        uuid:   shared_source_uuid,
        title:  "Pre-v1.8.2 imported",
        source: "imported",
        rel:    "reference"
      )
      expect {
        host_class.new(cdef_a).promote([ back_matter_resource ])
      }.not_to change { cdef_a.back_matter_resources.count }
    end
  end

  describe "resume from a partially-failed v1.8.1 migration attempt" do
    it "continues from where the partial run left off without creating duplicates" do
      r1 = back_matter_resource
      r2 = back_matter_resource.merge("uuid" => "22222222-2222-4333-8444-666666666666",
                                       "title" => "FIPS 200")

      # Simulate the first half of a partial v1.8.0 import that
      # stored source uuid as BMR.uuid before the migration crashed.
      cdef_a.back_matter_resources.create!(
        uuid:   r1["uuid"], title: r1["title"], source: "imported", rel: "reference"
      )
      # Stash still contains both — migration didn't get to clear it.
      cdef_a.update!(import_metadata: { "back_matter" => [ r1, r2 ] })

      host_class.new(cdef_a).promote(cdef_a.import_metadata["back_matter"])

      # Exactly 2 BMRs on this doc: the pre-existing one (r1) and the
      # new fresh-uuid one (r2). No duplicate for r1.
      expect(cdef_a.back_matter_resources.count).to eq(2)
      legacy_bmr = cdef_a.back_matter_resources.find_by(uuid: r1["uuid"])
      expect(legacy_bmr).to be_present
      new_bmr = cdef_a.back_matter_resources.where.not(uuid: r1["uuid"]).first
      expect(new_bmr.resource_data["source_uuid"]).to eq(r2["uuid"])
    end
  end

  describe "skip behavior unchanged" do
    it "still skips entries without a v4 uuid" do
      bad_resource = back_matter_resource.merge("uuid" => "not-a-uuid")
      expect {
        host_class.new(cdef_a).promote([ bad_resource ])
      }.not_to change { cdef_a.back_matter_resources.count }
    end

    it "still no-ops on nil/empty input" do
      expect { host_class.new(cdef_a).promote(nil) }.not_to raise_error
      expect { host_class.new(cdef_a).promote([]) }.not_to raise_error
    end
  end

  describe "audit row emission (preserved from #581)" do
    it "emits one BackMatterResourceChange create row per promoted BMR" do
      expect {
        host_class.new(cdef_a).promote([ back_matter_resource ])
      }.to change { BackMatterResourceChange.where(change_type: "create").count }.by(1)
    end
  end
end
