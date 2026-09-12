# frozen_string_literal: true

require "rails_helper"

# #940 S3 — FIPS-199 categorization on the BOUNDARY, derived rather than typed.
#
# Owner, 2026-09-12: "The boundary's Classification is part of the boundary so
# that the SSP is accurate. Information types is both SP 800-60 and 800-53
# related to keep the boundaries Classification, Integrity, Availability (CIA)
# of data and what the boundary really is."
#
# The chain: SP 800-60 gives each information type provisional C/I/A impacts ->
# the owner adjusts -> FIPS-199 takes the HIGH WATER MARK -> that selects the
# 800-53 baseline. SPARC had every piece and assembled none of them.
RSpec.describe "boundary FIPS-199 categorization (#940)" do
  let(:boundary) { create(:authorization_boundary) }
  let(:ssp) { create(:ssp_document, authorization_boundary: boundary) }

  # Impacts are passed through as the real column names rather than via named
  # parameters.
  #
  # CodeQL's rb/clear-text-storage-sensitive-data flagged the previous signature
  # (alerts #40 and #41) because a PARAMETER called `confidentiality` matches its
  # sensitive-name heuristic. The values are FIPS-199 impact levels —
  # `fips-199-low` — which are a categorization, not a secret, so the finding was
  # a false positive driven entirely by the name I chose. Removing the trigger is
  # cheaper than a dismissal and reads better: the call sites now say exactly
  # which column they are setting.
  def information_type(**impacts)
    SspInformationType.create!(
      ssp_document: ssp, authorization_boundary: boundary,
      uuid: SecureRandom.uuid, title: "Test type", description: "Test information type",
      **impacts
    )
  end

  describe "the high water mark" do
    # The rule that makes FIPS-199 what it is: one HIGH anywhere makes the
    # system HIGH. Averaging, or "mostly moderate", is wrong.
    it "takes the HIGHEST impact across all three objectives" do
      information_type(confidentiality_impact_selected: "fips-199-low",
                       integrity_impact_selected: "fips-199-high",
                       availability_impact_selected: "fips-199-low")

      expect(boundary.reload.security_categorization).to eq("fips-199-high")
    end

    it "takes the highest across MULTIPLE information types, not the last one" do
      information_type(confidentiality_impact_selected: "fips-199-low")
      information_type(confidentiality_impact_selected: "fips-199-moderate")

      expect(boundary.reload.security_objective(:confidentiality)).to eq("fips-199-moderate")
    end

    it "is low only when everything is low" do
      information_type(confidentiality_impact_selected: "fips-199-low", integrity_impact_selected: "fips-199-low",
                       availability_impact_selected: "fips-199-low")

      expect(boundary.reload.security_categorization).to eq("fips-199-low")
    end
  end

  describe "selected overrides base" do
    # An adjustment REPLACES the provisional value; it does not sit alongside it.
    it "prefers the owner's selected impact over the 800-60 provisional base" do
      information_type(confidentiality_impact_selected: "fips-199-low", confidentiality_impact_base: "fips-199-high")

      expect(boundary.reload.security_objective(:confidentiality)).to eq("fips-199-low")
    end

    it "falls back to the provisional base when nothing was selected" do
      information_type(confidentiality_impact_base: "fips-199-moderate")

      expect(boundary.reload.security_objective(:confidentiality)).to eq("fips-199-moderate")
    end
  end

  describe "with no information types" do
    it "falls back to the value recorded on the boundary" do
      boundary.update!(security_objective_confidentiality: "fips-199-moderate")

      expect(boundary.security_objective(:confidentiality)).to eq("fips-199-moderate")
      expect(boundary.security_categorization).to eq("fips-199-moderate")
    end

    it "is nil when nothing is recorded anywhere — not a default of low" do
      expect(boundary.security_categorization).to be_nil
    end
  end

  # The condition that was previously undetectable: a stored categorization that
  # disagrees with the information types underneath it. Before this, the level
  # was free text set by the wizard or an import and nothing compared the two.
  describe "conflict detection" do
    it "flags a stored level that contradicts the information types" do
      boundary.update!(security_objective_confidentiality: "fips-199-low")
      information_type(confidentiality_impact_selected: "fips-199-high")

      expect(boundary.reload).to be_categorization_conflicts_with_information_types
    end

    it "does not flag agreement" do
      boundary.update!(security_objective_confidentiality: "fips-199-high")
      information_type(confidentiality_impact_selected: "fips-199-high")

      expect(boundary.reload).not_to be_categorization_conflicts_with_information_types
    end

    it "does not flag when there are no information types to disagree with" do
      boundary.update!(security_objective_confidentiality: "fips-199-low")

      expect(boundary).not_to be_categorization_conflicts_with_information_types
    end
  end

  describe "information types belong to the boundary" do
    it "is reachable from the boundary, not only through the SSP" do
      information_type(confidentiality_impact_selected: "fips-199-moderate")

      expect(boundary.reload.information_types.count).to eq(1)
    end
  end
end
