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

  # #945 — entries were typed as free text and nothing checked them against the
  # catalogs the mapping already names.
  describe "identifiers are validated against the mapped catalogs (#945)" do
    let(:source_catalog) { create(:control_catalog, name: "NIST SP 800-53 Rev 5") }
    let(:target_catalog) { create(:control_catalog, name: "ISO 27001") }
    let(:mapping) do
      create(:control_mapping, source_catalog: source_catalog, target_catalog: target_catalog)
    end

    before do
      src_family = create(:control_family, control_catalog: source_catalog, code: "AC")
      src_family.catalog_controls.create!(control_id: "ac-1", label: "AC-1", title: "Policy")
      # #941 stores statement sub-parts as CatalogControl rows, so a `statement`
      # subject resolves through the same lookup.
      src_family.catalog_controls.create!(control_id: "ac-1a", title: "Develop policy")

      tgt_family = create(:control_family, control_catalog: target_catalog, code: "A5")
      tgt_family.catalog_controls.create!(control_id: "a.5.1", label: "A.5.1", title: "Policies")
    end

    def entry_for(source:, target:, **attrs)
      build(:control_mapping_entry, control_mapping: mapping,
            source_control_id: source, target_control_id: target, **attrs)
    end

    it "accepts identifiers present in both catalogs" do
      expect(entry_for(source: "ac-1", target: "a.5.1")).to be_valid
    end

    it "rejects a source control absent from the source catalog" do
      entry = entry_for(source: "zz-99", target: "a.5.1")

      expect(entry).not_to be_valid
      expect(entry.errors[:source_control_id].join).to include("NIST SP 800-53 Rev 5")
    end

    it "rejects a target control absent from the target catalog" do
      entry = entry_for(source: "ac-1", target: "b.9.9")

      expect(entry).not_to be_valid
      expect(entry.errors[:target_control_id].join).to include("ISO 27001")
    end

    # The exact confusion the issue names: a control that exists, but in the
    # OTHER catalog.
    it "rejects a control taken from the wrong side of the mapping" do
      expect(entry_for(source: "a.5.1", target: "ac-1")).not_to be_valid
    end

    it "reaches statement sub-parts, not only whole controls" do
      entry = entry_for(source: "ac-1a", target: "a.5.1", source_type: "statement")

      expect(entry).to be_valid
    end

    # ControlId.canonical encodes NIST numbering and would strip a KSI id's
    # zero-padding to something the KSI catalog does not contain (#911), so a
    # verbatim match has to be authoritative.
    it "accepts an identifier that only matches verbatim" do
      family = create(:control_family, control_catalog: source_catalog, code: "KSI")
      family.catalog_controls.create!(control_id: "ksi-iam-01", title: "Identity")

      expect(entry_for(source: "ksi-iam-01", target: "a.5.1")).to be_valid
    end

    it "accepts a differently-spelled identifier that canonicalises to a real control" do
      expect(entry_for(source: "AC-1", target: "a.5.1")).to be_valid
    end

    # Nothing to check against is not the same as a failed check: refusing here
    # would make a mapping unusable until someone imported the catalog.
    it "does not refuse when the catalog has no controls loaded" do
      empty = create(:control_mapping,
                     source_catalog: create(:control_catalog),
                     target_catalog: create(:control_catalog))

      expect(build(:control_mapping_entry, control_mapping: empty)).to be_valid
    end
  end

  describe "reporting entries that no longer resolve (#945)" do
    let(:source_catalog) { create(:control_catalog) }
    let(:target_catalog) { create(:control_catalog) }
    let(:mapping) do
      create(:control_mapping, source_catalog: source_catalog, target_catalog: target_catalog)
    end

    it "reports which side is unresolved without rewriting it" do
      entry = create(:control_mapping_entry, control_mapping: mapping,
                     source_control_id: "ac-1", target_control_id: "a.5.1")

      # Load the catalogs AFTER the entry exists, so only the target resolves.
      create(:control_family, control_catalog: target_catalog, code: "A5")
        .catalog_controls.create!(control_id: "a.5.1", title: "Policies")
      create(:control_family, control_catalog: source_catalog, code: "ZZ")
        .catalog_controls.create!(control_id: "zz-1", title: "Something else")

      expect(entry.reload.resolved?).to be false
      expect(entry.unresolved_sides).to eq([ "source" ])
      expect(entry.source_control_id).to eq("ac-1")
    end

    # A rule added later must not freeze a record it was not applied to.
    it "still allows an unresolvable entry's remarks to be corrected" do
      entry = create(:control_mapping_entry, control_mapping: mapping,
                     source_control_id: "ac-1", target_control_id: "a.5.1")
      create(:control_family, control_catalog: source_catalog, code: "ZZ")
        .catalog_controls.create!(control_id: "zz-1", title: "Something else")

      expect(entry.reload.update(remarks: "corrected note")).to be true
    end
  end
end
