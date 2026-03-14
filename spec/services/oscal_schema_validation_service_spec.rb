require "rails_helper"

RSpec.describe OscalSchemaValidationService do
  describe ".available_schemas" do
    it "returns an array of available schemas" do
      schemas = described_class.available_schemas
      expect(schemas).to be_an(Array)
      expect(schemas).to include(:ssp)
    end
  end

  describe ".validate" do
    it "returns a Result with valid? and errors" do
      result = described_class.validate(:ssp, {})
      expect(result).to respond_to(:valid?)
      expect(result).to respond_to(:errors)
      expect(result.valid?).to be false
    end
  end
end
