# frozen_string_literal: true

require "rails_helper"

RSpec.describe "SparcConfig userdata derivation (#515)" do
  around do |ex|
    old_app_url  = ENV["SPARC_APP_URL"]
    old_userdata = ENV["SPARC_USERDATA_HOST"]
    ex.run
    ENV["SPARC_APP_URL"]       = old_app_url
    ENV["SPARC_USERDATA_HOST"] = old_userdata
  end

  describe ".userdata_host" do
    it "derives userdata.<host> from SPARC_APP_URL" do
      ENV["SPARC_APP_URL"]       = "https://sparc.example.org"
      ENV["SPARC_USERDATA_HOST"] = nil
      expect(SparcConfig.userdata_host).to eq("userdata.sparc.example.org")
    end

    it "honors SPARC_USERDATA_HOST override when set" do
      ENV["SPARC_APP_URL"]       = "https://sparc.example.org"
      ENV["SPARC_USERDATA_HOST"] = "blobs.tenant-a.example.org"
      expect(SparcConfig.userdata_host).to eq("blobs.tenant-a.example.org")
    end

    it "returns nil when SPARC_APP_URL is unparseable" do
      ENV["SPARC_APP_URL"]       = "not a url at all"
      ENV["SPARC_USERDATA_HOST"] = nil
      expect(SparcConfig.userdata_host).to be_nil
    end

    it "ignores empty SPARC_USERDATA_HOST and falls back to derivation" do
      ENV["SPARC_APP_URL"]       = "https://sparc.example.org"
      ENV["SPARC_USERDATA_HOST"] = ""
      expect(SparcConfig.userdata_host).to eq("userdata.sparc.example.org")
    end
  end

  describe ".userdata_protocol" do
    it "matches the scheme of SPARC_APP_URL" do
      ENV["SPARC_APP_URL"] = "https://sparc.example.org"
      expect(SparcConfig.userdata_protocol).to eq("https")

      ENV["SPARC_APP_URL"] = "http://localhost:3000"
      expect(SparcConfig.userdata_protocol).to eq("http")
    end

    it "defaults to https when SPARC_APP_URL is unparseable" do
      ENV["SPARC_APP_URL"] = "not a url"
      expect(SparcConfig.userdata_protocol).to eq("https")
    end
  end
end
