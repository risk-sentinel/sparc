# frozen_string_literal: true

require "rails_helper"

# #1257 — Policy Manager holds `cdef.write`, so it can create and edit a
# component definition and make it organization-wide. Instance-wide stays
# instance-administrator only (#980).
#
# The roles here are the SHIPPED built-in roles (BuiltInRoleSeeder), not a
# spec-made grant, so these fail if the shipped default loses the key. Both
# directions on both surfaces: the refusals use a role that reads CDEFs and
# does not write them, and a Policy Manager whose administrator revoked the key.
RSpec.describe "Policy Manager and component definitions (#1257)", type: :request do
  let(:organization) { create(:organization) }
  let(:policy_manager) { holder_of("policy_manager", organization: organization) }
  let(:reader) { holder_of("global_viewer", organization: organization) }
  let(:cdef) { create(:cdef_document, cdef_type: "custom") }

  before do
    allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true)
    allow(SparcConfig).to receive(:enable_local_login?).and_return(true)
    BuiltInRoleSeeder.call
  end

  def holder_of(role_name, organization: nil)
    create(:user).tap do |user|
      create(:user_role, user: user, role: Role.find_by!(name: role_name))
      create(:organization_membership, user: user, organization: organization) if organization
    end
  end

  def api_headers(user)
    { "Authorization" => "Bearer #{ApiToken.generate!(user: user, name: 'T').plaintext_token}" }
  end

  def authoring_attrs(**overrides)
    { name: "Directory Service", component_type: "service", component_title: "Directory",
      component_description: "Organization directory.", control_implementation_source: "https://example.gov/rev5.json",
      control_implementation_description: "Implements the AC family." }.merge(overrides)
  end

  # What an administrator does in Admin -> Roles: revoke the key, recorded as
  # their choice (#1259).
  def administrator_revokes_cdef_write
    role = Role.find_by!(name: "policy_manager")
    role.permissions = role.permissions.merge("cdef.write" => false)
    role.record_admin_choices([ "cdef.write" ])
    role.save!
  end

  it "ships Policy Manager with cdef.write" do
    expect(Role.find_by!(name: "policy_manager").has_permission?("cdef.write")).to be(true)
  end

  describe "web" do
    context "as a Policy Manager" do
      before { sign_in_as(policy_manager) }

      it "creates a component definition" do
        expect { post cdef_documents_path, params: { cdef_document: authoring_attrs } }
          .to change(CdefDocument, :count).by(1)

        expect(response).to redirect_to(cdef_document_path(CdefDocument.order(:id).last))
      end

      it "uploads one organization-wide, owned by their organization" do
        file = fixture_file_upload("components/example-component-definition.json", "application/json")

        expect {
          post cdef_documents_path, params: { cdef_document: { files: [ file ], scope: "global" } }
        }.to change(CdefDocument, :count).by(1)

        created = CdefDocument.order(:id).last
        expect(created.scope_tier).to eq(:organization)
        expect(created.organization_id).to eq(organization.id)
      end

      it "edits a component definition" do
        patch cdef_document_path(cdef), params: { cdef_document: authoring_attrs(name: "Renamed Service") }

        expect(cdef.reload.name).to eq("Renamed Service")
      end

      it "makes a component definition organization-wide" do
        patch update_scope_cdef_document_path(cdef), params: { cdef_document: { scope: "global" } }

        expect(flash[:error]).to be_blank
        expect(cdef.reload.scope_tier).to eq(:organization)
        expect(cdef.organization_id).to eq(organization.id)
      end

      it "cannot make a component definition instance-wide" do
        patch update_scope_cdef_document_path(cdef), params: { cdef_document: { scope: "instance" } }

        expect(flash[:error]).to match(/instance administrator/i)
        expect(cdef.reload.scope_tier).not_to eq(:instance)
      end

      it "is not offered the instance-wide tier" do
        get cdef_document_path(cdef)

        expect(response.body).not_to include('value="instance"')
      end
    end

    context "as a Policy Manager in no organization" do
      before { sign_in_as(holder_of("policy_manager")) }

      it "cannot reach instance-wide by asking for organization-wide" do
        patch update_scope_cdef_document_path(cdef), params: { cdef_document: { scope: "global" } }

        expect(flash[:error]).to match(/organization/i)
        expect(cdef.reload.scope_tier).not_to eq(:instance)
        expect(cdef.globally_available).not_to be(true)
      end

      it "cannot upload one instance-wide by asking for organization-wide" do
        file = fixture_file_upload("components/example-component-definition.json", "application/json")

        post cdef_documents_path, params: { cdef_document: { files: [ file ], scope: "global" } }

        expect(CdefDocument.where(globally_available: true, organization_id: nil)).to be_empty
      end
    end

    context "as a role that reads component definitions and does not write them" do
      before { sign_in_as(reader) }

      it "is refused create, edit and scope" do
        expect { post cdef_documents_path, params: { cdef_document: authoring_attrs } }
          .not_to change(CdefDocument, :count)
        expect(response).to redirect_to(root_path)

        patch cdef_document_path(cdef), params: { cdef_document: authoring_attrs(name: "Renamed Service") }
        expect(cdef.reload.name).not_to eq("Renamed Service")

        patch update_scope_cdef_document_path(cdef), params: { cdef_document: { scope: "global" } }
        expect(cdef.reload.globally_available).not_to be(true)
      end
    end

    context "as a Policy Manager whose administrator revoked cdef.write" do
      before do
        administrator_revokes_cdef_write
        BuiltInRoleSeeder.call # an upgrade keeps the administrator's choice
        sign_in_as(policy_manager)
      end

      it "is refused" do
        expect { post cdef_documents_path, params: { cdef_document: authoring_attrs } }
          .not_to change(CdefDocument, :count)
        expect(response).to redirect_to(root_path)
      end
    end
  end

  describe "API" do
    it "lets a Policy Manager create a component definition" do
      post "/api/v1/cdef_documents", params: { cdef_document: { name: "Directory Service", cdef_type: "custom" } },
                                      headers: api_headers(policy_manager), as: :json

      expect(response).to have_http_status(:created)
    end

    it "lets a Policy Manager edit a component definition" do
      put "/api/v1/cdef_documents/#{cdef.slug}", params: { cdef_document: { name: "Renamed Service" } },
                                                 headers: api_headers(policy_manager), as: :json

      expect(response).to have_http_status(:ok)
      expect(cdef.reload.name).to eq("Renamed Service")
    end

    it "lets a Policy Manager make a component definition organization-wide" do
      patch "/api/v1/cdef_documents/#{cdef.slug}/scope", params: { scope: "global" },
                                                          headers: api_headers(policy_manager), as: :json

      expect(response).to have_http_status(:ok)
      expect(cdef.reload.scope_tier).to eq(:organization)
    end

    it "refuses a Policy Manager the instance-wide tier" do
      patch "/api/v1/cdef_documents/#{cdef.slug}/scope", params: { scope: "instance" },
                                                          headers: api_headers(policy_manager), as: :json

      expect(response).to have_http_status(:forbidden)
      expect(cdef.reload.scope_tier).not_to eq(:instance)
    end

    it "refuses a role without cdef.write" do
      post "/api/v1/cdef_documents", params: { cdef_document: { name: "Directory Service", cdef_type: "custom" } },
                                      headers: api_headers(reader), as: :json

      expect(response).to have_http_status(:forbidden)
    end

    it "refuses a Policy Manager whose administrator revoked cdef.write" do
      administrator_revokes_cdef_write
      BuiltInRoleSeeder.call

      post "/api/v1/cdef_documents", params: { cdef_document: { name: "Directory Service", cdef_type: "custom" } },
                                      headers: api_headers(policy_manager), as: :json

      expect(response).to have_http_status(:forbidden)
    end
  end
end
