# frozen_string_literal: true

require "rails_helper"

# #1238 — `set_baseline` (#911) was outside every write guard on SSP, SAR,
# SAP, POA&M and CDEF; only the profile controller covered it. So a signed-in
# user who could not edit a document could still re-point its baseline, and a
# POA&M, whose lineage includes its authorization boundary, could be moved into
# another boundary. `CdefDocumentsController#edit` likewise rendered the
# authoring form to a user without `cdef.write`.
#
# Both directions (#885): the deny leg holds every READ permission, so a refusal
# is about write and not about reaching the document at all; the allow leg holds
# write too and must still succeed.
RSpec.describe "Declaring a baseline requires write permission", type: :request do
  let(:catalog)  { create(:control_catalog) }
  let(:profile)  { create(:profile_document, control_catalog: catalog) }
  let(:boundary) { create(:authorization_boundary) }
  let(:other_boundary) { create(:authorization_boundary) }
  let(:ssp_source) { create(:ssp_document, profile_document: profile, authorization_boundary: boundary) }

  def grant(write:)
    allow_any_instance_of(User).to receive(:admin?).and_return(false)
    allow_any_instance_of(User).to receive(:instance_administrator?).and_return(false)
    allow_any_instance_of(User).to receive(:has_permission?) do |_user, key, **|
      key.to_s.end_with?(".read") || (write && key.to_s.end_with?(".write"))
    end
  end

  before do
    allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true)
    sign_in_as(create(:user))
  end

  cases = {
    "an SSP" => {
      build: ->(ctx) { ctx.create(:ssp_document, profile_document: nil, authorization_boundary: ctx.boundary) },
      path: :set_baseline_ssp_document_path, key: :ssp_document,
      attrs: ->(ctx) { { profile_document_id: ctx.profile.id } },
      read: ->(doc) { doc.profile_document_id }
    },
    "a SAP" => {
      build: ->(ctx) { ctx.create(:sap_document, ssp_document: nil, authorization_boundary: ctx.boundary) },
      path: :set_baseline_sap_document_path, key: :sap_document,
      attrs: ->(ctx) { { ssp_document_id: ctx.ssp_source.id } },
      read: ->(doc) { doc.ssp_document_id }
    },
    "a SAR" => {
      build: ->(ctx) { ctx.create(:sar_document, sap_document: nil, authorization_boundary: ctx.boundary) },
      path: :set_baseline_sar_document_path, key: :sar_document,
      attrs: ->(ctx) { { sap_document_id: ctx.create(:sap_document, authorization_boundary: ctx.boundary).id } },
      read: ->(doc) { doc.sap_document_id }
    },
    "a POA&M re-pointed to another boundary" => {
      build: ->(ctx) { ctx.create(:poam_document, ssp_document: nil, authorization_boundary: ctx.boundary) },
      path: :set_baseline_poam_document_path, key: :poam_document,
      attrs: ->(ctx) { { authorization_boundary_id: ctx.other_boundary.id } },
      read: ->(doc) { doc.authorization_boundary_id }
    },
    "a CDEF" => {
      build: ->(ctx) { ctx.create(:cdef_document, profile_document: nil) },
      path: :set_baseline_cdef_document_path, key: :cdef_document,
      attrs: ->(ctx) { { profile_document_id: ctx.profile.id } },
      read: ->(doc) { doc.profile_document_id }
    }
  }

  cases.each do |label, c|
    describe label do
      let(:doc) { c[:build].call(self) }
      let(:attrs) { c[:attrs].call(self) }

      def declare(c, doc, attrs)
        patch public_send(c[:path], doc), params: { c[:key] => attrs }
      end

      it "is refused to a user who can only read it, and changes nothing" do
        before_value = c[:read].call(doc)
        attrs # create any target document before permissions narrow
        grant(write: false)

        expect { declare(c, doc, attrs) }
          .to change { AuditEvent.where(action: "authorization_failure").count }.by(1)

        expect(response).to redirect_to(root_path)
        expect(c[:read].call(doc.reload)).to eq(before_value)
      end

      it "is allowed to a user who can write it" do
        attrs
        grant(write: true)

        declare(c, doc, attrs)

        expect(response).not_to redirect_to(root_path)
        expect(c[:read].call(doc.reload)).to eq(attrs.values.first)
      end
    end
  end

  describe "the CDEF authoring form" do
    let(:cdef) { create(:cdef_document) }

    it "is refused to a user without cdef.write" do
      cdef
      grant(write: false)

      get edit_cdef_document_path(cdef)

      expect(response).to redirect_to(root_path)
    end

    it "renders for a user with cdef.write" do
      cdef
      grant(write: true)

      get edit_cdef_document_path(cdef)

      expect(response).to have_http_status(:ok)
    end

    # The picker in front of `source_from_profile`, which was already guarded.
    it "refuses the profile-source picker to a user without cdef.write" do
      cdef
      grant(write: false)

      get select_profile_source_cdef_document_path(cdef)

      expect(response).to redirect_to(root_path)
    end

    it "renders the profile-source picker for a user with cdef.write" do
      cdef
      grant(write: true)

      get select_profile_source_cdef_document_path(cdef)

      expect(response).to have_http_status(:ok)
    end

    it "does not offer Populate from Profile to a user without cdef.write" do
      cdef
      grant(write: false)

      get cdef_document_path(cdef)

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include(select_profile_source_cdef_document_path(cdef))
    end

    it "offers Populate from Profile to a user with cdef.write" do
      cdef
      grant(write: true)

      get cdef_document_path(cdef)

      expect(response.body).to include(select_profile_source_cdef_document_path(cdef))
    end
  end
end
