# frozen_string_literal: true

require "rails_helper"

# #1024 — KSI validations are gated by the evidence permissions, scoped to the
# boundary.
#
# Before this, `create` and `update` required nothing beyond a valid token on
# ANY boundary: `set_boundary` looked the boundary up and never checked the
# caller against it. Any authenticated user could mark an indicator `passed` on
# a system they had no relationship with, and the audit event recorded it as a
# legitimate assessment.
#
# Both directions are asserted throughout, and the refusal legs re-read the
# record — refusing the request is not the same as refusing the write, and only
# a separate read tells them apart.
RSpec.describe "Api::V1::KsiValidations authorization", type: :request do
  let(:boundary)       { create(:authorization_boundary) }
  let(:other_boundary) { create(:authorization_boundary) }

  let(:admin)     { create(:user, :admin) }
  let(:holder)    { create(:user) }
  let(:outsider)  { create(:user) }

  let(:catalog)  { create(:control_catalog) }
  let(:family)   { create(:control_family, control_catalog: catalog, code: "KSI") }
  let!(:indicator) { create(:catalog_control, control_family: family, control_id: "ksi-cna-01") }

  let(:writer_role) do
    role = create(:role, :authorization_boundary_scoped, name: "ksi_writer_#{SecureRandom.hex(4)}")
    role.assign_permissions("evidence.read" => true, "evidence.write" => true)
    role.save!
    role
  end

  def headers_for(user)
    { "Authorization" => "Bearer #{ApiToken.generate!(user: user, name: 'T').plaintext_token}" }
  end

  def path(target = boundary) = "/api/v1/authorization_boundaries/#{target.id}/ksi_validations"

  before do
    allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true)
    create(:user_role, user: holder, role: writer_role, authorization_boundary: boundary)
  end

  let(:payload) do
    { ksi_validation: { catalog_control_id: indicator.id, status: "not_assessed" } }
  end

  describe "create" do
    it "allows a caller holding evidence.write on this boundary" do
      expect {
        post path, params: payload, headers: headers_for(holder), as: :json
      }.to change(KsiValidation, :count).by(1)

      expect(response).to have_http_status(:created), response.body
    end

    it "allows an instance admin" do
      post path, params: payload, headers: headers_for(admin), as: :json
      expect(response).to have_http_status(:created), response.body
    end

    it "refuses a caller with no grant, and records nothing" do
      expect {
        post path, params: payload, headers: headers_for(outsider), as: :json
      }.not_to change(KsiValidation, :count)

      expect(response).to have_http_status(:forbidden)
    end

    # The grant is per boundary, so holding it somewhere is not holding it here.
    # This is the leg the old code could never have failed, because it did not
    # look at the boundary at all.
    it "refuses a holder writing to a DIFFERENT boundary, and records nothing" do
      expect {
        post path(other_boundary), params: payload, headers: headers_for(holder), as: :json
      }.not_to change(KsiValidation, :count)

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "update" do
    let!(:validation) do
      create(:ksi_validation, authorization_boundary: boundary, catalog_control: indicator,
                              status: "not_assessed")
    end

    it "allows a holder, and the change persists" do
      patch "#{path}/#{validation.id}", params: { ksi_validation: { status: "passed" } },
        headers: headers_for(holder), as: :json

      expect(response).to have_http_status(:ok), response.body
      expect(validation.reload.status).to eq("passed")
    end

    it "refuses a caller with no grant, and the record is unchanged" do
      patch "#{path}/#{validation.id}", params: { ksi_validation: { status: "passed" } },
        headers: headers_for(outsider), as: :json

      expect(response).to have_http_status(:forbidden)
      expect(validation.reload.status).to eq("not_assessed")
    end
  end

  describe "reads" do
    it "allows a holder to list" do
      get path, headers: headers_for(holder)
      expect(response).to have_http_status(:ok)
    end

    it "refuses a caller with no grant" do
      get path, headers: headers_for(outsider)
      expect(response).to have_http_status(:forbidden)
    end

    it "still refuses an unauthenticated caller" do
      get path
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "destroy" do
    let!(:validation) do
      create(:ksi_validation, authorization_boundary: boundary, catalog_control: indicator)
    end

    it "remains admin-only — a boundary write grant is not enough" do
      expect {
        delete "#{path}/#{validation.id}", headers: headers_for(holder)
      }.not_to change(KsiValidation, :count)

      expect(response).to have_http_status(:forbidden)
    end

    it "allows an instance admin" do
      expect {
        delete "#{path}/#{validation.id}", headers: headers_for(admin)
      }.to change(KsiValidation, :count).by(-1)

      expect(response).to have_http_status(:ok)
    end
  end
end
