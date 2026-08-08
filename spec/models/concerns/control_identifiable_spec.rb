# frozen_string_literal: true

require "rails_helper"

# #911 layer 1 — control identifiers are canonicalised on write.
#
# Before this, an identifier was stored exactly as typed. Catalogs store the
# canonical form while SPARC *displays* the padded one, so a literal comparison
# against a stored value matched nothing: SarControl and EvidenceControlLink
# resolved 0% verbatim and 100% after canonicalisation.
RSpec.describe ControlIdentifiable, type: :model do
  # Columns whose value is a NIST control reference by construction, and the
  # column(s) each uses. Listed explicitly so adding a control-bearing model
  # without a deliberate decision fails here rather than silently reintroducing
  # the defect.
  CANONICALISING_MODELS = {
    SspControl => :control_id,
    SarControl => :control_id,
    SapControl => :control_id,
    ProfileControl => :control_id,
    # #912 — canonicalised again now that `control_id` holds ONLY a NIST
    # reference; the source identifier moved to its own column.
    CdefControl => :control_id,
    EvidenceControlLink => :control_id,
    # TARGET only — the source side of a mapping is the non-NIST vocabulary.
    ControlMappingEntry => :target_control_id
  }.freeze

  # Columns that carry a control identifier and are deliberately left alone,
  # with the reason. `ControlId.canonical` encodes NIST numbering and case, so
  # it corrupts every other vocabulary: FedRAMP KSI's zero-padding is
  # significant (`ksi-auth-01`, not `ksi-auth-1`) and AWS Security Hub ids are
  # case-bearing (`IAM.3`, not `iam.3`).
  MIXED_VOCABULARY_COLUMNS = {
    # #912 — the source identifier, whatever framework it came from. Preserved
    # byte-for-byte: an AWS Security Hub id is case-bearing (`IAM.3`) and a
    # FedRAMP KSI id's zero-padding is significant (`ksi-auth-01`).
    CdefControl => :source_control_id,
    ControlMappingEntry => :source_control_id  # whatever framework maps INTO NIST
  }.freeze

  it "is included by every model with a NIST-by-construction identifier" do
    CANONICALISING_MODELS.each_key do |klass|
      expect(klass.ancestors).to include(described_class),
        "#{klass} carries a NIST control identifier but does not canonicalise it"
    end
  end

  # The regression this guards: canonicalising a mixed-vocabulary column mutated
  # `IAM.3` to `iam.3` and `ksi-iam-01` to `ksi-iam-1`, breaking the SecHub
  # enrichment lookups and emptying the KSI mappings endpoint.
  it "leaves mixed-vocabulary columns untouched" do
    MIXED_VOCABULARY_COLUMNS.each do |klass, column|
      declared = klass.try(:canonicalised_control_id_attributes) || []

      expect(declared).not_to include(column),
        "#{klass}##{column} holds non-NIST identifiers and must persist unmolested"
    end
  end

  it "preserves a FedRAMP KSI identifier exactly as the catalog stores it" do
    entry = build(:control_mapping_entry, source_control_id: "ksi-iam-01", target_control_id: "AC-02")
    entry.validate

    expect(entry.source_control_id).to eq("ksi-iam-01"), "KSI zero-padding is significant"
    expect(entry.target_control_id).to eq("ac-2")
  end

  # #912 — the identifier is still never rewritten; it now lives in
  # `source_control_id`. `control_id` alongside it is canonicalised, because it
  # holds a NIST reference rather than a Security Hub one.
  it "preserves an AWS Security Hub identifier through a bulk import" do
    document = create(:cdef_document)
    record   = CdefControl.new(cdef_document_id: document.id,
                               source_control_id: "IAM.3", source_vocabulary: "aws_security_hub",
                               control_id: "AC-02", title: "x", uuid: SecureRandom.uuid)
    # A direct `.import` runs no callbacks — the bulk path applies the model's
    # own declaration, so mirror that here rather than expecting magic.
    CdefControl.canonicalise_control_ids!(record)
    CdefControl.import([ record ], validate: false)

    stored = CdefControl.where(cdef_document_id: document.id).first
    expect(stored.source_control_id).to eq("IAM.3"), "the source identifier must never be rewritten"
    expect(stored.control_id).to eq("ac-2"), "the NIST reference is canonicalised"
  end

  describe "canonicalisation on write" do
    it "stores the canonical form given the padded form SPARC displays" do
      link = build(:evidence_control_link, control_id: "AC-02")
      link.validate

      expect(link.control_id).to eq("ac-2")
    end

    it "stores the canonical form given the NIST publication form" do
      link = build(:evidence_control_link, control_id: "AC-2 (1)")
      link.validate

      expect(link.control_id).to eq("ac-2.1")
    end

    it "leaves an already-canonical identifier untouched" do
      link = build(:evidence_control_link, control_id: "ac-2.1")
      link.validate

      expect(link.control_id).to eq("ac-2.1")
    end

    it "is idempotent across repeated saves" do
      link = create(:evidence_control_link, control_id: "AC-02")
      first = link.reload.control_id
      link.save!

      expect(link.reload.control_id).to eq(first)
    end

    it "leaves a blank identifier alone" do
      # Shared-responsibility rows in an SSP legitimately carry no control id.
      control = build(:ssp_control, control_id: nil)
      control.validate

      expect(control.control_id).to be_nil
    end

    # `ControlId.canonical` returns "unknown" for input it cannot parse.
    # Storing that would replace the identifier with a word and destroy the
    # only record of what the author meant.
    it "keeps an unparseable identifier rather than storing 'unknown'" do
      control = build(:ssp_control, control_id: "???")
      control.validate

      expect(control.control_id).not_to eq("unknown")
    end

    it "canonicalises the NIST side of a mapping entry and leaves the source side alone" do
      entry = build(:control_mapping_entry, source_control_id: "AC-02", target_control_id: "AC-2 (1)")
      entry.validate

      expect(entry.target_control_id).to eq("ac-2.1")
      expect(entry.source_control_id).to eq("AC-02")
    end
  end

  # #911 — the callback covers interactive writes and misses bulk import, which
  # creates almost every row. `canonicalise_control_ids!` is how a callback-free
  # writer reaches the same transform; the declaration is the single source both
  # read, so they cannot drift.
  describe "the declaration bulk writers read" do
    it "records the columns each model canonicalises" do
      CANONICALISING_MODELS.each do |klass, attributes|
        expect(klass.canonicalised_control_id_attributes)
          .to match_array(Array(attributes)),
              "#{klass} declares #{klass.canonicalised_control_id_attributes.inspect}"
      end
    end

    it "applies the same transform to an unsaved record, and only to declared columns" do
      entry = ControlMappingEntry.new(source_control_id: "AC-02", target_control_id: "AC-2 (1)")
      ControlMappingEntry.canonicalise_control_ids!(entry)

      expect(entry.target_control_id).to eq("ac-2.1")
      expect(entry.source_control_id).to eq("AC-02"), "the source vocabulary is never rewritten"
    end

    it "agrees with the callback it mirrors" do
      bulk = SspControl.new(control_id: "AC-2 (1)")
      SspControl.canonicalise_control_ids!(bulk)

      callback = SspControl.new(control_id: "AC-2 (1)")
      callback.validate

      expect(bulk.control_id).to eq(callback.control_id)
    end

    it "does not reach models that never declared a column" do
      expect(SspControlField).not_to respond_to(:canonicalise_control_ids!)
    end
  end

  # The bug this replaced: ApplicationController#normalize_ctrl_id was a private
  # reimplementation of ControlId.canonical that had drifted and was wrong for
  # the most common human spelling of an enhancement, and corrupted fixed-width
  # external identifiers.
  describe "the identifier forms the old private normaliser got wrong" do
    {
      "AC-2 (1)"        => "ac-2.1",       # was "ac-2-.1"
      "AC-2  (1)"       => "ac-2.1",       # was "ac-2-.1"
      "ac-19.4.(b).(1)" => "ac-19.4.b.1",  # was "ac-19.4..b..1"
      "CCI-000213"      => "cci-000213"    # was "cci-213" — fixed-width, must not be stripped
    }.each do |input, expected|
      it "canonicalises #{input.inspect} to #{expected.inspect}" do
        expect(ControlId.canonical(input)).to eq(expected)
      end
    end
  end
end
