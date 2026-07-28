# frozen_string_literal: true

require "rails_helper"

# #852 — data evidence that EVERY document SPARC publishes emits control
# identifiers that are legal OSCAL.
#
# `control-id` and `target-id` are **TokenDatatype** in the ssp, profile,
# component-definition, assessment-plan, assessment-results and poam schemas:
#
#     ^(\p{L}|_)(\p{L}|\p{N}|[.\-_])*$
#
# Parentheses and spaces are not in that set. The JSON schemas do not all
# enforce the pattern (`id-ref` in the mapping schema is StringDatatype, and a
# document can validate while carrying an identifier no other document will
# match), so schema validity alone is NOT sufficient evidence — which is
# exactly how the mapping export shipped writing `ac-2-(1)` unnoticed.
#
# So this asserts BOTH, per export: every emitted identifier is a legal token,
# AND the document validates. And it does it with deliberately hostile inputs
# rather than tidy ones, because tidy inputs prove nothing about a normalizer.
RSpec.describe "published documents emit valid OSCAL control ids (#852)" do
  # Every shape a control id genuinely arrives in: NIST publication text, a
  # spreadsheet upload, an OSCAL file, and the demo seed's padded form.
  HOSTILE_IDS = [ "AC-2 (1)", "AC-02", "ac-2.1", "AC-2(1)", "  au-6  ", "SI-4 (12)" ].freeze

  OSCAL_TOKEN = /\A(\p{L}|_)(\p{L}|\p{N}|[.\-_])*\z/
  ID_FIELDS   = %w[control-id target-id id-ref].freeze

  # Pull every control identifier out of an exported document, wherever it sits.
  def control_ids_in(payload)
    parsed = payload.is_a?(String) ? JSON.parse(payload) : payload.deep_stringify_keys
    found = []
    walk = lambda do |node|
      case node
      when Hash
        node.each { |k, v| ID_FIELDS.include?(k.to_s) && v.is_a?(String) ? found << v : walk.call(v) }
      when Array
        node.each { |v| walk.call(v) }
      end
    end
    walk.call(parsed)
    found
  end

  def expect_all_tokens(ids, label:)
    expect(ids).not_to be_empty, "#{label}: no control identifiers found — the assertion would be vacuous"

    offenders = ids.reject { |id| id.match?(OSCAL_TOKEN) }
    expect(offenders).to be_empty,
      "#{label}: emitted identifiers that are NOT legal OSCAL tokens: #{offenders.uniq.inspect}"
  end

  let(:boundary) { create(:authorization_boundary) }

  describe "SSP export" do
    it "emits only legal tokens, and validates" do
      ssp = create(:ssp_document, authorization_boundary: boundary)
      HOSTILE_IDS.each { |id| create(:ssp_control, ssp_document: ssp, control_id: id) }

      json = OscalSspExportService.new(ssp).export
      ids = control_ids_in(json)

      expect_all_tokens(ids, label: "SSP")
      expect(OscalSchemaValidationService.validate_json(:ssp, json).valid?).to be(true)
    end
  end

  describe "SAR export" do
    it "emits only legal tokens, and validates" do
      sar = create(:sar_document, authorization_boundary: boundary)
      HOSTILE_IDS.each { |id| create(:sar_control, sar_document: sar, control_id: id) }

      json = OscalSarExportService.new(sar).export
      ids = control_ids_in(json)

      expect_all_tokens(ids, label: "SAR")
      expect(OscalSchemaValidationService.validate_json(:assessment_results, json).valid?).to be(true)
    end
  end

  describe "SAP export" do
    it "emits only legal tokens, and validates" do
      sap = create(:sap_document, authorization_boundary: boundary)
      HOSTILE_IDS.each { |id| create(:sap_control, sap_document: sap, control_id: id) }

      json = OscalAssessmentPlanExportService.new(sap).export
      ids = control_ids_in(json)

      expect_all_tokens(ids, label: "SAP")
      expect(OscalSchemaValidationService.validate_json(:assessment_plan, json).valid?).to be(true)
    end
  end

  describe "component definition export" do
    it "emits only legal tokens, and validates" do
      cdef = create(:cdef_document)
      HOSTILE_IDS.each { |id| create(:cdef_control, cdef_document: cdef, control_id: id) }

      json = OscalComponentDefinitionExportService.new(cdef).export
      ids = control_ids_in(json)

      expect_all_tokens(ids, label: "component-definition")
      expect(OscalSchemaValidationService.validate_json(:component_definition, json).valid?).to be(true)
    end
  end

  describe "control mapping export" do
    it "emits only legal tokens, and validates" do
      mapping = create(:control_mapping, status: "complete")
      HOSTILE_IDS.each do |id|
        create(:control_mapping_entry, control_mapping: mapping,
               source_control_id: id, target_control_id: "A.5.1",
               source_type: "control", target_type: "control")
      end

      raw = OscalMappingExportService.new(mapping).export
      ids = control_ids_in(raw)

      # id-ref is StringDatatype, so this is stricter than the schema demands —
      # deliberately. Writing a value that would ALSO be legal as a control-id
      # is what lets a consumer join a mapping to an SSP without transforming.
      expect_all_tokens(ids, label: "mapping")

      parsed = raw.is_a?(String) ? JSON.parse(raw) : raw.deep_stringify_keys
      expect(OscalSchemaValidationService.validate(:mapping, parsed).valid?).to be(true)
    end
  end

  # The evidence that matters most for Catalog -> ATO Package: it is not enough
  # that each document is individually valid; the SAME control must carry the
  # SAME identifier across all of them, or nothing joins up.
  describe "cross-document agreement" do
    it "gives one control one identifier in every document that publishes it" do
      shape = "AC-2 (1)"

      ssp = create(:ssp_document, authorization_boundary: boundary)
      create(:ssp_control, ssp_document: ssp, control_id: shape)

      sar = create(:sar_document, authorization_boundary: boundary)
      create(:sar_control, sar_document: sar, control_id: shape)

      sap = create(:sap_document, authorization_boundary: boundary)
      create(:sap_control, sap_document: sap, control_id: shape)

      cdef = create(:cdef_document)
      create(:cdef_control, cdef_document: cdef, control_id: shape)

      mapping = create(:control_mapping, status: "complete")
      create(:control_mapping_entry, control_mapping: mapping,
             source_control_id: shape, target_control_id: "A.5.1",
             source_type: "control", target_type: "control")

      emitted = {
        ssp:     control_ids_in(OscalSspExportService.new(ssp).export),
        sar:     control_ids_in(OscalSarExportService.new(sar).export),
        sap:     control_ids_in(OscalAssessmentPlanExportService.new(sap).export),
        cdef:    control_ids_in(OscalComponentDefinitionExportService.new(cdef).export),
        mapping: control_ids_in(OscalMappingExportService.new(mapping).export)
      }

      expected = ControlId.canonical(shape) # "ac-2.1"

      emitted.each do |document, ids|
        expect(ids).to include(expected),
          "#{document} published #{ids.uniq.inspect}, expected to include #{expected.inspect}"
      end
    end

    it "agrees regardless of which shape each document stored" do
      # The realistic case: the seed stores padded, an OSCAL import stores
      # canonical, a spreadsheet stores parenthesised. All name one control.
      ssp = create(:ssp_document, authorization_boundary: boundary)
      create(:ssp_control, ssp_document: ssp, control_id: "AC-02")

      sar = create(:sar_document, authorization_boundary: boundary)
      create(:sar_control, sar_document: sar, control_id: "AC-2")

      cdef = create(:cdef_document)
      create(:cdef_control, cdef_document: cdef, control_id: "ac-2")

      ssp_ids  = control_ids_in(OscalSspExportService.new(ssp).export)
      sar_ids  = control_ids_in(OscalSarExportService.new(sar).export)
      cdef_ids = control_ids_in(OscalComponentDefinitionExportService.new(cdef).export)

      expect(ssp_ids).to include("ac-2")
      expect(sar_ids).to include("ac-2")
      expect(cdef_ids).to include("ac-2")
    end
  end
end
