# frozen_string_literal: true

require "rails_helper"

# #1228 — checks 1 and 2, each proven both ways on NIST's real content: red on
# the v5.2.0 catalog NIST released with the errors, green on the develop file
# that fixes them.
RSpec.describe CatalogIntegrityService do
  let(:released) { JSON.parse(Rails.root.join("spec/fixtures/files/catalogs/NIST_SP-800-53_rev5_catalog.json").read) }
  let(:develop)  { NistCatalogSource.catalog }

  # Found by check 1 on the develop file and NOT fixed upstream: the PL-08(01)
  # and SC-32(01) assessment methods carry their parent control's label. They
  # are NIST's to fix (recorded in the provenance sidecar as
  # known_upstream_findings) and are not patched here. When NIST fixes them the
  # first example below fails, and this list is emptied.
  let(:known_upstream) do
    [
      %w[label-names-own-control pl-8.1 pl-8.1_asm-examine],
      %w[label-names-own-control pl-8.1 pl-8.1_asm-interview],
      %w[label-names-own-control pl-8.1 pl-8.1_asm-test],
      %w[label-names-own-control sc-32.1 sc-32.1_asm-examine],
      %w[label-names-own-control sc-32.1 sc-32.1_asm-interview],
      %w[label-names-own-control sc-32.1 sc-32.1_asm-test]
    ]
  end

  def triples(findings) = findings.map { |f| [ f.rule, f.control_id, f.part_id ] }

  it "finds nothing on the develop file but the errors NIST has not fixed yet" do
    expect(triples(described_class.check(develop))).to match_array(known_upstream)
  end

  describe "check 1: a part's label names its own control" do
    it "is red on v5.2.0, where SA-15(13)'s Examine method is labelled SA-15(12)-Examine" do
      findings = described_class.check(released).select { |f| f.rule == "label-names-own-control" }

      expect(triples(findings) - known_upstream)
        .to eq([ %w[label-names-own-control sa-15.13 sa-15.13_asm-examine] ])
      expect(findings.find { |f| f.control_id == "sa-15.13" }.message).to include("SA-15(12)-Examine", "sa-15.12")
    end

    it "is green on SA-15(13) once NIST's fix is in" do
      expect(described_class.check(develop).map(&:control_id)).not_to include("sa-15.13")
    end

    it "reads enhancement, zero-padded and part-suffixed labels as their control" do
      expect(described_class.control_id_for_label("SA-15(12)-Examine")).to eq("sa-15.12")
      expect(described_class.control_id_for_label("SI-02(07)c.[01]")).to eq("si-2.7")
      expect(described_class.control_id_for_label("SA-24b.[10]")).to eq("sa-24")
      expect(described_class.control_id_for_label("AC-01")).to eq("ac-1")
    end

    it "ignores a label that names no control" do
      expect(described_class.control_id_for_label("a.")).to be_nil
      expect(described_class.control_id_for_label("(a)")).to be_nil
    end

    it "leaves a label in another namespace to its owner" do
      catalog = { "catalog" => { "groups" => [ { "id" => "ex", "controls" => [
        { "id" => "ex-1", "parts" => [ { "id" => "ex-1_x", "name" => "item",
                                         "props" => [ { "name" => "label", "ns" => "https://example.invalid/ns", "value" => "EX-2" } ] } ] }
      ] } ] } }

      expect(described_class.check(catalog)).to be_empty
    end
  end

  describe "check 2: assessment-for stays inside its own control's statement" do
    it "is red on v5.2.0, where six SA-24 objectives point into AC-2" do
      findings = described_class.check(released).select { |f| f.rule == "assessment-for-own-statement" }

      expect(findings.map(&:control_id).uniq).to eq([ "sa-24" ])
      expect(findings.map(&:part_id)).to match_array(%w[sa-24_obj.a-5 sa-24_obj.b-1 sa-24_obj.b-2
                                                        sa-24_obj.b-3 sa-24_obj.b-4 sa-24_obj.b-5])
      expect(findings.first.message).to include("#ac-2_smt")
    end

    it "is green on SA-24 once NIST's fix is in" do
      expect(described_class.check(develop).map(&:rule)).not_to include("assessment-for-own-statement")
    end

    it "checks assessment-method parts as well as objectives" do
      catalog = { "groups" => [ { "id" => "ex", "controls" => [
        { "id" => "ex-1", "parts" => [
          { "id" => "ex-1_smt", "name" => "statement" },
          { "id" => "ex-1_asm", "name" => "assessment-method",
            "links" => [ { "href" => "#ex-2_smt", "rel" => "assessment-for" } ] }
        ] }
      ] } ] }

      expect(triples(described_class.check(catalog))).to eq([ %w[assessment-for-own-statement ex-1 ex-1_asm] ])
    end
  end
end
