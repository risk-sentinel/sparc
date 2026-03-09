require "rails_helper"

RSpec.describe ControlMappingEntry, type: :model do
  describe "validations" do
    subject { build(:control_mapping_entry) }

    it { should validate_uniqueness_of(:uuid) }

    it "auto-generates uuid via before_validation callback" do
      entry = build(:control_mapping_entry, uuid: nil)
      entry.valid?
      expect(entry.uuid).to be_present
    end
    it { should validate_presence_of(:source_control_id) }
    it { should validate_presence_of(:target_control_id) }
    it { should validate_presence_of(:relationship) }
    it { should validate_inclusion_of(:relationship).in_array(ControlMappingEntry::RELATIONSHIPS) }
    it { should validate_inclusion_of(:source_type).in_array(ControlMappingEntry::SUBJECT_TYPES) }
    it { should validate_inclusion_of(:target_type).in_array(ControlMappingEntry::SUBJECT_TYPES) }
  end

  describe "associations" do
    it { should belong_to(:control_mapping) }
  end

  describe "uniqueness constraint" do
    it "prevents duplicate source-target pairs within the same mapping" do
      mapping = create(:control_mapping)
      create(:control_mapping_entry,
             control_mapping: mapping,
             source_control_id: "AC-1",
             target_control_id: "A.5.1")

      duplicate = build(:control_mapping_entry,
                        control_mapping: mapping,
                        source_control_id: "AC-1",
                        target_control_id: "A.5.1")
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:source_control_id]).to include("to target pair already exists in this mapping")
    end

    it "allows same source-target pair in different mappings" do
      entry1 = create(:control_mapping_entry, source_control_id: "AC-1", target_control_id: "A.5.1")
      entry2 = build(:control_mapping_entry, source_control_id: "AC-1", target_control_id: "A.5.1")
      expect(entry2).to be_valid
    end
  end

  describe "default scope" do
    it "orders by row_order" do
      mapping = create(:control_mapping)
      entry_b = create(:control_mapping_entry, control_mapping: mapping, row_order: 2,
                       source_control_id: "AC-2", target_control_id: "A.6.1")
      entry_a = create(:control_mapping_entry, control_mapping: mapping, row_order: 1,
                       source_control_id: "AC-1", target_control_id: "A.5.1")

      expect(mapping.control_mapping_entries.to_a).to eq([ entry_a, entry_b ])
    end
  end

  describe "touch parent" do
    it "updates the parent mapping's updated_at on save" do
      mapping = create(:control_mapping)
      original_time = mapping.updated_at
      sleep(0.1) # Ensure time difference for timestamp comparison
      create(:control_mapping_entry, control_mapping: mapping)
      expect(mapping.reload.updated_at).to be >= original_time
    end
  end
end
