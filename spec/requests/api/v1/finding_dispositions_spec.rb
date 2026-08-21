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

    # #1034 — a disposition is the decision that a failing scanner finding stops
    # counting against a boundary. One person could waive a HIGH finding and
    # sign off on their own waiver, and the record showed a completed two-stage
    # approval. `DocumentApprovalService` has refused self-approval since it was
    # written; this had no equivalent.
    describe "separation of duties" do
      let(:decider) do
        create(:user).tap do |u|
          grant_permission(u, "evidence.write",    authorization_boundary: boundary)
          grant_permission(u, "amendment.approve", authorization_boundary: boundary)
        end
      end

      it "refuses approval by the person who decided it" do
        set_disposition(headers: headers_for(decider))
        expect(response).to have_http_status(:created)

        post "#{path}/approve", headers: headers_for(decider), as: :json

        expect(response).to have_http_status(:forbidden)
        expect(response.parsed_body["error"]).to match(/person who decided it/i)
      end

      it "refuses rejection by the person who decided it" do
        set_disposition(headers: headers_for(decider))

        post "#{path}/reject", headers: headers_for(decider), as: :json

        expect(response).to have_http_status(:forbidden)
      end

      it "leaves the disposition unapproved when it refuses" do
        set_disposition(headers: headers_for(decider))

        post "#{path}/approve", headers: headers_for(decider), as: :json

        get path, headers: admin_headers
        expect(response.parsed_body["data"]["approval_status"]).to eq("draft")
        expect(response.parsed_body["data"]["approved_by"]).to be_nil
      end

      it "allows a DIFFERENT holder of amendment.approve" do
        set_disposition(headers: headers_for(decider))

        post "#{path}/approve", headers: headers_for(approver), as: :json

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body["data"]["approval_status"]).to eq("approved")
      end

      # Compared by user id, not by `decided_by`, which is a display name.
      it "distinguishes two users who share a display name" do
        twin = create(:user, display_name: decider.display_name)
        grant_permission(twin, "amendment.approve", authorization_boundary: boundary)
        set_disposition(headers: headers_for(decider))

        post "#{path}/approve", headers: headers_for(twin), as: :json

        expect(response).to have_http_status(:ok),
          "the guard compared names, so a different user was mistaken for the decider"
      end

      it "records the approver identity, not only their name" do
        set_disposition(headers: headers_for(decider))

        post "#{path}/approve", headers: headers_for(approver), as: :json

        expect(FindingDisposition.last.approved_by_user_id).to eq(approver.id)
        expect(FindingDisposition.last.decided_by_user_id).to eq(decider.id)
      end

      # Mirrors DocumentApprovalService, which exempts admins. Called out on
      # #1034 as the owner's call rather than assumed.
      it "still permits an admin to self-approve, as documents do" do
        set_disposition(headers: admin_headers)

        post "#{path}/approve", headers: admin_headers, as: :json

        expect(response).to have_http_status(:ok)
      end

      # Every row written before the column existed has a NULL decider id and
      # was deliberately not backfilled by matching names.
      it "does not fire on a row whose decider identity was never recorded" do
        set_disposition(headers: headers_for(decider))
        FindingDisposition.last.update_columns(decided_by_user_id: nil)

        post "#{path}/approve", headers: headers_for(decider), as: :json

        expect(response).to have_http_status(:ok)
      end

      it "re-opens approval when the disposition is edited" do
        set_disposition(headers: headers_for(decider))
        post "#{path}/approve", headers: headers_for(approver), as: :json
        expect(response.parsed_body["data"]["approval_status"]).to eq("approved")

        set_disposition(headers: headers_for(decider), reason: "Revised")

        get path, headers: admin_headers
        expect(response.parsed_body["data"]["approval_status"]).to eq("draft")
        expect(FindingDisposition.last.approved_by_user_id).to be_nil
      end
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
