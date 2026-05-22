require "rails_helper"

RSpec.describe DocumentTypeRegistry do
  describe ".for" do
    %i[ssp sar cdef profile sap poam].each do |key|
      it "returns an entry for #{key}" do
        entry = described_class.for(key)

        expect(entry).to respond_to(:document_class)
        expect(entry).to respond_to(:control_class)
        expect(entry).to respond_to(:allowed_extensions)
      end
    end

    it "returns SspDocument class for :ssp" do
      entry = described_class.for(:ssp)

      expect(entry.document_class).to eq(SspDocument)
    end

    it "raises for unknown key" do
      expect { described_class.for(:unknown) }.to raise_error(StandardError)
    end
  end

  describe "XLSX gate (#510)" do
    context "when SparcConfig.xlsx_uploads_enabled? is false (default)" do
      before { allow(SparcConfig).to receive(:xlsx_uploads_enabled?).and_return(false) }

      it "strips .xlsx and .xls from SSP allowed_extensions" do
        entry = described_class.for(:ssp)
        expect(entry.allowed_extensions).not_to have_key(".xlsx")
        expect(entry.allowed_extensions).not_to have_key(".xls")
      end

      it "strips .xlsx and .xls from SAR allowed_extensions" do
        entry = described_class.for(:sar)
        expect(entry.allowed_extensions).not_to have_key(".xlsx")
        expect(entry.allowed_extensions).not_to have_key(".xls")
      end

      it "leaves other extensions intact for SSP" do
        entry = described_class.for(:ssp)
        expect(entry.allowed_extensions).to include(".json", ".xml", ".yaml", ".yml")
      end

      it "does not affect non-XLSX-carrying types (CDEF)" do
        cdef = described_class.for(:cdef)
        expect(cdef.allowed_extensions.keys).to match_array([ ".xml", ".json", ".yaml", ".yml" ])
      end
    end

    context "when SparcConfig.xlsx_uploads_enabled? is true" do
      before { allow(SparcConfig).to receive(:xlsx_uploads_enabled?).and_return(true) }

      it "keeps .xlsx and .xls in SSP allowed_extensions" do
        entry = described_class.for(:ssp)
        expect(entry.allowed_extensions).to include(".xlsx" => "excel", ".xls" => "excel")
      end

      it "keeps .xlsx and .xls in SAR allowed_extensions" do
        entry = described_class.for(:sar)
        expect(entry.allowed_extensions).to include(".xlsx" => "excel", ".xls" => "excel")
      end
    end
  end
end
