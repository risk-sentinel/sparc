# frozen_string_literal: true

require "rails_helper"

# #499 slice 5 — bulk-apply UI flow on the CDEF web controller.
# Three routes: GET /bulk_apply (picker), POST /bulk_apply_preview
# (preview table), POST /bulk_apply_confirm (apply).
RSpec.describe "CdefDocuments bulk-apply UI", type: :request do
  let(:admin) { create(:user, :admin) }
  let(:cdef)  { create(:cdef_document, name: "UI Spec CDEF") }
  let!(:converter) do
    conv = Converter.create!(name: "UI Spec Converter", converter_type: "custom",
                             status: "complete", metadata_extra: { "target_rev" => "5" })
    ConverterEntry.create!(converter: conv, source_id: "src-1", target_id: "cm-3",
                           relationship: "equivalent", row_order: 0)
    conv
  end

  before do
    allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true)
    sign_in_as(admin)
  end

  describe "GET /cdef_documents/:id/bulk_apply" do
    it "renders the picker form" do
      get bulk_apply_cdef_document_path(cdef)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Bulk Apply Converter")
      expect(response.body).to include(converter.name)
    end

    it "redirects with error when CDEF is AWS-Labs-sourced" do
      cdef.update!(import_metadata: { "source_type" => "aws_labs", "source_url" => "https://example/cdef.json" })
      get bulk_apply_cdef_document_path(cdef)
      expect(response).to redirect_to(cdef_document_path(cdef))
      follow_redirect!
      expect(response.body).to include("Bulk-apply is disabled on AWS-Labs-sourced CDEFs")
    end
  end

  describe "POST /cdef_documents/:id/bulk_apply_preview" do
    it "renders the preview table with stats" do
      post bulk_apply_preview_cdef_document_path(cdef),
           params: { converter_id: converter.id }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Confirm &amp; Apply")
      expect(response.body).to include("cm-3")
      expect(response.body).to include("ready")
    end

    it "emits a cdef_bulk_apply_converter_previewed audit event" do
      expect {
        post bulk_apply_preview_cdef_document_path(cdef),
             params: { converter_id: converter.id }
      }.to change { AuditEvent.where(action: "cdef_bulk_apply_converter_previewed").count }.by(1)
    end

    it "redirects with alert when converter_id is missing" do
      post bulk_apply_preview_cdef_document_path(cdef), params: { converter_id: 999_999 }
      expect(response).to redirect_to(bulk_apply_cdef_document_path(cdef))
      follow_redirect!
      expect(response.body).to include("Converter not found")
    end
  end

  describe "POST /cdef_documents/:id/bulk_apply_confirm" do
    def grab_token_for(target_cdef = cdef)
      post bulk_apply_preview_cdef_document_path(target_cdef),
           params: { converter_id: converter.id }
      # Match either attribute order — Rails form_with hidden_field
      # typically renders name= before value=, but be tolerant.
      m = response.body.match(/<input[^>]*name="token"[^>]*value="([^"]+)"/) ||
          response.body.match(/<input[^>]*value="([^"]+)"[^>]*name="token"/)
      m && m[1]
    end

    it "applies the changeset and redirects with flash success" do
      token = grab_token_for
      expect(token).to be_present, "could not extract token from preview response"

      expect {
        post bulk_apply_confirm_cdef_document_path(cdef), params: { token: token }
      }.to change { cdef.cdef_controls.count }.by(1)
      expect(response).to redirect_to(cdef_document_path(cdef))
      follow_redirect!
      expect(response.body).to include("Bulk apply complete")
    end

    it "redirects with alert on tampered token" do
      post bulk_apply_confirm_cdef_document_path(cdef), params: { token: "bogus.token" }
      expect(response).to redirect_to(bulk_apply_cdef_document_path(cdef))
      follow_redirect!
      expect(response.body).to include("Apply failed")
    end
  end

  context "as a non-admin user without converters.write" do
    let(:regular_user) { create(:user) }

    before { sign_in_as(regular_user) }

    it "redirects with auth error on the picker" do
      get bulk_apply_cdef_document_path(cdef)
      expect(response).to redirect_to(cdef_document_path(cdef))
      follow_redirect!
      expect(response.body).to include("Not authorized to bulk-apply")
    end
  end
end
