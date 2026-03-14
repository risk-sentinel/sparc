require "rails_helper"

RSpec.describe JsonExportService do
  describe ".export_ssp" do
    it "returns a JSON string" do
      ssp = create(:ssp_document)
      result = described_class.export_ssp(ssp)
      expect(result).to be_a(String)
      expect { JSON.parse(result) }.not_to raise_error
    end
  end

  describe ".export_sar" do
    it "returns a JSON string" do
      sar = create(:sar_document)
      result = described_class.export_sar(sar)
      expect(result).to be_a(String)
      expect { JSON.parse(result) }.not_to raise_error
    end
  end

  describe ".export_cdef" do
    it "returns a JSON string" do
      cdef = create(:cdef_document)
      result = described_class.export_cdef(cdef)
      expect(result).to be_a(String)
      expect { JSON.parse(result) }.not_to raise_error
    end
  end

  describe ".export_profile" do
    it "returns a JSON string" do
      profile = create(:profile_document)
      result = described_class.export_profile(profile)
      expect(result).to be_a(String)
      expect { JSON.parse(result) }.not_to raise_error
    end
  end

  describe ".export_sap" do
    it "returns a JSON string" do
      sap = create(:sap_document)
      result = described_class.export_sap(sap)
      expect(result).to be_a(String)
      expect { JSON.parse(result) }.not_to raise_error
    end
  end

  describe ".export_poam" do
    it "returns a JSON string" do
      poam = create(:poam_document)
      result = described_class.export_poam(poam)
      expect(result).to be_a(String)
      expect { JSON.parse(result) }.not_to raise_error
    end
  end
end
