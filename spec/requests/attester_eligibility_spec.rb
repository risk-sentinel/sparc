# frozen_string_literal: true

require "rails_helper"

# #981 — the JSON the evidence attester picker calls when the boundary changes.
#
# The form used to compute the eligible set once, for the boundary the page was
# rendered with. Loading /evidences/new with no boundary computes options for
# instance-wide evidence, which legitimately includes instance-scoped attesting
# roles (`policy_manager`); pick a boundary, pick that role, and the server
# correctly refused a pair the form had just offered.
#
# The asymmetry is deliberate (#947) and this endpoint has to preserve it: an
# instance grant satisfies `has_permission?` on EVERY boundary, so Policy may
# attest to provider material belonging to no system, but must not thereby gain
# authority over an individual system's evidence.
RSpec.describe "Attester eligibility (#981)", type: :request do
  # Declared here rather than inherited from the environment. CI configures no
  # auth method, so a spec that relies on .env has its permission gate
  # short-circuit and asserts nothing — the trap that made twelve Bundle P
  # specs vacuous.
  before { allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true) }

  let(:boundary)       { create(:authorization_boundary) }
  let(:other_boundary) { create(:authorization_boundary) }

  let(:policy_role) do
    create(:role, name: "policy_manager", display_name: "Policy Manager",
                  scope: "instance", permissions: { "evidence.attest" => true })
  end

  let(:isso_role) do
    create(:role, :authorization_boundary_scoped, name: "isso", display_name: "ISSO",
                  permissions: { "evidence.attest" => true })
  end

  let(:policy_user) { create(:user, email: "policy@example.gov") }
  let(:isso_user)   { create(:user, email: "isso@example.gov") }

  let(:admin) { create(:user, :admin) }

  before do
    create(:user_role, user: policy_user, role: policy_role, authorization_boundary: nil)
    create(:user_role, user: isso_user, role: isso_role, authorization_boundary: boundary)
  end

  def payload
    JSON.parse(response.body).fetch("data")
  end

  def role_names_for(user)
    payload.fetch("roles_by_attester").fetch(user.id.to_s, []).map { |r| r["name"] }
  end

  describe "GET /attestations/eligible" do
    # An admin reaches every boundary, so the permission gate is not what is
    # under test in these first examples — the SCOPING is.
    before { sign_in_as(admin) }

    it "offers the instance-scoped role for instance-wide evidence" do
      get attester_eligibility_path

      expect(response).to have_http_status(:ok)
      expect(role_names_for(policy_user)).to include("policy_manager")
    end

    # The whole defect, as one assertion: the same role must disappear once a
    # boundary is named, because the server will refuse it there.
    it "withdraws the instance-scoped role once a boundary is named" do
      get attester_eligibility_path, params: { authorization_boundary_id: boundary.id }

      expect(response).to have_http_status(:ok)
      expect(role_names_for(policy_user)).not_to include("policy_manager")
    end

    it "offers a boundary role holder on their own boundary" do
      get attester_eligibility_path, params: { authorization_boundary_id: boundary.id }

      expect(role_names_for(isso_user)).to eq([ "isso" ])
    end

    it "does not offer that role on a boundary they hold nothing on" do
      get attester_eligibility_path, params: { authorization_boundary_id: other_boundary.id }

      expect(role_names_for(isso_user)).to be_empty
    end

    # #947 — an admin who appeared in no picker while being able to do
    # everything else was a real defect once. It must not come back through the
    # refresh path.
    it "still lists an Instance Admin as an eligible attester" do
      get attester_eligibility_path, params: { authorization_boundary_id: boundary.id }

      expect(payload.fetch("attesters").map { |a| a["id"] }).to include(admin.id)
    end

    it "labels attesters without exposing a bare id" do
      get attester_eligibility_path, params: { authorization_boundary_id: boundary.id }

      labels = payload.fetch("attesters").map { |a| a["label"] }
      expect(labels).to all(be_present)
      expect(labels).to include(isso_user.display_label.presence || isso_user.email)
    end
  end

  # Both directions (#885): a permitted caller succeeds AND an unpermitted one
  # is refused. Only asserting the allow leg would pass against an endpoint with
  # no gate at all.
  describe "authorization" do
    it "requires authentication" do
      reset!

      get attester_eligibility_path, params: { authorization_boundary_id: boundary.id }

      expect(response).to have_http_status(:redirect)
    end

    it "refuses a caller without evidence.write on that boundary" do
      sign_in_as(create(:user))

      get attester_eligibility_path, params: { authorization_boundary_id: boundary.id }

      expect(response).to have_http_status(:forbidden)
    end

    it "allows a caller who holds evidence.write on that boundary" do
      writer_role = create(:role, :authorization_boundary_scoped,
                           permissions: { "evidence.write" => true })
      writer = create(:user)
      create(:user_role, user: writer, role: writer_role, authorization_boundary: boundary)
      sign_in_as(writer)

      get attester_eligibility_path, params: { authorization_boundary_id: boundary.id }

      expect(response).to have_http_status(:ok)
    end

    # The grant is boundary-scoped, so it must not open a different system's
    # roster (#919).
    it "refuses that same caller on a boundary they do not hold it on" do
      writer_role = create(:role, :authorization_boundary_scoped,
                           permissions: { "evidence.write" => true })
      writer = create(:user)
      create(:user_role, user: writer, role: writer_role, authorization_boundary: boundary)
      sign_in_as(writer)

      get attester_eligibility_path, params: { authorization_boundary_id: other_boundary.id }

      expect(response).to have_http_status(:forbidden)
    end
  end

  # api-first: every user-facing function gets an Api::V1 surface, and the UI is
  # a thin client over the same service.
  describe "GET /api/v1/attestations/eligible" do
    let(:token_user) { create(:user, :admin) }
    let(:api_token) { ApiToken.generate!(user: token_user, name: "Attester eligibility spec") }
    let(:auth_headers) { { "Authorization" => "Bearer #{api_token.plaintext_token}" } }

    it "returns the same shape as the session endpoint" do
      get api_v1_attester_eligibility_path,
          params: { authorization_boundary_id: boundary.id }, headers: auth_headers

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["data"]).to have_key("attesters")
      expect(body["data"]).to have_key("roles_by_attester")
      expect(body.dig("meta", "authorization_boundary_id")).to eq(boundary.id.to_s)
    end

    it "preserves the instance/boundary asymmetry" do
      get api_v1_attester_eligibility_path,
          params: { authorization_boundary_id: boundary.id }, headers: auth_headers

      expect(role_names_for(policy_user)).not_to include("policy_manager")

      get api_v1_attester_eligibility_path, headers: auth_headers

      expect(role_names_for(policy_user)).to include("policy_manager")
    end

    it "requires a bearer token" do
      get api_v1_attester_eligibility_path, params: { authorization_boundary_id: boundary.id }

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
