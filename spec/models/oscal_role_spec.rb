# frozen_string_literal: true

require "rails_helper"

# #1116 — two tiers of role, both legal, one hard rule.
RSpec.describe OscalRole do
  describe "NIST's suggested vocabulary" do
    it "is read from the generated dataset, not a copied list" do
      expect(described_class.suggested_ids).to include(
        "information-system-security-officer", "system-owner", "authorizing-official",
        "system-poc-technical", "privacy-poc"
      )
    end

    # The assertion that makes SSP_DEFAULT_IDS safe to edit. A typo, or a NIST
    # rename, would otherwise ship a document declaring a role id that no
    # consuming tool recognises — the exact failure #1116 describes when an
    # author types `isso`.
    it "contains every id the SSP declares by default" do
      unknown = described_class::SSP_DEFAULT_IDS - described_class.suggested_ids

      expect(unknown).to be_empty, <<~MSG
        These default role ids are not in NIST's suggested vocabulary: #{unknown.join(', ')}

        Either they are typos, or NIST renamed them. Inventing a private id for a
        role NIST defines means a reader resolving it has to guess.
      MSG
    end

    it "uses NIST's id for the ISSO rather than the abbreviation authors type" do
      expect(described_class::SSP_DEFAULT_IDS).to include("information-system-security-officer")
      expect(described_class::SSP_DEFAULT_IDS).not_to include("isso")
    end
  end

  describe ".humanize" do
    it "renders an id as something a person recognises" do
      expect(described_class.humanize("information-system-security-officer"))
        .to eq("Information System Security Officer")
      expect(described_class.humanize("system-owner")).to eq("System Owner")
    end

    it "keeps acronyms uppercase" do
      expect(described_class.humanize("system-poc-technical")).to eq("System POC Technical")
    end
  end

  describe ".organization_defined" do
    # A role id cannot carry a namespace — it is a plain NCName token. The
    # deployment's namespace attaches to a PROP on the role instead, which is
    # what OSCAL provides for (`assembly ref="property"` on the role assembly).
    it "marks the role with a prop under the deployment namespace, not a namespaced id" do
      role = described_class.organization_defined("policy-department", "Policy Department")

      expect(role["id"]).to eq("policy-department")
      expect(role["id"]).not_to include("://"), "a role-id is a token, never a URI"
      expect(role.dig("props", 0, "ns")).to eq(OscalNamespace.instance)
      expect(described_class).to be_organization_defined(role)
    end

    it "does not treat a NIST role as organization-defined" do
      expect(described_class).not_to be_organization_defined("id" => "system-owner")
    end
  end

  # The rule that matters: a deployment-defined role is as valid as a NIST one,
  # PROVIDED it is declared. NIST sets allow-other="yes" on role-id precisely so
  # this works.
  describe "a deployment-defined role in a real document" do
    let(:boundary) { create(:authorization_boundary) }
    let(:ssp)      { create(:ssp_document, authorization_boundary: boundary) }

    it "is conformant once declared, and unresolved when not" do
      control = ssp.ssp_controls.create!(control_id: "ac-1", title: "Policy")
      statement = control.ssp_control_statements.create!(
        statement_id: "ac-1_stmt", uuid: SecureRandom.uuid,
        responsible_roles_data: [ { "role-id" => "policy-department" } ]
      )
      expect(statement).to be_persisted

      undeclared = OscalConformanceService.new(
        JSON.parse(OscalSspExportService.new(ssp.reload).export_unvalidated),
        model: "system-security-plan"
      ).validate
      expect(undeclared.violations.map(&:rule)).to include("role-id-unresolved")

      ssp.update!(metadata_extra: {
                    "roles" => described_class::SSP_DEFAULT_IDS.map { |id|
                      { "id" => id, "title" => described_class.humanize(id) }
                    } + [ described_class.organization_defined("policy-department", "Policy Department") ]
                  })

      declared = OscalConformanceService.new(
        JSON.parse(OscalSspExportService.new(ssp.reload).export_unvalidated),
        model: "system-security-plan"
      ).validate
      expect(declared.violations.select { |v| v.rule == "role-id-unresolved" }).to be_empty
    end
  end
end
