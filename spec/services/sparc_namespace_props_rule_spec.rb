# frozen_string_literal: true

require "rails_helper"

# #1154 — the SPARC-namespace props gate on the validated export path.
#
# Each refusal case is built from a document the rule ACCEPTS, changed in one
# place, so a rule that refused everything could not satisfy these examples and
# a rule that accepted everything could not either.
RSpec.describe SparcNamespacePropsRule do
  let(:ns) { OscalNamespace.uri(:sparc) }
  let(:boundary_uuid) { SecureRandom.uuid }
  let(:org_uuid) { SecureRandom.uuid }

  def prop(name, value, namespace: ns) = { "name" => name, "ns" => namespace, "value" => value }

  let(:ssp) do
    {
      "system-security-plan" => {
        "uuid" => SecureRandom.uuid,
        "metadata" => {
          "title" => "SSP",
          "props" => [
            prop("node-type", "system"),
            prop("parent-uuid", boundary_uuid),
            prop("fips-199", "moderate"),
            prop("next-decision-date", "2026-10-11")
          ],
          "parties" => [ { "uuid" => org_uuid, "type" => "organization", "name" => "Org",
                           "props" => [ prop("node-type", "organization") ] } ]
        },
        "back-matter" => {
          "resources" => [ { "uuid" => SecureRandom.uuid, "title" => "Evidence",
                             "props" => [ prop("evidence-kind", "manual-attestation"),
                                          prop("signed-by", SecureRandom.uuid) ] } ]
        }
      }
    }
  end

  let(:required) { { "node-type" => "system", "parent-uuid" => boundary_uuid, "fips-199" => "moderate" } }

  let(:poam) do
    {
      "plan-of-action-and-milestones" => {
        "uuid" => SecureRandom.uuid,
        "metadata" => { "title" => "POA&M" },
        "risks" => [ { "uuid" => SecureRandom.uuid,
                       "props" => [ prop("blocks-ato", "true"), prop("condition-expires", "2026-11-01"),
                                    prop("trigger", "score<0.85") ] } ]
      }
    }
  end

  let(:sar) do
    {
      "assessment-results" => {
        "uuid" => SecureRandom.uuid,
        "metadata" => { "title" => "SAR" },
        "results" => [ { "uuid" => SecureRandom.uuid,
                         "risks" => [ { "uuid" => SecureRandom.uuid, "props" => [ prop("blocks-ato", "false") ] } ] } ]
      }
    }
  end

  def errors_for(model, data, required_metadata: {})
    described_class.new(model, data, required_metadata: required_metadata).errors
  end

  describe "a conforming document" do
    it "accepts an SSP carrying all nine placements' SSP-side props" do
      expect(errors_for(:ssp, ssp, required_metadata: required)).to eq([])
      expect(described_class.validate!(:ssp, ssp, required_metadata: required)).to be(true)
    end

    it "accepts a POA&M risk and a SAR risk carrying their props" do
      expect(errors_for(:poam, poam)).to eq([])
      expect(errors_for(:assessment_results, sar)).to eq([])
    end

    it "ignores props in every other namespace, including the nine names claimed by someone else" do
      ssp["system-security-plan"]["metadata"]["props"] << prop("fips-199", "extreme", namespace: "https://example.org/ns")
      ssp["system-security-plan"]["metadata"]["props"] << { "name" => "fips-199", "value" => "whatever" }

      expect(errors_for(:ssp, ssp, required_metadata: required)).to eq([])
    end
  end

  describe "values the vendored schema rejects" do
    {
      [ "metadata", "fips-199" ]             => "fips-199-moderate",
      [ "metadata", "node-type" ]            => "tenant",
      [ "metadata", "parent-uuid" ]          => "not-a-uuid",
      [ "metadata", "next-decision-date" ]   => "11/10/2026"
    }.each do |(_where, name), bad|
      it "refuses SSP metadata #{name}=#{bad.inspect}" do
        target = ssp["system-security-plan"]["metadata"]["props"].find { |p| p["name"] == name }
        target["value"] = bad

        expect { described_class.validate!(:ssp, ssp) }
          .to raise_error(OscalValidationError, %r{/metadata/props/\d+ \(#{name}\)})
      end
    end

    { "blocks-ato" => "maybe", "condition-expires" => "2026-11", "trigger" => "score=0.85" }.each do |name, bad|
      it "refuses a POA&M risk #{name}=#{bad.inspect}" do
        poam["plan-of-action-and-milestones"]["risks"][0]["props"].find { |p| p["name"] == name }["value"] = bad

        expect(errors_for(:poam, poam).join).to match(%r{/risks/0/props/\d+ \(#{name}\)})
      end
    end

    it "refuses an evidence-kind outside the enum and a signed-by that is not a uuid" do
      props = ssp["system-security-plan"]["back-matter"]["resources"][0]["props"]
      props[0]["value"] = "photograph"
      props[1]["value"] = "Jane Doe"

      messages = errors_for(:ssp, ssp, required_metadata: required)
      expect(messages.grep(/evidence-kind/).size).to eq(1)
      expect(messages.grep(/signed-by/).size).to eq(1)
    end

    it "refuses a SAR risk blocks-ato that is not the string true/false" do
      sar["assessment-results"]["results"][0]["risks"][0]["props"][0]["value"] = "yes"

      expect(errors_for(:assessment_results, sar)).not_to be_empty
    end
  end

  describe "placement" do
    it "refuses a risk prop on SSP metadata" do
      ssp["system-security-plan"]["metadata"]["props"] << prop("blocks-ato", "true")

      expect(errors_for(:ssp, ssp, required_metadata: required).join)
        .to include("(blocks-ato): belongs on a risk, not here")
    end

    it "refuses fips-199 on a POA&M's metadata (SSP metadata only)" do
      poam["plan-of-action-and-milestones"]["metadata"]["props"] = [ prop("fips-199", "low") ]

      expect(errors_for(:poam, poam).join).to include("(fips-199): belongs on SSP metadata, not here")
    end

    it "refuses evidence-kind on a risk" do
      poam["plan-of-action-and-milestones"]["risks"][0]["props"] << prop("evidence-kind", "document")

      expect(errors_for(:poam, poam).join).to include("(evidence-kind): belongs on a back-matter resource")
    end
  end

  describe "uniqueness" do
    it "refuses two fips-199 values on one SSP" do
      ssp["system-security-plan"]["metadata"]["props"] << prop("fips-199", "high")

      expect(errors_for(:ssp, ssp, required_metadata: required).join).to include("fips-199 appears 2 times")
    end
  end

  describe "required SSP metadata" do
    %w[node-type parent-uuid fips-199].each do |name|
      it "refuses an SSP whose metadata is missing #{name}" do
        ssp["system-security-plan"]["metadata"]["props"].reject! { |p| p["name"] == name }

        expect { described_class.validate!(:ssp, ssp, required_metadata: required) }
          .to raise_error(OscalValidationError, /#{name} is required and missing/)
      end
    end

    it "refuses a parent-uuid that is well-formed but names another boundary" do
      required["parent-uuid"] = SecureRandom.uuid

      expect(errors_for(:ssp, ssp, required_metadata: required).join).to include("parent-uuid is")
    end

    it "requires nothing the caller did not ask for (a boundary-less, uncategorized SSP)" do
      ssp["system-security-plan"]["metadata"]["props"] = [ prop("node-type", "system") ]

      expect(errors_for(:ssp, ssp, required_metadata: { "node-type" => "system" })).to eq([])
    end
  end

  # The finding the owner asked for: SPARC ALREADY emits props in its own
  # namespace that the vendored schema rejects, because the schema's `name` is
  # a closed enum of the nine. The rule is scoped to the nine so that existing
  # exports keep working; this records WHY, reproducibly, rather than in prose.
  describe "SPARC's other props in its own namespace" do
    # Every name SPARC emits under its namespace today (grep `OscalNamespace.instance`
    # in app/services and app/models/oscal_role.rb).
    %w[sparc-status sparc-control-origination control-type provided-as responsible-entities
       priority impact-level assessment-type type role-source sparc-implementation-status
       control-origin baseline-priority].each do |name|
      it "the vendored schema rejects #{name} — which is why the rule does not apply it" do
        other = prop(name, "value")

        expect(described_class.schema_errors_for(other)).not_to be_empty
        ssp["system-security-plan"]["metadata"]["props"] << other
        expect(errors_for(:ssp, ssp, required_metadata: required)).to eq([])
      end
    end
  end
end
