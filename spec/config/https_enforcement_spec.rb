# frozen_string_literal: true

require "rails_helper"

RSpec.describe "HTTPS enforcement configuration" do
  describe "production environment" do
    let(:production_config_path) { Rails.root.join("config/environments/production.rb") }
    let(:production_source) { File.read(production_config_path) }

    it "enables force_ssl by default" do
      expect(production_source).to include('config.force_ssl = ENV.fetch("FORCE_SSL", "true") == "true"')
    end

    it "assumes SSL for reverse-proxy deployments" do
      expect(production_source).to include("config.assume_ssl = true")
    end

    it "configures HSTS with preload and subdomains" do
      expect(production_source).to include("preload: true")
      expect(production_source).to include("subdomains: true")
      expect(production_source).to include("expires: 1.year")
    end

    it "excludes the /up health-check path from SSL redirect" do
      expect(production_source).to include('request.path == "/up"')
    end
  end

  describe "development environment" do
    let(:development_config_path) { Rails.root.join("config/environments/development.rb") }
    let(:development_source) { File.read(development_config_path) }

    it "does not force SSL in development" do
      expect(development_source).not_to include("config.force_ssl")
    end
  end

  describe "SparcConfig.force_ssl?" do
    it "defaults to true when FORCE_SSL env var is not set" do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with("FORCE_SSL", "true").and_return("true")
      expect(SparcConfig.force_ssl?).to be true
    end

    it "returns false when FORCE_SSL=false" do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with("FORCE_SSL", "true").and_return("false")
      expect(SparcConfig.force_ssl?).to be false
    end
  end
end
