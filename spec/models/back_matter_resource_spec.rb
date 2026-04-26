require "rails_helper"

RSpec.describe BackMatterResource, type: :model do
  let(:ssp) { create(:ssp_document) }

  describe "validations" do
    it "requires title" do
      resource = described_class.new(resourceable: ssp, uuid: SecureRandom.uuid)
      expect(resource).not_to be_valid
      expect(resource.errors[:title]).to be_present
    end

    it "requires a valid RFC 4122 v4 UUID" do
      resource = described_class.new(
        resourceable: ssp,
        title: "Test",
        uuid: "not-a-uuid"
      )
      expect(resource).not_to be_valid
      expect(resource.errors[:uuid]).to include("must be a valid RFC 4122 v4 UUID")
    end

    it "accepts a valid UUID" do
      resource = described_class.new(
        resourceable: ssp,
        title: "Test",
        uuid: SecureRandom.uuid
      )
      expect(resource).to be_valid
    end

    it "enforces UUID uniqueness" do
      uuid = SecureRandom.uuid
      described_class.create!(resourceable: ssp, title: "First", uuid: uuid)
      duplicate = described_class.new(resourceable: ssp, title: "Second", uuid: uuid)
      expect(duplicate).not_to be_valid
    end
  end

  describe "#to_oscal_resource" do
    it "builds an OSCAL-compliant resource hash" do
      uuid = SecureRandom.uuid
      resource = described_class.new(
        uuid: uuid,
        title: "Security Policy",
        description: "Organization security policy document",
        href: "https://example.com/policy.pdf",
        media_type: "application/pdf"
      )

      oscal = resource.to_oscal_resource
      expect(oscal["uuid"]).to eq(uuid)
      expect(oscal["title"]).to eq("Security Policy")
      expect(oscal["description"]).to eq("Organization security policy document")
      expect(oscal["rlinks"]).to eq([
        { "href" => "https://example.com/policy.pdf", "media-type" => "application/pdf" }
      ])
    end

    it "excludes empty fields" do
      resource = described_class.new(uuid: SecureRandom.uuid, title: "Minimal")
      oscal = resource.to_oscal_resource
      expect(oscal).not_to have_key("description")
      expect(oscal).not_to have_key("rlinks")
    end
  end

  describe "scopes" do
    before do
      described_class.create!(resourceable: ssp, title: "Managed", uuid: SecureRandom.uuid, source: "managed")
      described_class.create!(resourceable: ssp, title: "Imported", uuid: SecureRandom.uuid, source: "imported")
    end

    it "filters by managed" do
      expect(described_class.managed.count).to eq(1)
      expect(described_class.managed.first.title).to eq("Managed")
    end

    it "filters by imported" do
      expect(described_class.imported.count).to eq(1)
      expect(described_class.imported.first.title).to eq("Imported")
    end

    it "filters authoritative resources" do
      described_class.create!(resourceable: nil, title: "Auth",
                              uuid: SecureRandom.uuid, source: "authoritative",
                              globally_available: true)
      expect(described_class.authoritative.pluck(:title)).to eq([ "Auth" ])
    end

    it "filters pending_promotion" do
      described_class.create!(resourceable: ssp, title: "Pending",
                              uuid: SecureRandom.uuid, source: "managed",
                              promotion_status: "pending_review")
      expect(described_class.pending_promotion.pluck(:title)).to eq([ "Pending" ])
    end

    it "separates active from archived" do
      described_class.create!(resourceable: ssp, title: "Old",
                              uuid: SecureRandom.uuid, source: "managed",
                              archived_at: 1.day.ago)
      expect(described_class.active.pluck(:title)).to match_array([ "Managed", "Imported" ])
      expect(described_class.archived.pluck(:title)).to eq([ "Old" ])
    end

    it "filters federated" do
      described_class.create!(resourceable: nil, title: "Fed",
                              uuid: SecureRandom.uuid, source: "authoritative",
                              federated_from_instance: "https://peer.example.gov",
                              original_uuid: SecureRandom.uuid,
                              federated_at: Time.current)
      expect(described_class.federated.pluck(:title)).to eq([ "Fed" ])
    end
  end

  describe "promotion_status validation" do
    it "accepts the four canonical states" do
      BackMatterResource::PROMOTION_STATES.each do |state|
        r = described_class.new(resourceable: ssp, title: "T", uuid: SecureRandom.uuid,
                                promotion_status: state)
        expect(r).to be_valid, "expected #{state.inspect} to be a valid promotion_status"
      end
    end

    it "rejects unknown states" do
      r = described_class.new(resourceable: ssp, title: "T", uuid: SecureRandom.uuid,
                              promotion_status: "approved_with_caveats")
      expect(r).not_to be_valid
      expect(r.errors[:promotion_status]).to be_present
    end
  end

  describe "state helpers" do
    let(:resource) do
      described_class.create!(resourceable: ssp, title: "T", uuid: SecureRandom.uuid)
    end

    it "#archived? reflects archived_at" do
      expect(resource.archived?).to eq(false)
      resource.update!(archived_at: Time.current)
      expect(resource.archived?).to eq(true)
    end

    it "#federated? reflects federated_from_instance presence" do
      expect(resource.federated?).to eq(false)
      resource.update!(federated_from_instance: "https://peer.example.gov")
      expect(resource.federated?).to eq(true)
    end

    it "#federation_dedup_uuid prefers original_uuid" do
      original = SecureRandom.uuid
      resource.update!(original_uuid: original)
      expect(resource.federation_dedup_uuid).to eq(original)
    end

    it "#federation_dedup_uuid falls back to uuid when no original_uuid" do
      expect(resource.federation_dedup_uuid).to eq(resource.uuid)
    end
  end
end
