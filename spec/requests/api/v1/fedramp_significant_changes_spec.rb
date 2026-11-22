# frozen_string_literal: true

require "rails_helper"

# #1390 — /api/v1/authorization_boundaries/:id/fedramp_significant_changes and
# .../fedramp_incidents.
RSpec.describe "API v1 FedRAMP significant changes and incidents", type: :request do
  let(:boundary) { create(:authorization_boundary, :fedramp, fedramp_package_overview_uri: "https://trust.example/cpo.json") }
  let(:base) { "/api/v1/authorization_boundaries/#{boundary.id}" }

  def headers_for(user)
    { "Authorization" => "Bearer #{ApiToken.generate!(user: user, name: SecureRandom.hex(4)).plaintext_token}" }
  end

  def user_with(permissions, on: boundary)
    user = create(:user)
    role = create(:role, :authorization_boundary_scoped, permissions: permissions)
    create(:user_role, user: user, role: role, authorization_boundary_id: on.id)
    user
  end

  before { allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true) }

  describe "significant changes" do
    let(:writer) { headers_for(user_with({ "evidence.read" => true, "evidence.write" => true })) }
    let(:path) { "#{base}/fedramp_significant_changes" }

    it "records a change (201), updates only the fields sent, and lists it with its deadlines" do
      post path, params: { fedramp_significant_change: { change_type: "Transformative", description: "New region",
                                                         plan_summary: "Phased", planned_start: "2027-01-15",
                                                         impacted_controls: %w[sc-7 KSI-CNA-RNT] } },
                 headers: writer, as: :json
      expect(response).to have_http_status(:created)
      uuid = response.parsed_body.dig("data", "uuid")
      expect(response.parsed_body.dig("data", "deadlines").first).to include("stage" => "initial_plans",
                                                                             "rule_id" => "SCN-TRF-NIP",
                                                                             "due_on" => "2026-12-02", "timeframe" => [ "bizdays", 30 ])

      put "#{path}/#{uuid}", params: { fedramp_significant_change: { reason: "Capacity" } }, headers: writer, as: :json
      expect(response.parsed_body["data"]).to include("reason" => "Capacity", "description" => "New region")

      get path, headers: writer
      expect(response.parsed_body["meta"]).to eq("total" => 1, "notifiable" => 1)
      expect(AuditEvent.where(action: "fedramp_significant_change_recorded").count).to eq(2)
    end

    it "returns the notification and records a notice, 422 for a routine change or an unknown field" do
      change = FedrampSignificantChangeService.new(boundary).record(
        attributes: { change_type: "Adaptive", description: "Dashboard", finished_on: "2026-11-20" }, user: nil
      ).change
      get "#{path}/#{change.uuid}/notification", headers: writer
      expect(response.parsed_body).to include("changeType" => "Adaptive", "changeDescription" => "Dashboard")

      post "#{path}/#{change.uuid}/notices", params: { notice: { stage: "after_finish", sent_on: Date.current.iso8601 } },
                                              headers: writer, as: :json
      expect(response).to have_http_status(:created)
      expect(response.parsed_body.dig("data", "notices").sole).to include("stage" => "after_finish")
      expect(response.parsed_body.dig("data", "notices").sole).not_to have_key("document")

      routine = FedrampSignificantChangeService.new(boundary).record(
        attributes: { change_type: "Routine", description: "Patching" }, user: nil
      ).change
      get "#{path}/#{routine.uuid}/notification", headers: writer
      expect(response).to have_http_status(:unprocessable_content)

      post path, params: { fedramp_significant_change: { change_type: "Adaptive", description: "x", owner: "y" } },
                 headers: writer, as: :json
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "403s a reader on POST, 404s another boundary's change, and 422s while FedRAMP is off" do
      reader = headers_for(user_with({ "evidence.read" => true }))
      post path, params: { fedramp_significant_change: { change_type: "Adaptive", description: "x" } }, headers: reader, as: :json
      expect(response).to have_http_status(:forbidden)

      other = create(:authorization_boundary, :fedramp)
      change = FedrampSignificantChangeService.new(other).record(attributes: { change_type: "Routine", description: "x" }, user: nil).change
      get "#{path}/#{change.uuid}", headers: headers_for(create(:user, :admin))
      expect(response).to have_http_status(:not_found)

      boundary.update!(fedramp_enabled: false)
      get path, headers: reader
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "incidents" do
    let(:responder) { headers_for(user_with({ "incident.read" => true, "incident.write" => true })) }
    let(:path) { "#{base}/fedramp_incidents" }

    it "records an incident with lists and a rating, returns its deadlines, a report, and records a report sent" do
      post path, params: { fedramp_incident: { tracking_id: "INC-1", evaluation_completed_at: 1.hour.ago.utc.iso8601,
                                               current_rating: 3, affected_agencies: %w[DHS], related_cve_ids: %w[CVE-2026-1234],
                                               milestones: [ { occurred_at: 2.hours.ago.utc.iso8601, description: "Detected" } ] } },
                 headers: responder, as: :json
      expect(response).to have_http_status(:created)
      data = response.parsed_body["data"]
      expect(data).to include("tracking_id" => "INC-1", "current_rating" => 3, "affected_agencies" => %w[DHS])
      expect(data["deadlines"].map { |d| d["report_type"] }).to eq(%w[Initial Ongoing Final])
      expect(data["deadlines"].first).to include("rule_id" => "IEC-CSO-IIR", "force" => "MUST", "timeframe" => [ "hours", 6 ])

      get "#{path}/#{data['uuid']}/report", params: { type: "Initial" }, headers: responder
      expect(response.parsed_body).to include("reportType" => "Initial", "relatedCveIds" => %w[CVE-2026-1234])

      post "#{path}/#{data['uuid']}/reports", params: { report: { report_type: "Initial", sent_at: Time.current.utc.iso8601 } },
                                               headers: responder, as: :json
      expect(response).to have_http_status(:created)
      expect(response.parsed_body.dig("data", "reports").sole).to include("report_type" => "Initial")

      get "#{path}/#{data['uuid']}/report", params: { type: "Final" }, headers: responder
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to include("resolved")
    end

    it "is closed to evidence.* holders and to a reader writing" do
      evidence = headers_for(user_with({ "evidence.read" => true, "evidence.write" => true }))
      get path, headers: evidence
      expect(response).to have_http_status(:forbidden)

      reader = headers_for(user_with({ "incident.read" => true }))
      get path, headers: reader
      expect(response).to have_http_status(:ok)
      post path, params: { fedramp_incident: { tracking_id: "INC-2" } }, headers: reader, as: :json
      expect(response).to have_http_status(:forbidden)
    end
  end
end
