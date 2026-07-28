# frozen_string_literal: true

require "rails_helper"

# #852 — the same control must carry the SAME identifier in every document
# SPARC exports, or nothing links up as documents flow Catalog → ATO Package.
#
# Before this, the mapping export wrote `ac-2-(1)` while the SSP, SAP, SAR and
# POA&M exports wrote `ac-2.1` for that same control. That was not a schema
# violation — `id-ref` is StringDatatype in the mapping schema, unlike
# `control-id`/`target-id` which are TokenDatatype elsewhere — and it is worse
# for being schema-clean: no validator would ever flag it, and a consumer
# joining a mapping to an SSP would simply find nothing.
RSpec.describe "control identifier consistency across documents (#852)" do
  # Every shape that genuinely occurs: NIST publication text, an OSCAL file,
  # a spreadsheet upload, and the demo seed's padded form.
  SHAPES = [ "AC-2 (1)", "ac-2.1", "AC-2(1)", "AC-02 (01)", "ac-02.01" ].freeze

  describe "one control, one identifier" do
    it "normalises every input shape to the same canonical id" do
      canonical = SHAPES.map { |shape| ControlId.canonical(shape) }.uniq

      expect(canonical).to eq([ "ac-2.1" ]),
        "expected one identifier, got #{canonical.inspect}"
    end

    it "matches a padded stored id against an unpadded selection" do
      # The concrete Catalog → ATO Package breakage: the seed stores "AC-02"
      # while control lists are written "ac-2".
      expect(ControlId).to be_same("AC-02", "ac-2")
    end
  end

  describe "the mapping export, which previously disagreed with every other document" do
    let(:mapping) { create(:control_mapping, status: "complete") }

    before do
      create(:control_mapping_entry, control_mapping: mapping,
             source_control_id: "AC-2 (1)", target_control_id: "A.5.1",
             source_type: "control", target_type: "control")
    end

    def exported_id_refs
      raw = OscalMappingExportService.new(mapping).export
      parsed = raw.is_a?(String) ? JSON.parse(raw) : raw.deep_stringify_keys

      refs = []
      walk = lambda do |node|
        case node
        when Hash  then node.each { |k, v| k.to_s == "id-ref" ? refs << v : walk.call(v) }
        when Array then node.each { |v| walk.call(v) }
        end
      end
      walk.call(parsed)
      refs
    end

    it "now writes the canonical identifier rather than ac-2-(1)" do
      expect(exported_id_refs).to include("ac-2.1")
      expect(exported_id_refs).not_to include("ac-2-(1)")
    end

    it "emits identifiers that are legal OSCAL tokens even though the field is a string" do
      # id-ref is StringDatatype, so this is not required — but writing a value
      # that would ALSO be legal as a control-id is what lets a consumer join a
      # mapping to an SSP without transforming anything.
      exported_id_refs.each do |ref|
        expect(ControlId).to be_token(ref), "#{ref.inspect} is not a legal OSCAL token"
      end
    end

    # The mapping export had a spec but never validated against the schema,
    # which is why the disagreement went unnoticed.
    it "validates against the OSCAL mapping schema" do
      raw = OscalMappingExportService.new(mapping).export
      parsed = raw.is_a?(String) ? JSON.parse(raw) : raw.deep_stringify_keys

      result = OscalSchemaValidationService.validate(:mapping, parsed)

      expect(result.valid?).to be(true), Array(result.errors).first(5).join("\n")
    end
  end

  describe "token conformance where the schema actually demands it" do
    # control-id and target-id are TokenDatatype in ssp, profile,
    # component-definition, assessment-plan, assessment-results and poam.
    # Parentheses and spaces are not in that set.
    it "produces a legal token for every input shape" do
      SHAPES.each do |shape|
        canonical = ControlId.canonical(shape)

        expect(ControlId).to be_token(canonical), "#{shape.inspect} -> #{canonical.inspect}"
        expect(canonical).not_to match(/[()\s]/)
      end
    end
  end
end
