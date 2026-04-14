require "rails_helper"

RSpec.describe ControlBackMatterLink, type: :model do
  let(:catalog) { create(:control_catalog) }
  let(:family)  { create(:control_family, control_catalog: catalog) }
  let(:control) { create(:catalog_control, control_family: family) }

  let(:resource) do
    BackMatterResource.create!(
      title: "Test Resource",
      uuid: SecureRandom.uuid,
      source: "managed",
      resourceable: catalog
    )
  end

  describe "associations" do
    it "belongs to a linkable (polymorphic)" do
      link = described_class.new(linkable: control, back_matter_resource: resource)
      expect(link.linkable).to eq(control)
      expect(link.linkable_type).to eq("CatalogControl")
    end

    it "belongs to a back_matter_resource" do
      link = described_class.new(linkable: control, back_matter_resource: resource)
      expect(link.back_matter_resource).to eq(resource)
    end
  end

  describe "validations" do
    it "prevents duplicate links" do
      described_class.create!(linkable: control, back_matter_resource: resource)
      duplicate = described_class.new(linkable: control, back_matter_resource: resource)
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:back_matter_resource_id]).to include("is already linked to this control")
    end

    it "allows same resource linked to different controls" do
      control2 = create(:catalog_control, control_family: family)
      described_class.create!(linkable: control, back_matter_resource: resource)
      link2 = described_class.new(linkable: control2, back_matter_resource: resource)
      expect(link2).to be_valid
    end

    it "allows same control linked to different resources" do
      resource2 = BackMatterResource.create!(
        title: "Another Resource",
        uuid: SecureRandom.uuid,
        source: "managed",
        resourceable: catalog
      )
      described_class.create!(linkable: control, back_matter_resource: resource)
      link2 = described_class.new(linkable: control, back_matter_resource: resource2)
      expect(link2).to be_valid
    end
  end

  describe "polymorphic control types" do
    it "works with CdefControl" do
      cdef_control = create(:cdef_control)
      link = described_class.create!(linkable: cdef_control, back_matter_resource: resource)
      expect(link.linkable_type).to eq("CdefControl")
      expect(cdef_control.back_matter_resources).to include(resource)
    end

    it "works with CatalogControl" do
      described_class.create!(linkable: control, back_matter_resource: resource)
      expect(control.back_matter_resources).to include(resource)
    end
  end

  describe "dependent destroy" do
    it "destroys links when control is destroyed" do
      described_class.create!(linkable: control, back_matter_resource: resource)
      expect { control.destroy }.to change(described_class, :count).by(-1)
    end

    it "destroys links when resource is destroyed" do
      described_class.create!(linkable: control, back_matter_resource: resource)
      expect { resource.destroy }.to change(described_class, :count).by(-1)
    end
  end

  describe "organization scoping" do
    let(:org) { create(:organization) }

    it "scopes resources by organization" do
      org_resource = BackMatterResource.create!(
        title: "Org Resource", uuid: SecureRandom.uuid,
        source: "managed", resourceable: catalog, organization: org
      )
      other_resource = BackMatterResource.create!(
        title: "Other Resource", uuid: SecureRandom.uuid,
        source: "managed", resourceable: catalog
      )

      results = BackMatterResource.org_available(org.id)
      expect(results).to include(org_resource)
      expect(results).not_to include(other_resource)
    end

    it "includes globally available resources in org scope" do
      global_resource = BackMatterResource.create!(
        title: "Global Resource", uuid: SecureRandom.uuid,
        source: "managed", resourceable: catalog, globally_available: true
      )

      results = BackMatterResource.org_available(org.id)
      expect(results).to include(global_resource)
    end
  end
end
