# frozen_string_literal: true

require "rails_helper"

# #1354 / #1384 — the provider's FedRAMP evaluation of each vulnerability
# (VER-EVA-EIR, VER-EVA-ELX, VER-EVA-EPA, VER-RPT-VDT), keyed by control_id.
RSpec.describe "Api::V1 FedRAMP evaluations", type: :request do
  let(:boundary) { create(:authorization_boundary, :fedramp) }
  let(:scan_run) { create(:scan_run, authorization_boundary: boundary) }
  let!(:finding) do
    create(:scanner_finding, :failed, scan_run: scan_run, authorization_boundary: boundary,
                                      control_id: "CVE-2026-0001", severity: "HIGH")
  end
  let(:base) { "/api/v1/authorization_boundaries/#{boundary.id}/fedramp_evaluations" }
  let(:path) { "#{base}/CVE-2026-0001" }
  let(:admin) { create(:user, :admin) }

  def headers_for(user)
    { "Authorization" => "Bearer #{ApiToken.generate!(user: user, name: SecureRandom.hex(4)).plaintext_token}" }
  end

  let(:admin_headers) { headers_for(admin) }

  def record(fields, url: path, headers: admin_headers)
    put url, params: { fedramp_evaluation: fields }, headers: headers, as: :json
  end

  before { allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true) }

  describe "PUT .../fedramp_evaluations/:control_id" do
    it "creates the evaluation (201), then updates it (200)" do
      record({ internet_reachable: true, likely_exploitable: false, pain_rating: 3 })
      expect(response).to have_http_status(:created)
      data = response.parsed_body["data"]
      expect(data).to include("control_id" => "CVE-2026-0001", "evaluated" => true, "internet_reachable" => true,
                              "likely_exploitable" => false, "pain_rating" => 3, "pain_label" => "N3")
      expect(data["evaluated_at"]).to be_present
      expect(data["evaluated_by"]).to include("id" => admin.id)
      expect(data["detected_at"]).to eq(finding.created_at.utc.iso8601)

      record({ supplementary_info: "WAF rule blocks the payload" })
      expect(response).to have_http_status(:ok)
      expect(FedrampVulnerabilityEvaluation.count).to eq(1)
      evaluation = FedrampVulnerabilityEvaluation.sole
      # Only the field sent changed.
      expect(evaluation).to have_attributes(supplementary_info: "WAF rule blocks the payload",
                                            internet_reachable: true, pain_rating: 3)
    end

    it "sets evaluated_at to now on the first evaluation and keeps it after" do
      record({ pain_rating: 2 })
      first = FedrampVulnerabilityEvaluation.sole.evaluated_at
      expect(first).to be_within(5.seconds).of(Time.current)

      FedrampVulnerabilityEvaluation.sole.update_columns(evaluated_at: 1.day.ago)
      record({ pain_rating: 1, evaluated_at: "" })
      expect(FedrampVulnerabilityEvaluation.sole.evaluated_at).to be_within(1.second).of(1.day.ago)
    end

    it "takes the evaluated_at the caller names" do
      record({ pain_rating: 2, evaluated_at: "2026-11-01T09:30:00Z" })
      expect(response.parsed_body.dig("data", "evaluated_at")).to eq("2026-11-01T09:30:00Z")
    end

    it "records each change of N-rating in pain_history, and a fall as a reduction" do
      record({ pain_rating: 4 })
      record({ pain_rating: 4, supplementary_info: "unchanged rating" })
      record({ pain_rating: 2 })

      data = response.parsed_body["data"]
      expect(data["pain_history"].map { |h| h["rating"] }).to eq([ 4, 2 ])
      expect(data["pain_history"]).to all(include("at"))
      expect(data["pain_reductions"].map { |h| h["rating"] }).to eq([ 2 ])
    end

    it "records the planned next reduction when it is lower than the current N-rating" do
      record({ pain_rating: 3, next_reduction_rating: 1, next_reduction_at: "2026-12-15" })
      expect(response).to have_http_status(:created)
      expect(response.parsed_body["data"]).to include("next_reduction_rating" => 1)
      expect(response.parsed_body.dig("data", "next_reduction_at")).to start_with("2026-12-15")
    end

    it "refuses a next reduction that is not lower (422)" do
      record({ pain_rating: 2, next_reduction_rating: 2 })
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to match(/lower than the current N-rating/)
      expect(FedrampVulnerabilityEvaluation.count).to eq(0)
    end

    it "refuses an N-rating outside N0–N5 (422)" do
      record({ pain_rating: 6 })
      expect(response).to have_http_status(:unprocessable_content)
      record({ pain_rating: "high" })
      expect(response).to have_http_status(:unprocessable_content)
      expect(FedrampVulnerabilityEvaluation.count).to eq(0)
    end

    it "refuses a value that is not a yes or no (422)" do
      record({ internet_reachable: "maybe" })
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to match(/internet_reachable must be true or false/)
    end

    it "refuses a control the boundary has no failing finding for (422)" do
      record({ pain_rating: 1 }, url: "#{base}/CVE-NOT-HERE")
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to match(/no failing finding for CVE-NOT-HERE/)

      create(:scanner_finding, :passed, scan_run: scan_run, authorization_boundary: boundary, control_id: "PASSING-1")
      record({ pain_rating: 1 }, url: "#{base}/PASSING-1")
      expect(response).to have_http_status(:unprocessable_content)
      expect(FedrampVulnerabilityEvaluation.count).to eq(0)
    end

    it "refuses a field it does not know, changing nothing (422)" do
      record({ pain_rating: 1, severity: "LOW" })
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["details"]).to include("Unrecognized field: severity")
      expect(FedrampVulnerabilityEvaluation.count).to eq(0)
    end

    it "accepts a flat JSON body" do
      put path, params: { pain_rating: 1 }, headers: admin_headers, as: :json
      expect(response).to have_http_status(:created)
    end

    it "addresses control ids with dots and percent-encoded slashes" do
      %w[xccdf_org.example_rule_audit-enabled pkg:gem/rack@2.0.0].each do |control_id|
        create(:scanner_finding, :failed, scan_run: scan_run, authorization_boundary: boundary, control_id: control_id)
        record({ pain_rating: 1 }, url: "#{base}/#{ERB::Util.url_encode(control_id)}")
        expect(response).to have_http_status(:created), "#{control_id}: #{response.body}"
        expect(response.parsed_body.dig("data", "control_id")).to eq(control_id)

        get "#{base}/#{ERB::Util.url_encode(control_id)}", headers: admin_headers
        expect(response.parsed_body.dig("data", "control_id")).to eq(control_id)
      end
    end

    it "audits fedramp_evaluation_recorded" do
      expect { record({ pain_rating: 2 }) }
        .to change { AuditEvent.where(action: "fedramp_evaluation_recorded").count }.by(1)
      event = AuditEvent.where(action: "fedramp_evaluation_recorded").last
      expect(event.metadata).to include("control_id" => "CVE-2026-0001", "created" => true, "pain_rating" => 2)
    end

    it "refuses a caller without evidence.write on the boundary (403)" do
      reader = create(:user)
      grant_permission(reader, "evidence.read", authorization_boundary: boundary)

      expect { record({ pain_rating: 1 }, headers: headers_for(reader)) }
        .not_to change(FedrampVulnerabilityEvaluation, :count)
      expect(response).to have_http_status(:forbidden)
    end

    it "refuses evidence.write held on a different boundary (403)" do
      writer = create(:user)
      grant_permission(writer, "evidence.write", authorization_boundary: create(:authorization_boundary))

      record({ pain_rating: 1 }, headers: headers_for(writer))
      expect(response).to have_http_status(:forbidden)
    end

    it "allows a caller who holds evidence.write on the boundary" do
      writer = create(:user)
      grant_permission(writer, "evidence.write", authorization_boundary: boundary)

      record({ pain_rating: 1 }, headers: headers_for(writer))
      expect(response).to have_http_status(:created)
    end
  end

  describe "GET .../fedramp_evaluations" do
    before do
      create(:scanner_finding, :failed, scan_run: scan_run, authorization_boundary: boundary, control_id: "CVE-2026-0002")
      FedrampVulnerabilityEvaluation.create!(authorization_boundary: boundary, control_id: "CVE-2026-0001",
                                             pain_rating: 3, evaluated_at: Time.current)
    end

    it "lists the boundary's evaluations" do
      get base, headers: admin_headers
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["data"].map { |d| d["control_id"] }).to eq([ "CVE-2026-0001" ])
      expect(response.parsed_body["meta"]).to include("count" => 1)
    end

    it "lists the current failing findings not yet evaluated, with ?unevaluated=true" do
      get base, params: { unevaluated: "true" }, headers: admin_headers
      data = response.parsed_body["data"]
      expect(data.map { |d| d["control_id"] }).to eq([ "CVE-2026-0002" ])
      expect(data.first).to include("evaluated" => false, "pain_rating" => nil, "id" => nil)
      expect(data.first["detected_at"]).to be_present
    end

    it "refuses a caller without evidence.read (403)" do
      get base, headers: headers_for(create(:user))
      expect(response).to have_http_status(:forbidden)
    end

    it "allows a caller who holds evidence.read on the boundary" do
      reader = create(:user)
      grant_permission(reader, "evidence.read", authorization_boundary: boundary)
      get base, headers: headers_for(reader)
      expect(response).to have_http_status(:ok)
    end

    it "addresses the boundary by slug" do
      get "/api/v1/authorization_boundaries/#{boundary.slug}/fedramp_evaluations", headers: admin_headers
      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET .../fedramp_evaluations/:control_id" do
    it "shows an evaluation" do
      record({ pain_rating: 3 })
      get path, headers: admin_headers
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["data"]).to include("pain_rating" => 3, "evaluated" => true)
    end

    it "shows a detected vulnerability not yet evaluated as evaluated: false" do
      get path, headers: admin_headers
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["data"]).to include("evaluated" => false, "control_id" => "CVE-2026-0001")
    end

    it "is 404 for a control with no failing finding and no evaluation" do
      get "#{base}/CVE-NOT-HERE", headers: admin_headers
      expect(response).to have_http_status(:not_found)
    end

    it "refuses a caller without evidence.read (403)" do
      get path, headers: headers_for(create(:user))
      expect(response).to have_http_status(:forbidden)
    end
  end
end
