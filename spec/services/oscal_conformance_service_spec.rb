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

  # #1134 — the collector matched "role-id" and missed the PLURAL, so
  # `system-implementation.users[].role-ids` was never checked at all.
  # `import_boundary_users` wrote the raw boundary-membership role into it,
  # underscored and undeclared, and this service reported a clean document.
  describe "role-ids on a system user" do
    def doc_with_user_roles(ids, declared: [])
      ssp_doc(
        "metadata" => { "roles" => declared.map { |i| { "id" => i, "title" => i } } },
        "system-implementation" => { "users" => [ { "title" => "A Person", "role-ids" => ids } ] }
      )
    end

    it "reports an id that resolves to no declared role" do
      result = check(doc_with_user_roles([ "authorizing_official" ], declared: [ "authorizing-official" ]))

      expect(result.violations.map(&:rule)).to include("role-id-unresolved")
    end

    it "names which entry in the array is unresolved" do
      result = check(doc_with_user_roles([ "system-owner", "not-declared" ], declared: [ "system-owner" ]))

      expect(result.violations.map(&:location)).to eq([ "/system-implementation/users[0]/role-ids[1]" ])
    end

    it "accepts ids the document declares" do
      result = check(doc_with_user_roles([ "system-owner" ], declared: [ "system-owner" ]))

      expect(result.violations).to be_empty
    end
  end

  # Also found by the #1134 audit: `location-uuids` resolves against
  # `metadata.locations`, which is the same half of referential integrity this
  # service owns, and it was not collected either.
  describe "location-uuids" do
    it "reports a location that is not declared" do
      result = check(ssp_doc("metadata" => { "locations" => [] },
                             "system-implementation" => {
                               "users" => [ { "title" => "x", "location-uuids" => [ "11111111-1111-4111-8111-111111111111" ] } ]
                             }))

      expect(result.violations.map(&:rule)).to include("location-uuid-unresolved")
    end

    it "accepts one the metadata declares" do
      uuid = "11111111-1111-4111-8111-111111111111"
      result = check(ssp_doc("metadata" => { "locations" => [ { "uuid" => uuid } ] },
                             "system-implementation" => {
                               "users" => [ { "title" => "x", "location-uuids" => [ uuid ] } ]
                             }))

      expect(result.violations).to be_empty
    end
  end

  # #1131 — parts are a separate vocabulary from props, and `check_part` was the
  # one half of the check no spec reached. Catalog parts carry NIST's names
  # (`statement`, `item`, `guidance`), so the catalog model is the natural target.
  describe "part names" do
    def catalog_doc(parts)
      { "catalog" => {
        "metadata" => { "oscal-version" => "1.2.2", "roles" => [], "parties" => [] },
        "groups" => [ { "id" => "ac", "controls" => [ { "id" => "ac-1", "parts" => parts } ] } ]
      } }
    end

    def check_catalog(parts) = check(catalog_doc(parts), model: "catalog")

    it "accepts NIST-defined part names with no ns" do
      result = check_catalog([ { "name" => "statement" }, { "name" => "guidance" } ])

      expect(result).to be_conformant
    end

    it "rejects a name NIST does not define, emitted with no ns, at its exact location" do
      result = check_catalog([ { "name" => "statement" }, { "name" => "assessment-schedule" } ])

      expect(result.violations.map { |v| [ v.rule, v.location ] })
        .to eq([ [ "part-name-not-nist", "/groups[0]/controls[0]/parts[1]" ] ])
    end

    it "accepts the same name once it carries the deployment namespace" do
      result = check_catalog([ { "name" => "assessment-schedule", "ns" => OscalNamespace.instance } ])

      expect(result).to be_conformant
    end

    # A prop name is not a part name. The dataset generator once recorded
    # `statement` as a catalog PROP; the reverse confusion must not pass either.
    it "rejects a prop name used as a part name" do
      expect(check_catalog([ { "name" => "label" } ]).violations.map(&:rule)).to eq([ "part-name-not-nist" ])
    end

    it "reports a bad name nested under a bad parent, with its full path" do
      result = check_catalog([ { "name" => "not-nist", "parts" => [ { "name" => "also-not-nist" } ] } ])

      expect(result.violations.map(&:location))
        .to eq([ "/groups[0]/controls[0]/parts[0]", "/groups[0]/controls[0]/parts[0]/parts[0]" ])
    end

    # The shape real catalogs have: `statement` holding `item`s. A bad name two
    # levels under a GOOD parent must still be found.
    it "reports a bad name nested under a NIST-defined parent" do
      result = check_catalog([ { "name" => "statement", "parts" => [
        { "name" => "item", "parts" => [ { "name" => "not-nist" } ] }
      ] } ])

      expect(result.violations.map(&:location))
        .to eq([ "/groups[0]/controls[0]/parts[0]/parts[0]/parts[0]" ])
    end

    # A part in the deployment's namespace may still hold children with no `ns`,
    # and each of those claims NIST defines its name.
    it "reports a bad name with no ns nested under a namespaced parent" do
      result = check_catalog([ { "name" => "local", "ns" => OscalNamespace.instance, "parts" => [
        { "name" => "not-nist" }
      ] } ])

      expect(result.violations.map(&:location)).to eq([ "/groups[0]/controls[0]/parts[0]/parts[0]" ])
    end

    it "checks the props a part carries" do
      result = check_catalog([ { "name" => "statement", "props" => [ { "name" => "not-a-nist-prop", "value" => "x" } ] } ])

      expect(result.violations.map { |v| [ v.rule, v.location ] })
        .to eq([ [ "prop-name-not-nist", "/groups[0]/controls[0]/parts[0]/props[0]" ] ])
    end
  end

  describe "party-uuid (singular)" do
    let(:declared) { "11111111-1111-4111-8111-111111111111" }

    def doc_with_origin_party(uuid)
      ssp_doc("metadata" => { "parties" => [ { "uuid" => declared } ],
                              "responsible-parties" => [ { "role-id" => "x", "party-uuid" => uuid } ],
                              "roles" => [ { "id" => "x" } ] })
    end

    it "reports one that resolves to no declared party" do
      result = check(doc_with_origin_party("22222222-2222-4222-8222-222222222222"))

      expect(result.violations.map { |v| [ v.rule, v.location ] })
        .to eq([ [ "party-uuid-unresolved", "/metadata/responsible-parties[0]" ] ])
    end

    it "accepts one the metadata declares" do
      expect(check(doc_with_origin_party(declared)).violations).to be_empty
    end
  end

  describe "Result#summary" do
    it "says conformant, with the advisory count" do
      result = described_class::Result.new(findings: [
        described_class::Finding.new(severity: :advisory, rule: "r", location: "/", message: "m")
      ])

      expect(result.summary).to eq("conformant (1 advisory)")
    end

    it "counts violations and advisories when not conformant" do
      findings = %i[violation violation advisory].map do |s|
        described_class::Finding.new(severity: s, rule: "r", location: "/", message: "m")
      end

      expect(described_class::Result.new(findings: findings).summary).to eq("2 violation(s), 1 advisory")
    end
  end

  # Unreachable through real input by design: it guards against a reference KIND
  # being added to `collect_references` and forgotten in `check_references`, so
  # the condition has to be constructed.
  describe "an unhandled reference kind" do
    it "raises instead of dropping the reference silently" do
      service = described_class.new(ssp_doc, model: "system-security-plan")
      allow(service).to receive(:collect_references).and_return([ [ :component, "x", "/p" ] ])

      expect { service.validate }.to raise_error(ArgumentError, /unhandled reference kind :component at \/p/)
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
