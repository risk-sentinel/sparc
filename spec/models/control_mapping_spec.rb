require "rails_helper"

RSpec.describe ControlMapping, type: :model do
  describe "validations" do
    subject { build(:control_mapping) }

    it { should validate_presence_of(:name) }
    it { should validate_uniqueness_of(:uuid) }

    it "auto-generates uuid via before_validation callback" do
      mapping = build(:control_mapping, uuid: nil)
      mapping.valid?
      expect(mapping.uuid).to be_present
    end
    it { should validate_inclusion_of(:status).in_array(ControlMapping::STATUSES) }
    it { should validate_inclusion_of(:method_type).in_array(ControlMapping::METHODS) }
    it { should validate_inclusion_of(:matching_rationale).in_array(ControlMapping::RATIONALES) }
  end

  describe "associations" do
    it { should belong_to(:source_catalog).class_name("ControlCatalog") }
    it { should belong_to(:target_catalog).class_name("ControlCatalog") }
    it { should have_many(:control_mapping_entries).dependent(:destroy) }
  end

  describe "scopes" do
    let!(:draft_mapping) { create(:control_mapping, status: "draft") }
    let!(:complete_mapping) { create(:control_mapping, :complete) }

    it ".published returns only complete mappings" do
      expect(ControlMapping.published).to contain_exactly(complete_mapping)
    end

    it ".sorted orders by updated_at desc" do
      draft_mapping.touch
      expect(ControlMapping.sorted.first).to eq(draft_mapping)
    end
  end

  describe "#published?" do
    it "returns true when status is complete" do
      mapping = build(:control_mapping, status: "complete")
      expect(mapping.published?).to be true
    end

    it "returns false when status is draft" do
      mapping = build(:control_mapping, status: "draft")
      expect(mapping.published?).to be false
    end
  end

  describe "#entries_count" do
    it "returns the number of mapping entries" do
      mapping = create(:control_mapping)
      create_list(:control_mapping_entry, 3, control_mapping: mapping)
      expect(mapping.entries_count).to eq(3)
    end
  end

  describe "#oscal_document_version" do
    it "returns the mapping_version" do
      mapping = build(:control_mapping, mapping_version: "2.0.0")
      expect(mapping.oscal_document_version).to eq("2.0.0")
    end
  end

  describe "uuid generation" do
    it "auto-generates a uuid on create" do
      mapping = create(:control_mapping)
      expect(mapping.uuid).to be_present
      expect(mapping.uuid).to match(/\A[0-9a-f-]{36}\z/)
    end
  end
end
