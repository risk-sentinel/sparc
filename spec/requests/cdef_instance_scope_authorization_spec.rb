# frozen_string_literal: true

require "rails_helper"

# #980 — making a CDEF instance-wide publishes it to every organization on the
# instance, including ones the requester is not a member of. It needs an
# instance-level grant of `cdef.scope_instance` (#1257); an instance
# administrator always has it. The Policy Manager grant is exercised in
# policy_manager_cdef_write_1257_spec.rb.
#
# Both directions (#885). The deny leg uses a user who holds `cdef.write` and
# can therefore re-scope the document every OTHER way. Without that, the deny
# leg would pass merely because the user could not reach the action at all.
RSpec.describe "CDEF instance-wide scope authorization", type: :request do
  let(:org)  { create(:organization) }
  let(:cdef) { create(:cdef_document, organization: org, globally_available: true) }

  def set_scope(to:)
    patch update_scope_cdef_document_path(cdef), params: { cdef_document: { scope: to } }
  end

  context "as an instance admin" do
    before { sign_in_as(create(:user, :admin)) }

    it "allows the instance-wide tier" do
      set_scope(to: "instance")

      expect(cdef.reload.scope_tier).to eq(:instance)
      expect(flash[:error]).to be_blank
    end

    it "audits the change" do
      expect { set_scope(to: "instance") }
        .to change { AuditEvent.where(action: "cdef_document_scope_updated").count }.by(1)
    end
  end

  context "as a non-admin who can otherwise re-scope this CDEF" do
    let(:writer) do
      role = create(:role, name: "cdef_writer_probe", scope: "instance",
                           permissions: { "cdef.write" => true, "cdef.read" => true })
      create(:user).tap do |u|
        create(:user_role, user: u, role: role)
        create(:organization_membership, user: u, organization: org)
      end
    end

    before { sign_in_as(writer) }

    it "refuses the instance-wide tier and changes nothing" do
      set_scope(to: "instance")

      expect(cdef.reload.scope_tier).not_to eq(:instance)
      expect(cdef.organization_id).to eq(org.id)
      expect(flash[:error]).to eq(CdefScopeService::INSTANCE_SCOPE_REFUSAL)
    end

    # The other half of the deny leg: proves the refusal is about the TIER and
    # not about this user being unable to use the action at all.
    it "still allows the organization-wide tier" do
      set_scope(to: "global")

      expect(cdef.reload.scope_tier).to eq(:organization)
      expect(flash[:error]).to be_blank
    end

    it "is refused an instance-wide upload, and nothing is created" do
      file = fixture_file_upload("components/example-component-definition.json", "application/json")

      expect {
        post cdef_documents_path, params: { cdef_document: { files: [ file ], scope: "instance" } }
      }.not_to change(CdefDocument, :count)
      expect(flash[:error]).to include(CdefScopeService::INSTANCE_SCOPE_REFUSAL)
    end

    it "does not audit a refused change" do
      expect { set_scope(to: "instance") }
        .not_to change { AuditEvent.where(action: "cdef_document_scope_updated").count }
    end
  end
end
