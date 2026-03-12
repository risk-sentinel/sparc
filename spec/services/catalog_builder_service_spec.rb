require "rails_helper"

RSpec.describe CatalogBuilderService do
  describe "#build" do
    context "with blank template" do
      it "creates a catalog with no families" do
        catalog = described_class.new(name: "Custom Catalog").build

        expect(catalog).to be_persisted
        expect(catalog.name).to eq("Custom Catalog")
        expect(catalog.control_families).to be_empty
      end

      it "sets optional attributes" do
        catalog = described_class.new(
          name: "My Catalog",
          version: "2.0",
          source: "Custom",
          description: "A test catalog"
        ).build

        expect(catalog.version).to eq("2.0")
        expect(catalog.source).to eq("Custom")
        expect(catalog.description).to eq("A test catalog")
      end
    end

    context "with nist_families template" do
      it "creates a catalog with 20 NIST families" do
        catalog = described_class.new(
          name: "NIST Catalog",
          template: :nist_families
        ).build

        expect(catalog).to be_persisted
        expect(catalog.control_families.count).to eq(20)
      end

      it "includes all standard NIST family codes" do
        catalog = described_class.new(
          name: "NIST Catalog 2",
          template: :nist_families
        ).build

        codes = catalog.control_families.pluck(:code)
        expect(codes).to include("AC", "AT", "AU", "CA", "CM", "CP", "IA", "IR",
                                 "MA", "MP", "PE", "PL", "PM", "PS", "PT", "RA",
                                 "SA", "SC", "SI", "SR")
      end

      it "assigns correct names to families" do
        catalog = described_class.new(
          name: "NIST Catalog 3",
          template: :nist_families
        ).build

        ac_family = catalog.control_families.find_by(code: "AC")
        expect(ac_family.name).to eq("Access Control")

        si_family = catalog.control_families.find_by(code: "SI")
        expect(si_family.name).to eq("System and Information Integrity")
      end

      it "assigns sort_order to families" do
        catalog = described_class.new(
          name: "NIST Catalog 4",
          template: :nist_families
        ).build

        families = catalog.control_families.reorder(:sort_order)
        expect(families.first.code).to eq("AC")
        expect(families.last.code).to eq("SR")
      end
    end

    context "with string template parameter" do
      it "accepts string template values" do
        catalog = described_class.new(
          name: "String Template Test",
          template: "nist_families"
        ).build

        expect(catalog.control_families.count).to eq(20)
      end
    end

    context "validation" do
      it "allows duplicate catalog names" do
        described_class.new(name: "Duplicate Test").build

        expect {
          described_class.new(name: "Duplicate Test").build
        }.to change(ControlCatalog, :count).by(1)
      end

      it "raises on blank name" do
        expect {
          described_class.new(name: "").build
        }.to raise_error(ActiveRecord::RecordInvalid)
      end
    end

    context "transactionality" do
      it "rolls back families if catalog creation fails" do
        expect {
          begin
            described_class.new(name: "").build
          rescue ActiveRecord::RecordInvalid
            nil
          end
        }.not_to change(ControlFamily, :count)
      end
    end
  end

  describe "NIST_FAMILIES" do
    it "contains exactly 20 families" do
      expect(described_class::NIST_FAMILIES.size).to eq(20)
    end

    it "has unique codes" do
      codes = described_class::NIST_FAMILIES.map { |f| f[:code] }
      expect(codes.uniq.size).to eq(codes.size)
    end

    it "has sequential sort_order" do
      orders = described_class::NIST_FAMILIES.map { |f| f[:sort_order] }
      expect(orders).to eq((1..20).to_a)
    end
  end

  describe "TEMPLATES" do
    it "includes blank and nist_families" do
      expect(described_class::TEMPLATES).to eq([ :blank, :nist_families ])
    end
  end
end
