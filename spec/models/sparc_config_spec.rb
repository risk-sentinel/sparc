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

  describe "upload limit accessors (#510)" do
    around do |ex|
      old_mb = ENV["SPARC_MAX_UPLOAD_MB"]
      old_av = ENV["SPARC_MAX_AVATAR_MB"]
      ex.run
      ENV["SPARC_MAX_UPLOAD_MB"] = old_mb
      ENV["SPARC_MAX_AVATAR_MB"] = old_av
    end

    it "defaults max_upload_mb to 50" do
      ENV.delete("SPARC_MAX_UPLOAD_MB")
      expect(SparcConfig.max_upload_mb).to eq(50)
    end

    it "converts max_upload_mb to bytes via 1.megabyte" do
      ENV["SPARC_MAX_UPLOAD_MB"] = "10"
      expect(SparcConfig.max_upload_bytes).to eq(10 * 1.megabyte)
    end

    it "defaults max_avatar_mb to 2" do
      ENV.delete("SPARC_MAX_AVATAR_MB")
      expect(SparcConfig.max_avatar_mb).to eq(2)
    end

    it "converts max_avatar_mb to bytes" do
      ENV["SPARC_MAX_AVATAR_MB"] = "5"
      expect(SparcConfig.max_avatar_bytes).to eq(5 * 1.megabyte)
    end
  end

  describe ".xlsx_uploads_enabled? (#510)" do
    around do |ex|
      old = ENV["SPARC_ENABLE_XLSX_UPLOADS"]
      ex.run
      ENV["SPARC_ENABLE_XLSX_UPLOADS"] = old
    end

    it "defaults to false" do
      ENV.delete("SPARC_ENABLE_XLSX_UPLOADS")
      expect(SparcConfig.xlsx_uploads_enabled?).to be false
    end

    it "is true only when env var equals the literal string 'true'" do
      ENV["SPARC_ENABLE_XLSX_UPLOADS"] = "true"
      expect(SparcConfig.xlsx_uploads_enabled?).to be true
    end

    it "is false for any non-'true' value" do
      ENV["SPARC_ENABLE_XLSX_UPLOADS"] = "1"
      expect(SparcConfig.xlsx_uploads_enabled?).to be false
    end
  end
end
