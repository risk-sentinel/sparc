# frozen_string_literal: true

require "rails_helper"

# #1106 — the check that catches what JSON Schema structurally cannot.
#
# The end-to-end examples at the bottom are the ones that matter most: they
# export REAL documents through the real exporters and assert the result is
# conformant. A green unit suite is not a valid artifact, and this issue exists
# because "SCHEMA VALIDATION: PASSED" was reported for months over a document
# that told a conforming reader `deferred` in NIST's namespace.
RSpec.describe OscalConformanceService do
  let(:boundary) { create(:authorization_boundary) }

  def check(doc, model: "system-security-plan")
    described_class.new(doc, model: model).validate
  end

  def ssp_doc(overrides = {})
    {
      "system-security-plan" => {
        "metadata" => { "oscal-version" => "1.2.2", "roles" => [], "parties" => [] }
      }.deep_merge(overrides)
    }
  end

  describe "prop names" do
    it "accepts a NIST-defined name with no ns" do
      doc = ssp_doc("control-implementation" => {
                      "implemented-requirements" => [ { "props" => [ { "name" => "control-origination", "value" => "inherited" } ] } ]
                    })

      expect(check(doc)).to be_conformant
    end

    it "rejects a name NIST does not define, emitted with no ns" do
      doc = ssp_doc("control-implementation" => {
                      "implemented-requirements" => [ { "props" => [ { "name" => "implementation-status", "value" => "planned" } ] } ]
                    })

      result = check(doc)
      expect(result).not_to be_conformant
      expect(result.violations.map(&:rule)).to include("prop-name-not-nist")
    end

    it "accepts the same name once it carries the deployment namespace" do
      doc = ssp_doc("control-implementation" => {
                      "implemented-requirements" => [ { "props" => [
                        { "name" => "implementation-status", "ns" => OscalNamespace.instance, "value" => "planned" }
                      ] } ]
                    })

      expect(check(doc)).to be_conformant
    end
  end

  describe "prop values" do
    it "rejects a value outside an ENFORCED NIST vocabulary" do
      doc = ssp_doc("control-implementation" => {
                      "implemented-requirements" => [ { "props" => [ { "name" => "control-origination", "value" => "System Specific" } ] } ]
                    })

      result = check(doc)
      expect(result.violations.map(&:rule)).to include("prop-value-not-in-vocabulary")
    end
  end

  describe "referential integrity" do
    it "rejects a role-id that resolves to no declared role" do
      doc = ssp_doc(
        "metadata" => { "oscal-version" => "1.2.2", "roles" => [ { "id" => "system-owner" } ], "parties" => [] },
        "control-implementation" => {
          "implemented-requirements" => [ { "responsible-roles" => [ { "role-id" => "isso" } ] } ]
        }
      )

      result = check(doc)
      expect(result.violations.map(&:rule)).to include("role-id-unresolved")
    end

    # The deployment-defined case the owner asked for: AT&T's Policy Department
    # is legal OSCAL, because NIST sets allow-other on role-id. The ONLY
    # requirement is that it is declared.
    it "accepts a deployment-defined role once it is declared" do
      doc = ssp_doc(
        "metadata" => {
          "oscal-version" => "1.2.2", "parties" => [],
          "roles" => [ { "id" => "policy-department", "title" => "Policy Department",
                         "props" => [ { "name" => "role-source", "ns" => OscalNamespace.instance,
                                        "value" => "organization-defined" } ] } ]
        },
        "control-implementation" => {
          "implemented-requirements" => [ { "responsible-roles" => [ { "role-id" => "policy-department" } ] } ]
        }
      )

      expect(check(doc)).to be_conformant
    end

    it "rejects a party-uuid that resolves to no declared party" do
      doc = ssp_doc("metadata" => {
                      "oscal-version" => "1.2.2", "roles" => [],
                      "parties" => [ { "uuid" => "11111111-1111-4111-8111-111111111111" } ],
                      "responsible-parties" => [ { "role-id" => "x", "party-uuids" => [ "22222222-2222-4222-8222-222222222222" ] } ]
                    })

      expect(check(doc).violations.map(&:rule)).to include("party-uuid-unresolved")
    end
  end

  describe "an unknown OSCAL version" do
    it "is a violation, not a silent pass" do
      doc = ssp_doc("metadata" => { "oscal-version" => "9.9.9" })

      result = check(doc)
      expect(result).not_to be_conformant
      expect(result.violations.map(&:rule)).to include("dataset-missing")
    end
  end

  # ── End to end. These are the specs that would have caught #1106. ──────────
  describe "real exports" do
    it "the SSP exporter produces a conformant document" do
      ssp     = create(:ssp_document, authorization_boundary: boundary)
      control = ssp.ssp_controls.create!(control_id: "ac-1", title: "Policy and Procedures")
      control.ssp_control_fields.create!(field_name: "status", field_value: "Deferred")
      control.ssp_control_fields.create!(field_name: "control_type", field_value: "System Specific")

      result = check(JSON.parse(OscalSspExportService.new(ssp.reload).export_unvalidated))

      expect(result.violations).to be_empty, -> { result.violations.map(&:message).join("\n") }
    end

    it "the CDEF exporter produces a conformant document" do
      cdef = create(:cdef_document, cdef_type: "disa_stig")
      # The control MUST carry the STIG fields, or this example is vacuous: with
      # no severity/rule-id/group-id/stig-id there are no props to check, and the
      # spec passes whether or not they are namespaced. Caught by mutation —
      # un-namespacing `severity` left it green until this data was added.
      control = create(:cdef_control, cdef_document: cdef, severity: "high",
                                      rule_id: "SV-230221r1_rule", group_id: "V-230221",
                                      stig_id: "RHEL-09-211010", cci_references: "CCI-000048, CCI-002243")
      control.cdef_control_fields.create!(field_name: "implementation_status", field_value: "implemented")
      control.cdef_control_fields.create!(field_name: "control_origin", field_value: "System Specific")

      json = JSON.parse(OscalComponentDefinitionExportService.new(cdef.reload).export_unvalidated)
      props = json.to_s

      expect(props).to include("severity"), "the export must actually contain the props under test"
      result = check(json, model: "component-definition")

      expect(result.violations).to be_empty, -> { result.violations.map(&:message).join("\n") }
    end
  end
end
