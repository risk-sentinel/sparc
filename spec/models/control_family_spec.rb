require "rails_helper"

RSpec.describe ControlFamily, type: :model do
  describe "associations" do
    it "belongs to a control catalog" do
      family = build(:control_family)
      expect(family).to respond_to(:control_catalog)
    end

    it "has many catalog controls" do
      family = create(:control_family)
      expect(family).to respond_to(:catalog_controls)
    end

    it "destroys catalog controls when destroyed" do
      family = create(:control_family)
      family.catalog_controls.create!(control_id: "AC-01", title: "Test")
      expect { family.destroy }.to change(CatalogControl, :count).by(-1)
    end
  end

  describe "validations" do
    it "requires code" do
      family = build(:control_family, code: nil)
      expect(family).not_to be_valid
      expect(family.errors[:code]).to include("can't be blank")
    end

    it "requires name" do
      family = build(:control_family, name: nil)
      expect(family).not_to be_valid
      expect(family.errors[:name]).to include("can't be blank")
    end

    it "requires code to be unique within a catalog" do
      catalog = create(:control_catalog)
      create(:control_family, control_catalog: catalog, code: "AC")
      duplicate = build(:control_family, control_catalog: catalog, code: "AC")
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:code]).to include("has already been taken")
    end

    it "allows same code in different catalogs" do
      catalog1 = create(:control_catalog)
      catalog2 = create(:control_catalog)
      create(:control_family, control_catalog: catalog1, code: "AC")
      family = build(:control_family, control_catalog: catalog2, code: "AC")
      expect(family).to be_valid
    end

    it "requires code to be 2-5 uppercase letters" do
      family = build(:control_family, code: "A")
      expect(family).not_to be_valid

      family = build(:control_family, code: "ABCDEF")
      expect(family).not_to be_valid

      family = build(:control_family, code: "A1")
      expect(family).not_to be_valid
    end

    it "accepts valid codes" do
      family = build(:control_family, code: "AC")
      expect(family).to be_valid

      family = build(:control_family, code: "PLNNG")
      expect(family).to be_valid
    end
  end

  describe "code normalization" do
    it "upcases code before validation" do
      family = create(:control_family, code: "ac")
      expect(family.code).to eq("AC")
    end

    it "strips whitespace from code" do
      family = create(:control_family, code: " CM ")
      expect(family.code).to eq("CM")
    end
  end

  describe "auto sort_order" do
    it "auto-assigns sort_order on create when not provided" do
      catalog = create(:control_catalog)
      family1 = create(:control_family, control_catalog: catalog, code: "AC", sort_order: nil)
      family2 = create(:control_family, control_catalog: catalog, code: "AT", sort_order: nil)

      expect(family1.sort_order).to eq(1)
      expect(family2.sort_order).to eq(2)
    end

    it "preserves explicitly set sort_order" do
      catalog = create(:control_catalog)
      family = create(:control_family, control_catalog: catalog, code: "AC", sort_order: 10)
      expect(family.sort_order).to eq(10)
    end
  end

  describe "default_scope" do
    it "orders by sort_order then code" do
      catalog = create(:control_catalog)
      family_b = create(:control_family, control_catalog: catalog, code: "CM", sort_order: 2)
      family_a = create(:control_family, control_catalog: catalog, code: "AC", sort_order: 1)

      families = catalog.control_families
      expect(families.first).to eq(family_a)
      expect(families.last).to eq(family_b)
    end
  end

  describe "#total_controls" do
    it "returns the count of catalog controls" do
      family = create(:control_family)
      family.catalog_controls.create!(control_id: "AC-01", title: "First")
      family.catalog_controls.create!(control_id: "AC-02", title: "Second")

      expect(family.total_controls).to eq(2)
    end

    it "returns 0 for empty family" do
      family = create(:control_family)
      expect(family.total_controls).to eq(0)
    end
  end
end
