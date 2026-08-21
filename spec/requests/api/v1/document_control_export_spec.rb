# frozen_string_literal: true

require "rails_helper"

# #1026 — SAP and CDEF accepted bulk control-field WRITES over the API and
# exposed no read of what was written.
#
# `POST /api/v1/{sap,cdef}_documents/:slug/fields/import/confirm` sets control
# field values; `show` reported only `controls_count` and carried no `controls`;
# and neither type had the `…/export` route SSP and SAR have had since their
# controllers were written. The write's own `applied` count was the only
# evidence a caller had that anything landed — the #994 shape.
#
# These examples assert the read is INDEPENDENT of the write: each field value
# is written directly to the record, then read back through HTTP.
RSpec.describe "Api::V1 document control exports", type: :request do
  let(:admin) { create(:user, :admin) }
  let(:headers) do
    { "Authorization" => "Bearer #{ApiToken.generate!(user: admin, name: 'T').plaintext_token}" }
  end

  before { allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true) }

  describe "GET /api/v1/sap_documents/:id/export" do
    let(:boundary) { create(:authorization_boundary) }
    let!(:document) { create(:sap_document, authorization_boundary: boundary) }
    let!(:control) { create(:sap_control, sap_document: document, control_id: "AC-2") }
    let!(:field) do
      create(:sap_control_field, sap_control: control,
                                 field_name: "objective", field_value: "Verify AC-2 accounts")
    end

    it "returns the control field values that only field-import could otherwise write" do
      get "/api/v1/sap_documents/#{document.slug}/export", headers: headers

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      # #911 — `ControlIdentifiable` canonicalises the identifier on write, so
      # the export carries `ac-2`, not the `AC-2` handed to the factory. The
      # export must agree with the record, which is what makes it a read of the
      # stored value rather than an echo of the caller's spelling.
      expect(control.reload.control_id).to eq("ac-2")
      exported = body["controls"].find { |c| c["control_id"] == control.control_id }
      expect(exported).to be_present, "ac-2 missing from the export: #{body['controls'].inspect}"

      values = exported["fields"].to_h { |f| [ f["field_name"], f["field_value"] ] }
      expect(values["objective"]).to eq("Verify AC-2 accounts")
    end

    it "reflects a later change to the field, so it reads the record and not a cache" do
      field.update!(field_value: "Rewritten objective")

      get "/api/v1/sap_documents/#{document.slug}/export", headers: headers

      values = response.parsed_body["controls"]
                       .find { |c| c["control_id"] == control.reload.control_id }["fields"]
                       .to_h { |f| [ f["field_name"], f["field_value"] ] }
      expect(values["objective"]).to eq("Rewritten objective")
    end

    it "refuses an anonymous caller" do
      get "/api/v1/sap_documents/#{document.slug}/export"

      expect(response).to have_http_status(:unauthorized)
    end

    # #952 — a boundary-scoped document is not readable by a user holding no
    # grant on that boundary. The allow leg alone would pass against an action
    # with no guard at all, which is how #919 and #974 were found.
    it "refuses a user with no grant on the document's boundary" do
      outsider = create(:user)
      token = ApiToken.generate!(user: outsider, name: "O").plaintext_token

      get "/api/v1/sap_documents/#{document.slug}/export",
          headers: { "Authorization" => "Bearer #{token}" }

      expect(response).to have_http_status(:forbidden)
    end

    it "404s for an unknown slug rather than leaking a 500" do
      get "/api/v1/sap_documents/no-such-plan/export", headers: headers

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET /api/v1/cdef_documents/:id/export" do
    let!(:document) { create(:cdef_document) }
    let!(:control) { create(:cdef_control, cdef_document: document, control_id: "SV-000001r1_rule") }
    let!(:field) do
      create(:cdef_control_field, cdef_control: control,
                                  field_name: "implementation_narrative",
                                  field_value: "Enforced by the platform module")
    end

    it "returns the control field values that only field-import could otherwise write" do
      get "/api/v1/cdef_documents/#{document.slug}/export", headers: headers

      expect(response).to have_http_status(:ok)
      exported = response.parsed_body["controls"].find { |c| c["control_id"] == control.reload.control_id }
      expect(exported).to be_present

      values = exported["fields"].to_h { |f| [ f["field_name"], f["field_value"] ] }
      expect(values["implementation_narrative"]).to eq("Enforced by the platform module")
    end

    it "reflects a later change to the field, so it reads the record and not a cache" do
      field.update!(field_value: "Enforced by the HSM")

      get "/api/v1/cdef_documents/#{document.slug}/export", headers: headers

      values = response.parsed_body["controls"]
                       .find { |c| c["control_id"] == control.reload.control_id }["fields"]
                       .to_h { |f| [ f["field_name"], f["field_value"] ] }
      expect(values["implementation_narrative"]).to eq("Enforced by the HSM")
    end

    it "refuses an anonymous caller" do
      get "/api/v1/cdef_documents/#{document.slug}/export"

      expect(response).to have_http_status(:unauthorized)
    end

    it "404s for an unknown slug rather than leaking a 500" do
      get "/api/v1/cdef_documents/no-such-cdef/export", headers: headers

      expect(response).to have_http_status(:not_found)
    end
  end
end
