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
end
