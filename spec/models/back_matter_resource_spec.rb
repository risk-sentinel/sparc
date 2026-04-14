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
  end
end
