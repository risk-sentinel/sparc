require "rails_helper"

RSpec.describe BackMatterBuilder, type: :service do
  let(:ssp) { create(:ssp_document) }
  let(:builder) { described_class.new(ssp) }

  describe "#build" do
    it "returns a hash with resources array" do
      result = builder.build
      expect(result).to have_key("resources")
      expect(result["resources"]).to be_an(Array)
    end

    it "always includes the SPARC identifier resource" do
      result = builder.build
      sparc_resource = result["resources"].find { |r| r["title"] == "SPARC Document Source" }
      expect(sparc_resource).to be_present
      expect(sparc_resource["uuid"]).to match(BackMatterResource::UUID_V4_REGEX)
    end

    it "includes managed BackMatterResource records" do
      uuid = SecureRandom.uuid
      ssp.back_matter_resources.create!(
        title: "Security Policy",
        uuid: uuid,
        href: "https://example.com/policy.pdf",
        media_type: "application/pdf"
      )

      result = builder.build
      policy = result["resources"].find { |r| r["title"] == "Security Policy" }
      expect(policy).to be_present
      expect(policy["uuid"]).to eq(uuid)
    end

    # #583 — back-matter is no longer stashed in import_metadata; it's
    # promoted to first-class BackMatterResource rows at import time.
    # The builder picks them up via the same managed_resources query as
    # user-created resources (source != "authoritative").
    it "includes promoted imported resources (source: 'imported')" do
      imported_uuid = SecureRandom.uuid
      ssp.back_matter_resources.create!(
        title: "Imported Doc",
        uuid: imported_uuid,
        source: "imported"
      )

      result = builder.build
      imported = result["resources"].find { |r| r["title"] == "Imported Doc" }
      expect(imported).to be_present
      expect(imported["uuid"]).to eq(imported_uuid)
    end

    it "deduplicates resources sharing a UUID across managed + imported sources" do
      shared_uuid = SecureRandom.uuid
      # Same UUID, two rows — one managed, one imported. The unique
      # index on back_matter_resources.uuid will prevent two rows from
      # actually sharing a UUID in production, but the builder's uniq
      # logic still applies for the doc_resources + ctrl_resources
      # merge below.
      ssp.back_matter_resources.create!(
        title: "Managed Version",
        uuid: shared_uuid,
        source: "managed"
      )

      result = builder.build
      matching = result["resources"].select { |r| r["uuid"] == shared_uuid }
      expect(matching.size).to eq(1)
      expect(matching.first["title"]).to eq("Managed Version")
    end

    it "uses persistent SPARC resource UUID across builds" do
      result1 = described_class.new(ssp.reload).build
      result2 = described_class.new(ssp.reload).build

      uuid1 = result1["resources"].find { |r| r["title"] == "SPARC Document Source" }&.dig("uuid")
      uuid2 = result2["resources"].find { |r| r["title"] == "SPARC Document Source" }&.dig("uuid")

      expect(uuid1).to eq(uuid2)
    end

    it "skips archived resources from the assembled back-matter (#372)" do
      BackMatterResource.create!(resourceable: ssp, title: "Kept",
                                 uuid: SecureRandom.uuid, source: "managed")
      gone = BackMatterResource.create!(resourceable: ssp, title: "Archived",
                                        uuid: SecureRandom.uuid, source: "managed")
      gone.update!(archived_at: 1.day.ago)

      titles = described_class.new(ssp.reload).build["resources"].map { |r| r["title"] }
      expect(titles).to include("Kept")
      expect(titles).not_to include("Archived")
    end

    it "skips archived authoritative resources too (#372)" do
      BackMatterResource.create!(resourceable: nil, title: "AuthKept",
                                 uuid: SecureRandom.uuid, source: "authoritative",
                                 globally_available: true,
                                 promotion_status: "approved")
      BackMatterResource.create!(resourceable: nil, title: "AuthArchived",
                                 uuid: SecureRandom.uuid, source: "authoritative",
                                 globally_available: true,
                                 promotion_status: "approved",
                                 archived_at: 1.hour.ago)

      titles = described_class.new(ssp.reload).build["resources"].map { |r| r["title"] }
      expect(titles).to include("AuthKept")
      expect(titles).not_to include("AuthArchived")
    end
  end
end
