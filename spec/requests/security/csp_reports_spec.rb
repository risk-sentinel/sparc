# frozen_string_literal: true

require "rails_helper"

# CSP violation report sink (#528, epic #650). The endpoint is a write-only
# beacon: it must accept reports without authentication or a CSRF token,
# always answer 204, and never raise on malformed input.
RSpec.describe "Security::CspReports", type: :request do
  let(:report_uri_envelope) do
    {
      "csp-report" => {
        "document-uri" => "https://sparc.example/cdef_documents/1",
        "violated-directive" => "script-src-attr",
        "effective-directive" => "script-src-attr",
        "blocked-uri" => "inline",
        "source-file" => "https://sparc.example/cdef_documents/1",
        "line-number" => 42,
        "disposition" => "enforce"
      }
    }.to_json
  end

  describe "POST /security/csp-violations" do
    it "accepts a report-uri envelope without auth or CSRF and returns 204" do
      post "/security/csp-violations",
           params: report_uri_envelope,
           headers: { "Content-Type" => "application/csp-report" }

      expect(response).to have_http_status(:no_content)
    end

    it "logs a structured csp_violation line with the violated directive" do
      expect(Rails.logger).to receive(:warn) do |line|
        expect(line).to include("csp_violation")
        expect(line).to include("script-src-attr")
        expect(line).to include("blocked-uri").or include("blocked_uri")
      end

      post "/security/csp-violations",
           params: report_uri_envelope,
           headers: { "Content-Type" => "application/csp-report" }
    end

    it "accepts a bare report object (no csp-report envelope)" do
      post "/security/csp-violations",
           params: { "violated-directive" => "img-src", "blocked-uri" => "https://evil.example" }.to_json,
           headers: { "Content-Type" => "application/json" }

      expect(response).to have_http_status(:no_content)
    end

    it "tolerates malformed JSON without raising" do
      post "/security/csp-violations",
           params: "not-json{{{",
           headers: { "Content-Type" => "application/csp-report" }

      expect(response).to have_http_status(:no_content)
    end

    it "tolerates an empty body" do
      post "/security/csp-violations",
           params: "",
           headers: { "Content-Type" => "application/csp-report" }

      expect(response).to have_http_status(:no_content)
    end
  end
end
