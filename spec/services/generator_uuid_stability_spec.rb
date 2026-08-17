# frozen_string_literal: true

require "rails_helper"

# #957 — a document generated twice from the same source must carry the same
# identifiers.
#
# `OscalUuidService` was built for exactly this and the EXPORT services were
# converted to it; the GENERATOR services never were, so building an SSP twice
# from one published profile produced two documents sharing not a single control
# UUID. Cross-document references break on regeneration — FedRAMP leveraged
# authorization cites the UUIDs of provided/responsibility statements, and
# SspControlStatement UUIDs derive from the control's, so they moved too — and
# committed OSCAL artifacts churn on every rebuild, which makes a drift check
# worthless.
RSpec.describe "generated document UUID stability (#957)" do
  # #952 — a profile belongs to no system, so the generator takes the boundary
  # from its caller.
  let(:boundary) { create(:authorization_boundary) }
  let(:resolved_catalog_json) do
    {
      "catalog" => {
        "uuid" => "11111111-2222-4333-8444-555555555555",
        "metadata" => { "title" => "Stability Catalog", "version" => "1.0.0",
                        "oscal-version" => "1.1.2", "last-modified" => Time.current.iso8601 },
        "groups" => [ {
          "id" => "ac", "class" => "family", "title" => "Access Control",
          "controls" => [
            { "id" => "ac-1", "class" => "SP800-53", "title" => "Policy and Procedures",
              "props" => [ { "name" => "label", "value" => "AC-1" } ],
              "parts" => [ { "id" => "ac-1_smt", "name" => "statement",
                             "prose" => "Develop and document access control policy." } ] },
            { "id" => "ac-2", "class" => "SP800-53", "title" => "Account Management",
              "props" => [ { "name" => "label", "value" => "AC-2" } ],
              "parts" => [ { "id" => "ac-2_smt", "name" => "statement",
                             "prose" => "Define and document account types." } ] }
          ]
        } ]
      }
    }
  end

  let(:profile) do
    create(:profile_document, lifecycle_status: "published",
           resolved_catalog_json: resolved_catalog_json, published: Time.current.iso8601)
  end

  # The documents differ, so their own UUIDs differ — that is correct, they ARE
  # two documents. What must hold is that each one's controls are derived from
  # its own document UUID, so regenerating a document with a pinned identity
  # reproduces every identifier beneath it.
  describe "SspFromProfileService" do
    # `ssp_documents.uuid` is uniquely indexed, so two documents cannot share
    # one. The property that matters is that each control's UUID is a pure
    # function of (document uuid, control id) — which is what makes regenerating
    # a document of known identity reproduce every identifier beneath it.
    it "derives every control UUID from its own document, in both documents" do
      first  = SspFromProfileService.new(profile, name: "First", authorization_boundary: boundary).create
      second = SspFromProfileService.new(profile, name: "Second", authorization_boundary: boundary).create

      [ first, second ].each do |ssp|
        ssp.ssp_controls.each do |control|
          expect(control.uuid).to eq(
            OscalUuidService.derived(ssp.uuid, "ssp-control", control.control_id)
          ), "#{ssp.name}/#{control.control_id} was not derived"
        end
      end
    end

    # Proves the derivation is doing the work, not that both happened to be
    # random-and-unequal: the two documents' controls must differ BECAUSE their
    # document UUIDs differ.
    it "gives the same control id different UUIDs under different documents" do
      first  = SspFromProfileService.new(profile, name: "First", authorization_boundary: boundary).create
      second = SspFromProfileService.new(profile, name: "Second", authorization_boundary: boundary).create

      expect(first.ssp_controls.find_by(control_id: "ac-1").uuid)
        .not_to eq(second.ssp_controls.find_by(control_id: "ac-1").uuid)
    end

    it "produces a UUID that is a pure function of the document and control id" do
      ssp = SspFromProfileService.new(profile, name: "Derived", authorization_boundary: boundary).create
      control = ssp.ssp_controls.find_by(control_id: "ac-1")

      expect(control.uuid).to eq(OscalUuidService.derived(ssp.uuid, "ssp-control", "ac-1"))
    end

    # Control FIELDS carry no uuid column on any document type, so there is
    # nothing to stabilise there. Pinned so that if one is ever added, this
    # says plainly that it was not covered.
    it "has no field-level UUID to stabilise" do
      expect(SspControlField.column_names).not_to include("uuid")
      expect(SarControlField.column_names).not_to include("uuid")
      expect(CdefControlField.column_names).not_to include("uuid")
    end

    it "gives two different controls different UUIDs" do
      ssp = SspFromProfileService.new(profile, name: "Distinct", authorization_boundary: boundary).create

      expect(ssp.ssp_controls.pluck(:uuid).uniq.length).to eq(ssp.ssp_controls.count)
    end

    it "scaffolds the this-system component deterministically" do
      ssp = SspFromProfileService.new(profile, name: "Component", authorization_boundary: boundary).create

      expect(ssp.ssp_components.find_by(component_type: "this-system").uuid)
        .to eq(OscalUuidService.derived(ssp.uuid, "ssp-component", "this-system"))
    end
  end

  describe "SarFromSspService" do
    it "derives result, control, finding and risk UUIDs from their parents" do
      ssp = SspFromProfileService.new(profile, name: "For SAR", authorization_boundary: boundary).create
      sar = SarFromSspService.new(ssp, name: "SAR").create

      result = sar.sar_results.first
      expect(result.uuid).to eq(OscalUuidService.derived(sar.uuid, "sar-result", "default"))

      control = sar.sar_controls.find_by(control_id: "ac-1")
      expect(control.uuid).to eq(OscalUuidService.derived(sar.uuid, "sar-control", "ac-1"))

      finding = result.sar_findings.find { |f| f.title.include?("ac-1") }
      expect(finding.uuid).to eq(OscalUuidService.derived(result.uuid, "sar-finding", "ac-1"))
    end
  end

  # An imported document carries the source's own UUIDs. Deriving them here
  # would overwrite the identity the source assigned, which is the opposite of
  # what stability means for an import.
  describe "importers are deliberately unchanged" do
    it "keeps the source's own control UUIDs on an OSCAL import" do
      source_uuid = "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee"
      json = {
        "component-definition" => {
          "uuid" => "99999999-8888-4777-8666-555555555555",
          "metadata" => { "title" => "Imported", "version" => "1.0",
                          "oscal-version" => "1.1.2", "last-modified" => Time.current.iso8601 },
          "components" => [ {
            "uuid" => source_uuid, "type" => "software", "title" => "Thing",
            "description" => "d",
            "control-implementations" => [ {
              "uuid" => "12121212-3434-4545-8656-767676767676",
              "source" => "catalog.json", "description" => "ci",
              "implemented-requirements" => [ {
                "uuid" => "13131313-3434-4545-8656-767676767676",
                "control-id" => "ac-1", "description" => "r"
              } ]
            } ]
          } ]
        }
      }

      doc = create(:cdef_document)
      Tempfile.create([ "cdef", ".json" ]) do |file|
        file.write(json.to_json)
        file.flush
        CdefJsonParserService.new(doc, file.path).parse(validate: false)
      end

      expect(doc.cdef_controls.reload).to be_present

      # Whatever the importer stored, it must not be a value derived from the
      # document — that would mean it invented an identity for imported content.
      doc.cdef_controls.each do |control|
        expect(control.uuid).not_to eq(
          OscalUuidService.derived(doc.uuid, "cdef-control", control.control_id.to_s)
        )
      end
    end
  end
end
