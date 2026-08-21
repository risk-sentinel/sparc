# frozen_string_literal: true

require "rails_helper"

# #995 — the five disposition endpoints (#447, #809) had no test module at all,
# in rspec or in tests/api.
#
# A disposition is the decision to waive, defer or discount a scanner finding.
# It is the point at which a failing security check stops counting against a
# boundary, so "who may set one" and "who may approve one" are the whole point
# of the feature — and both were unasserted.
RSpec.describe "Api::V1 finding dispositions", type: :request do
  let(:boundary) { create(:authorization_boundary) }
  let(:scan_run) { create(:scan_run, authorization_boundary: boundary) }
  let(:finding) do
    create(:scanner_finding, scan_run: scan_run, authorization_boundary: boundary,
                             control_id: "ac-2", severity: "HIGH")
  end
  let(:path) { "/api/v1/scanner_findings/#{finding.uuid}/disposition" }

  let(:admin) { create(:user, :admin) }
  let(:admin_headers) do
    { "Authorization" => "Bearer #{ApiToken.generate!(user: admin, name: 'A').plaintext_token}" }
  end

  def headers_for(user)
    { "Authorization" => "Bearer #{ApiToken.generate!(user: user, name: SecureRandom.hex(4)).plaintext_token}" }
  end

  # Every kind requires a linked subject (LINKAGE in FindingDispositionService).
  # `inherited` links to an AuthorizationBoundary, which is the cheapest to make
  # and avoids the extra AO-attestation requirement `waiver` carries.
  let(:inherited_from) { create(:authorization_boundary) }

  def set_disposition(headers: admin_headers, kind: "inherited", reason: "Inherited from the platform",
                      subject_type: "AuthorizationBoundary", subject_id: nil)
    post path,
         params: { kind: kind, reason: reason,
                   linked_subject_type: subject_type,
                   linked_subject_id: subject_id || inherited_from.id },
         headers: headers, as: :json
  end

  before { allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true) }

  describe "POST .../disposition" do
    it "creates a disposition and reads back what was sent" do
      expect { set_disposition }.to change(FindingDisposition, :count).by(1)

      expect(response).to have_http_status(:created)
      data = response.parsed_body["data"]
      expect(data["kind"]).to eq("inherited")
      expect(data["reason"]).to eq("Inherited from the platform")
      expect(data["control_id"]).to eq(finding.control_id)
      expect(data["linked_subject_type"]).to eq("AuthorizationBoundary")
    end

    it "records who decided, so a disposition is attributable" do
      set_disposition

      expect(response.parsed_body["data"]["decided_by"]).to be_present
      expect(response.parsed_body["data"]["decided_at"]).to be_present
    end

    it "is an upsert — a second decision replaces the first rather than stacking" do
      set_disposition

      expect { set_disposition(reason: "Revised rationale") }
        .not_to change(FindingDisposition, :count)

      expect(FindingDisposition.last.reason).to eq("Revised rationale")
    end

    # Discovered writing this spec: every kind requires a linked subject, and
    # each kind requires a SPECIFIC one. A disposition is a claim that something
    # else justifies discounting the finding, so the justification has to exist.
    it "refuses a kind whose required linkage is missing, naming what it needs" do
      post path, params: { kind: "waiver", reason: "no link" }, headers: admin_headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to eq("waiver requires a linked Attestation")
    end

    it "refuses a linked subject of an unsupported type" do
      set_disposition(subject_type: "User", subject_id: admin.id)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to match(/Unsupported linked_subject_type/)
    end

    it "refuses a linked subject that does not exist" do
      set_disposition(subject_id: 0)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to match(/not found/i)
    end

    it "refuses an unknown kind by name" do
      set_disposition(kind: "notARealKind")

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to match(/kind/i)
    end

    it "refuses a caller without evidence.write on the boundary" do
      expect { set_disposition(headers: headers_for(create(:user))) }
        .not_to change(FindingDisposition, :count)

      expect(response).to have_http_status(:forbidden)
    end

    it "allows a caller who holds evidence.write on the boundary" do
      user = create(:user)
      grant_permission(user, "evidence.write", authorization_boundary: boundary)

      set_disposition(headers: headers_for(user))

      expect(response).to have_http_status(:created)
    end

    it "refuses an anonymous caller" do
      post path, params: { kind: "inherited", reason: "x",
                           linked_subject_type: "AuthorizationBoundary",
                           linked_subject_id: inherited_from.id }, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET .../disposition" do
    it "404s when no disposition has been set" do
      get path, headers: admin_headers

      expect(response).to have_http_status(:not_found)
    end

    it "returns the disposition once set" do
      set_disposition

      get path, headers: admin_headers

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["data"]["kind"]).to eq("inherited")
    end

    it "refuses a caller without evidence.read on the boundary" do
      set_disposition

      get path, headers: headers_for(create(:user))

      expect(response).to have_http_status(:forbidden)
    end

    it "allows a caller who holds evidence.read on the boundary" do
      set_disposition
      user = create(:user)
      grant_permission(user, "evidence.read", authorization_boundary: boundary)

      get path, headers: headers_for(user)

      expect(response).to have_http_status(:ok)
    end
  end

  describe "DELETE .../disposition" do
    it "removes the disposition, confirmed by an independent read" do
      set_disposition

      expect { delete path, headers: admin_headers }
        .to change(FindingDisposition, :count).by(-1)

      get path, headers: admin_headers
      expect(response).to have_http_status(:not_found)
    end

    it "404s when there is nothing to delete" do
      delete path, headers: admin_headers

      expect(response).to have_http_status(:not_found)
    end

    it "refuses a caller without evidence.write" do
      set_disposition

      expect { delete path, headers: headers_for(create(:user)) }
        .not_to change(FindingDisposition, :count)

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "POST .../disposition/approve and /reject (#809)" do
    let(:approver) do
      create(:user).tap { |u| grant_permission(u, "amendment.approve", authorization_boundary: boundary) }
    end

    it "approves, and the change is visible on an independent read" do
      set_disposition

      post "#{path}/approve", headers: headers_for(approver), as: :json
      expect(response).to have_http_status(:ok)

      get path, headers: admin_headers
      expect(response.parsed_body["data"]["approval_status"]).to eq("approved")
      expect(response.parsed_body["data"]["approved_by"]).to be_present
    end

    it "rejects, and the change is visible on an independent read" do
      set_disposition

      post "#{path}/reject", headers: headers_for(approver), as: :json
      expect(response).to have_http_status(:ok)

      get path, headers: admin_headers
      expect(response.parsed_body["data"]["approval_status"]).to eq("rejected")
    end

    it "404s when there is no disposition to approve" do
      post "#{path}/approve", headers: headers_for(approver), as: :json

      expect(response).to have_http_status(:not_found)
    end

    # #809 D5 — approval is a DISTINCT permission from setting a disposition.
    # evidence.write must not carry approval with it, or the separate permission
    # would mean nothing.
    it "refuses approval from a caller who holds only evidence.write" do
      set_disposition
      writer = create(:user)
      grant_permission(writer, "evidence.write", authorization_boundary: boundary)

      post "#{path}/approve", headers: headers_for(writer), as: :json

      expect(response).to have_http_status(:forbidden)
    end

    it "refuses approval from a caller with no permissions at all" do
      set_disposition

      post "#{path}/reject", headers: headers_for(create(:user)), as: :json

      expect(response).to have_http_status(:forbidden)
    end

    it "scopes the approve permission to the boundary" do
      set_disposition
      elsewhere = create(:user)
      grant_permission(elsewhere, "amendment.approve",
                       authorization_boundary: create(:authorization_boundary))

      post "#{path}/approve", headers: headers_for(elsewhere), as: :json

      expect(response).to have_http_status(:forbidden)
    end
  end
end
