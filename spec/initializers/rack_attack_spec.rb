# frozen_string_literal: true

require "rails_helper"
require "rack/test"

# Test Rack::Attack at the middleware level against a synthetic Rack app.
# This bypasses Rails routing + authentication so we're testing the
# throttle behavior in isolation. The actual middleware reads request
# attributes (ip, method, path, Authorization header) the same way
# whether mounted in front of Rails or a Sinatra-style hello-world.
RSpec.describe "Rack::Attack initializer (#513)" do
  include Rack::Test::Methods

  # The initializer disables Rack::Attack in Rails.env.test?; this spec
  # flips it back on per-example and uses an in-memory cache so throttle
  # counters don't bleed across examples or across parallel processes.
  before do
    @original_enabled     = Rack::Attack.enabled
    @original_cache_store = Rack::Attack.cache.store
    Rack::Attack.enabled         = true
    Rack::Attack.cache.store     = ActiveSupport::Cache::MemoryStore.new
    Rack::Attack.reset!
  end

  after do
    Rack::Attack.enabled     = @original_enabled
    Rack::Attack.cache.store = @original_cache_store
    Rack::Attack.reset!
  end

  # Minimal Rack app: Rack::Attack middleware in front of a hello-world
  # endpoint. If Rack::Attack throttles, we get 429; otherwise 200.
  let(:app) do
    Rack::Builder.new do
      use Rack::Attack
      run ->(_env) { [ 200, { "Content-Type" => "text/plain" }, [ "ok" ] ] }
    end
  end

  describe "uploads/5min/ip throttle" do
    before { allow(SparcConfig).to receive(:rate_limit_uploads_per_5min_per_ip).and_return(2) }

    it "allows requests under the limit" do
      2.times do
        post "/cdef_documents", {}, { "REMOTE_ADDR" => "203.0.113.7" }
        expect(last_response.status).to eq(200)
      end
    end

    it "returns 429 with bucket + Retry-After when exceeded" do
      3.times do
        post "/cdef_documents", {}, { "REMOTE_ADDR" => "203.0.113.8" }
      end
      expect(last_response.status).to eq(429)
      expect(last_response.headers["Retry-After"]).to be_present
      expect(last_response.headers["X-RateLimit-Bucket"]).to eq("uploads/5min/ip")

      body = JSON.parse(last_response.body)
      expect(body["code"]).to eq("rate_limit_exceeded")
      expect(body["bucket"]).to eq("uploads/5min/ip")
      expect(body["retry_after"]).to be > 0
    end

    it "does not match non-upload paths" do
      5.times do
        get "/some/other/path", {}, { "REMOTE_ADDR" => "203.0.113.9" }
      end
      expect(last_response.status).to eq(200)
    end
  end

  describe "api/writes/min/token throttle" do
    before { allow(SparcConfig).to receive(:rate_limit_api_writes_per_minute).and_return(2) }

    it "throttles per-token after the cap" do
      headers = { "HTTP_AUTHORIZATION" => "Bearer abc123def456_token_xyz" }
      3.times do
        post "/api/v1/ssp_documents", {}, headers.merge("REMOTE_ADDR" => "203.0.113.10")
      end
      expect(last_response.status).to eq(429)
      expect(last_response.headers["X-RateLimit-Bucket"]).to eq("api/writes/min/token")
    end

    it "does not throttle requests without a Bearer token (discriminator nil)" do
      5.times do
        post "/api/v1/ssp_documents", {}, { "REMOTE_ADDR" => "203.0.113.11" }
      end
      expect(last_response.status).to eq(200)
    end

    it "does not match read-method API requests" do
      headers = { "HTTP_AUTHORIZATION" => "Bearer abc123def456_token_xyz" }
      5.times do
        get "/api/v1/ssp_documents", {}, headers.merge("REMOTE_ADDR" => "203.0.113.12")
      end
      expect(last_response.status).to eq(200)
    end
  end

  describe "logins/failures/min/ip throttle" do
    before { allow(SparcConfig).to receive(:rate_limit_login_failures_per_minute).and_return(2) }

    it "returns 429 after the failure cap" do
      3.times do
        post "/login", { email: "nope@example.com", password: "wrong" }, { "REMOTE_ADDR" => "198.51.100.1" }
      end
      expect(last_response.status).to eq(429)
      expect(last_response.headers["X-RateLimit-Bucket"]).to eq("logins/failures/min/ip")
    end

    it "also matches POST /auth/failure" do
      3.times do
        post "/auth/failure", {}, { "REMOTE_ADDR" => "198.51.100.2" }
      end
      expect(last_response.status).to eq(429)
    end
  end

  describe "safelist" do
    before do
      allow(SparcConfig).to receive(:rate_limit_safelist_cidrs).and_return([ "10.0.0.0/8" ])
      allow(SparcConfig).to receive(:rate_limit_uploads_per_5min_per_ip).and_return(1)
    end

    it "bypasses throttles for safelisted CIDR" do
      5.times do
        post "/cdef_documents", {}, { "REMOTE_ADDR" => "10.5.6.7" }
      end
      expect(last_response.status).to eq(200)
    end

    it "still throttles non-safelisted CIDR" do
      2.times do
        post "/cdef_documents", {}, { "REMOTE_ADDR" => "192.0.2.1" }
      end
      expect(last_response.status).to eq(429)
    end

    it "tolerates malformed CIDR entries (skips them)" do
      allow(SparcConfig).to receive(:rate_limit_safelist_cidrs).and_return([ "not-a-cidr", "10.0.0.0/8" ])
      expect { post "/cdef_documents", {}, { "REMOTE_ADDR" => "10.5.6.7" } }.not_to raise_error
      expect(last_response.status).to eq(200)
    end
  end

  describe "operator kill switch" do
    it "exposes SparcConfig.rate_limiting_enabled? for the initializer" do
      expect(SparcConfig).to respond_to(:rate_limiting_enabled?)
    end

    it "defaults to true" do
      ENV.delete("SPARC_RATE_LIMITING_ENABLED")
      expect(SparcConfig.rate_limiting_enabled?).to be true
    end

    it "is false when SPARC_RATE_LIMITING_ENABLED=false" do
      original = ENV["SPARC_RATE_LIMITING_ENABLED"]
      ENV["SPARC_RATE_LIMITING_ENABLED"] = "false"
      expect(SparcConfig.rate_limiting_enabled?).to be false
    ensure
      ENV["SPARC_RATE_LIMITING_ENABLED"] = original
    end
  end
end
