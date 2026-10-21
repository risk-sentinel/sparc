# frozen_string_literal: true

require "rails_helper"

# The API refuses to boot on an authentication mode it cannot serve, with a
# named error (#1133) rather than a bare RuntimeError.
RSpec.describe "config/initializers/api_auth.rb" do
  let(:initializer) { Rails.root.join("config/initializers/api_auth.rb") }

  def with_env(vars)
    original = vars.keys.index_with { |k| ENV.fetch(k, nil) }
    vars.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
    yield
  ensure
    original.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
  end

  before do
    allow(Rails.application.config).to receive(:after_initialize) { |&block| block.call }
    allow(Rails.logger).to receive(:info)
  end

  it "refuses an unknown SPARC_API_AUTH" do
    with_env("SPARC_API_AUTH" => "magic") do
      expect { load initializer }.to raise_error(SparcConfig::ConfigurationError, /Invalid SPARC_API_AUTH value: "magic"/)
    end
  end

  it "refuses oidc without an issuer URL" do
    with_env("SPARC_API_AUTH" => "oidc", "SPARC_OIDC_ISSUER_URL" => nil) do
      expect { load initializer }
        .to raise_error(SparcConfig::ConfigurationError, /SPARC_API_AUTH=oidc requires SPARC_OIDC_ISSUER_URL/)
    end
  end

  it "starts in local mode and says which mode it is in" do
    with_env("SPARC_API_AUTH" => "local") do
      expect { load initializer }.not_to raise_error
      expect(Rails.logger).to have_received(:info).with("[SPARC] API authentication mode: local")
    end
  end
end
