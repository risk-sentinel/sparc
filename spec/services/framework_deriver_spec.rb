# frozen_string_literal: true

require "rails_helper"

# #935 — the derivation rule, tested as a unit so adding a framework is a data
# change rather than an archaeology exercise.
#
# The whole reason this exists as a persisted column with a named rule, rather
# than a regex evaluated per request, is that a catalog whose title convention
# differs would be labelled with the WRONG framework — and in a compliance tool
# a confidently wrong framework is worse than no filter at all. So the negative
# cases below matter as much as the positive ones.
RSpec.describe FrameworkDeriver do
  describe ".for_catalog" do
    it "believes an explicit source over anything else" do
      catalog = create(:control_catalog, name: "Key Security Indicators", source: "FedRAMP 20x")

      expect(described_class.for_catalog(catalog)).to eq(described_class::FEDRAMP_20X)
    end

    it "reads the control-id namespace, which survives a retitled catalog" do
      catalog = create(:control_catalog, name: "Some Internal Name", source: "OSCAL")
      family  = create(:control_family, control_catalog: catalog, code: "KSI")
      %w[ksi-auth-01 ksi-auth-02 ksi-cna-01].each do |id|
        create(:catalog_control, control_family: family, control_id: id)
      end

      expect(described_class.for_catalog(catalog)).to eq(described_class::FEDRAMP_20X)
    end

    it "recognises 800-53 from a majority of NIST families" do
      catalog = create(:control_catalog, name: "Internal Copy", source: "OSCAL")
      family  = create(:control_family, control_catalog: catalog, code: "AC")
      %w[ac-1 au-2 cm-6 ir-4].each do |id|
        create(:catalog_control, control_family: family, control_id: id)
      end

      expect(described_class.for_catalog(catalog)).to eq(described_class::NIST_800_53)
    end

    # One familiar-looking identifier in someone else's catalog proves nothing.
    it "does NOT claim 800-53 from a single NIST-shaped id among others" do
      catalog = create(:control_catalog, name: "Vendor Control Set", source: "OSCAL")
      family  = create(:control_family, control_catalog: catalog, code: "ZZ")
      %w[ac-1 zz-1 zz-2 zz-3 zz-4].each do |id|
        create(:catalog_control, control_family: family, control_id: id)
      end

      expect(described_class.for_catalog(catalog)).to be_nil
    end

    it "falls back to the title when nothing structural says" do
      catalog = create(:control_catalog,
                       name: "Electronic (OSCAL) Version of NIST Special Publication 800-53 Rev 5.2.0",
                       source: "OSCAL")

      expect(described_class.for_catalog(catalog)).to eq(described_class::NIST_800_53)
    end

    it "returns nil when nothing says clearly" do
      catalog = create(:control_catalog, name: "Demo Catalog", source: "OSCAL")

      expect(described_class.for_catalog(catalog)).to be_nil
    end

    it "handles nil without raising" do
      expect(described_class.for_catalog(nil)).to be_nil
    end
  end

  describe ".for_profile" do
    # Lineage is a statement of fact; the title is an inference from a string.
    # A baseline whose own name says nothing still resolves through its catalog,
    # which is the case the owner described for a boundary's profile.
    it "inherits from the catalog it descends from, even when its own name is silent" do
      catalog = create(:control_catalog, name: "FedRAMP KSI", source: "FedRAMP 20x")
      profile = create(:profile_document, name: "Demo LOW Baseline", control_catalog: catalog)

      expect(described_class.for_profile(profile)).to eq(described_class::FEDRAMP_20X)
    end

    it "prefers lineage over its own title when the two disagree" do
      catalog = create(:control_catalog, name: "FedRAMP KSI", source: "FedRAMP 20x")
      profile = create(:profile_document, name: "NIST SP 800-53 Rev 5 LOW Baseline",
                       control_catalog: catalog)

      expect(described_class.for_profile(profile)).to eq(described_class::FEDRAMP_20X)
    end

    it "falls back to its own title when it links no catalog" do
      profile = create(:profile_document, name: "NIST SP 800-53 Rev 5 MODERATE Baseline",
                       control_catalog: nil)

      expect(described_class.for_profile(profile)).to eq(described_class::NIST_800_53)
    end

    # The real row on the dev estate: no catalog link, no framework in the name.
    it "returns nil for a baseline that names no framework and links no catalog" do
      profile = create(:profile_document, name: "Demo LOW Baseline", control_catalog: nil)

      expect(described_class.for_profile(profile)).to be_nil
    end

    it "handles nil without raising" do
      expect(described_class.for_profile(nil)).to be_nil
    end
  end
end
