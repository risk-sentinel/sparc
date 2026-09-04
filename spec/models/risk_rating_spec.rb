# frozen_string_literal: true

require "rails_helper"

# #1090 — a rating set by a person must reach the OSCAL artifact.
#
# Before this, both exporters emitted `characterizations_data` and nothing else,
# so `impact` and `likelihood` never left SPARC. Measured on the seeded estate:
# 6 poam_risks carried a rating and 0 of 16 carried any characterizations, so
# all six ratings vanished at export.
RSpec.describe RiskRating do
  shared_examples "an OSCAL-rated risk" do
    it "emits nothing extra when unrated" do
      expect(build_risk(impact: nil, likelihood: nil).characterizations_for_export).to be_nil
    end

    it "expresses the rating as facets under a naming system" do
      chars = build_risk(impact: "high", likelihood: "moderate").characterizations_for_export

      expect(chars.length).to eq(1)
      facets = chars.first["facets"]
      # A characterization REQUIRES origin + facets, and `system` is a property of
      # the FACET — it is not valid on the characterization itself. Emitting it
      # there failed OSCAL schema validation with
      # "missing required properties: origin".
      expect(chars.first.keys).to contain_exactly("origin", "facets")
      expect(chars.first.dig("origin", "actors").first)
        .to include("type" => "tool", "actor-uuid" => be_present)
      expect(facets.map { |f| f["system"] }.uniq).to eq([ described_class::DEFAULT_RATING_SYSTEM ])
      # name/system/value are all REQUIRED on a facet by the OSCAL schema.
      expect(facets).to all(include("name", "system", "value"))
      expect(facets.map { |f| [ f["name"], f["value"] ] })
        .to contain_exactly([ "impact", "high" ], [ "likelihood", "moderate" ])
    end

    it "PRESERVES facets it does not model, so a round trip loses nothing" do
      imported = [ { "origin" => { "actors" => [ { "type" => "party", "actor-uuid" => SecureRandom.uuid } ] },
                     "facets" => [ { "name" => "base_score", "system" => "http://www.first.org/cvss/v3.1", "value" => "7.5" } ] } ]
      chars = build_risk(impact: "high", likelihood: nil, characterizations_data: imported)
              .characterizations_for_export

      cvss = chars.find { |c| Array(c["facets"]).any? { |f| f["system"] == "http://www.first.org/cvss/v3.1" } }
      expect(cvss["facets"].first["value"]).to eq("7.5")
      expect(chars.length).to eq(2)
    end

    it "REPLACES a stale copy of a rating it does model" do
      stale = [ { "origin" => { "actors" => [ { "type" => "tool", "actor-uuid" => SecureRandom.uuid } ] },
                  "facets" => [ { "name" => "impact", "system" => described_class::DEFAULT_RATING_SYSTEM, "value" => "low" } ] } ]
      chars = build_risk(impact: "high", likelihood: nil, characterizations_data: stale)
              .characterizations_for_export

      values = chars.flat_map { |c| c["facets"] }.select { |f| f["name"] == "impact" }.map { |f| f["value"] }
      expect(values).to eq([ "high" ]), "a re-export must not carry both the old and new rating"
    end

    # The point of #1090's second half: a document imported under one framework
    # must not silently re-export under another. SPARC's own default applies only
    # when the artifact expressed no opinion.
    it "KEEPS the framework the metric arrived under, rather than converting it" do
      fedramp = [ { "origin" => { "actors" => [ { "type" => "party", "actor-uuid" => SecureRandom.uuid } ] },
                    "facets" => [ { "name" => "impact", "system" => "http://fedramp.gov/ns/oscal", "value" => "moderate" } ] } ]
      chars = build_risk(impact: "high", likelihood: nil, characterizations_data: fedramp)
              .characterizations_for_export

      impact_facets = chars.flat_map { |c| Array(c["facets"]) }.select { |f| f["name"] == "impact" }
      expect(impact_facets.length).to eq(1), "the rating must not be duplicated under a second system"
      expect(impact_facets.first["system"]).to eq("http://fedramp.gov/ns/oscal")
      expect(impact_facets.first["value"]).to eq("high")
      expect(chars.length).to eq(1), "no second characterization should be created"
    end

    it "honours SPARC_OSCAL_RISK_SYSTEM for a risk that expressed no framework" do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with("SPARC_OSCAL_RISK_SYSTEM", anything)
                                   .and_return("http://fedramp.gov/ns/oscal")

      chars = build_risk(impact: "high", likelihood: nil, characterizations_data: []).characterizations_for_export

      expect(chars.first["facets"].first["system"]).to eq("http://fedramp.gov/ns/oscal")
    end

    it "does not mutate the stored column" do
      stored = [ { "origin" => { "actors" => [ { "type" => "party", "actor-uuid" => SecureRandom.uuid } ] },
                   "facets" => [ { "name" => "other", "system" => "http://cve.mitre.org", "value" => "x" } ] } ]
      risk = build_risk(impact: "high", likelihood: nil, characterizations_data: stored)
      risk.characterizations_for_export

      expect(risk.characterizations_data).to eq(stored)
    end
  end

  describe SarRisk do
    def build_risk(**attrs)
      build(:sar_risk, **attrs)
    end

    it_behaves_like "an OSCAL-rated risk"
  end

  describe PoamRisk do
    def build_risk(**attrs)
      build(:poam_risk, **attrs)
    end

    it_behaves_like "an OSCAL-rated risk"
  end
end
