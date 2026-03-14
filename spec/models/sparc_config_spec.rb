require "rails_helper"

RSpec.describe SparcConfig do
  describe ".VERSION" do
    it "returns a version string" do
      expect(SparcConfig::VERSION).to be_a(String)
      expect(SparcConfig::VERSION).to match(/\d+\.\d+\.\d+/)
    end
  end

  describe ".any_auth_enabled?" do
    it "returns a boolean" do
      expect(SparcConfig.any_auth_enabled?).to be_in([ true, false ])
    end
  end

  describe ".app_name" do
    it "returns a string" do
      expect(SparcConfig.app_name).to be_a(String)
    end
  end
end
