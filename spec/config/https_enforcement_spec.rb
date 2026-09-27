# frozen_string_literal: true

require "rails_helper"

RSpec.describe "HTTPS enforcement configuration" do
  let(:probe) { Struct.new(:path) }

  # The `exclude: ->(request) { ... }` lambda, exactly as written in the file.
  def redirect_exclusion(source)
    body = source[/exclude:\s*(->\(request\)\s*\{[^}]*\})/, 1]
    raise "no redirect exclusion lambda found" unless body

    eval(body) # rubocop:disable Security/Eval -- our own config source, read from the repo
  end

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

    # #1151 — evaluated, not string-matched: the lambda is pulled out of the
    # config source and run, so a rewrite that keeps the behaviour passes and
    # one that loses a probe path (or excludes everything) fails.
    it "excludes both health probes, and nothing else, from SSL redirect" do
      exclude = redirect_exclusion(production_source)

      expect(exclude.call(probe.new("/up"))).to be(true)
      expect(exclude.call(probe.new("/up/ready"))).to be(true)
      expect(exclude.call(probe.new("/login"))).to be(false)
      expect(exclude.call(probe.new("/up/other"))).to be(false)
    end
  end

  describe "development environment" do
    let(:development_config_path) { Rails.root.join("config/environments/development.rb") }
    let(:development_source) { File.read(development_config_path) }

    it "does not unconditionally force SSL in development" do
      # force_ssl should only appear inside a conditional SSL_DEV block,
      # never as a top-level unconditional setting
      lines = development_source.lines
      force_ssl_lines = lines.select { |l| l.match?(/^\s+config\.force_ssl\s*=/) }
      force_ssl_lines.each do |line|
        idx = lines.index(line)
        preceding = lines[0...idx].reverse
        conditional = preceding.find { |l| l.match?(/if\s+ENV/) }
        expect(conditional).to include("SSL_DEV")
      end
    end

    it "does not configure HSTS in development" do
      expect(development_source).not_to include("hsts:")
    end
  end

  describe "development HTTPS (SSL_DEV)" do
    let(:puma_config_path) { Rails.root.join("config/puma.rb") }
    let(:puma_source) { File.read(puma_config_path) }
    let(:development_config_path) { Rails.root.join("config/environments/development.rb") }
    let(:development_source) { File.read(development_config_path) }

    it "conditionally enables SSL binding in Puma when SSL_DEV is true" do
      expect(puma_source).to include('ENV["SSL_DEV"] == "true"')
      expect(puma_source).to include("ssl_bind")
    end

    it "references mkcert certificate paths in Puma config" do
      expect(puma_source).to include("localhost+2.pem")
      expect(puma_source).to include("localhost+2-key.pem")
    end

    it "conditionally enables force_ssl in development when SSL_DEV is true" do
      expect(development_source).to include('ENV["SSL_DEV"] == "true"')
      expect(development_source).to include("config.force_ssl = true")
    end

    it "excludes both health probes, and nothing else, from SSL redirect in development" do
      exclude = redirect_exclusion(development_source)

      expect(exclude.call(probe.new("/up"))).to be(true)
      expect(exclude.call(probe.new("/up/ready"))).to be(true)
      expect(exclude.call(probe.new("/login"))).to be(false)
    end

    it "configures redirect port for non-standard HTTPS port" do
      expect(development_source).to include("SSL_PORT")
    end
  end

  describe "bin/setup-ssl" do
    let(:setup_ssl_path) { Rails.root.join("bin/setup-ssl") }

    it "exists and is executable" do
      expect(File.exist?(setup_ssl_path)).to be true
      expect(File.executable?(setup_ssl_path)).to be true
    end

    it "references mkcert for certificate generation" do
      source = File.read(setup_ssl_path)
      expect(source).to include("mkcert")
      expect(source).to include("localhost")
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
