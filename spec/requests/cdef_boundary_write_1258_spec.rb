# frozen_string_literal: true

require "rails_helper"

# #1258 — a boundary-scoped `cdef.write` grant writes its boundary's component
# definitions, and nothing wider. The writer is a SHIPPED System Owner / ISO
# (BuiltInRoleSeeder) held on boundary X, so these fail if the shipped role
# loses the key as well as if the rule breaks. Both directions on both surfaces.
RSpec.describe "Boundary-scoped cdef.write (#1258)", type: :request do
  let(:organization) { create(:organization) }
  let(:x) { create(:authorization_boundary) }
  let(:y) { create(:authorization_boundary) }
  let!(:x_env) { create(:boundary, authorization_boundary: x) }
  let!(:y_env) { create(:boundary, authorization_boundary: y) }

  let(:owner) do
    create(:user).tap do |user|
      create(:user_role, user: user, role: Role.find_by!(name: "so_iso"), authorization_boundary_id: x.id)
      create(:organization_membership, user: user, organization: organization)
    end
  end
  let(:policy_manager) do
    create(:user).tap do |user|
      create(:user_role, user: user, role: Role.find_by!(name: "policy_manager"))
      create(:organization_membership, user: user, organization: organization)
    end
  end

  before do
    allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true)
    allow(SparcConfig).to receive(:enable_local_login?).and_return(true)
    BuiltInRoleSeeder.call
  end

  def scoped_to(boundary)
    create(:cdef_document, cdef_type: "custom").tap do |cdef|
      CdefScopeService.apply(cdef, scope: "boundary", authorization_boundary_id: boundary.id)
    end
  end

  let!(:on_x) { scoped_to(x) }
  let!(:on_y) { scoped_to(y) }
  let!(:org_wide) { create(:cdef_document, cdef_type: "custom", globally_available: true, organization: organization) }
  let!(:unassigned) { create(:cdef_document, cdef_type: "custom") }

  def headers(user) = { "Authorization" => "Bearer #{ApiToken.generate!(user: user, name: 'T').plaintext_token}" }

  def authoring_attrs(**overrides)
    { name: "Invented directory service", component_type: "service", component_title: "Directory",
      component_description: "Invented directory.", control_implementation_source: "https://example.gov/rev5.json",
      control_implementation_description: "Implements AC." }.merge(overrides)
  end

  describe CdefWriteAccess do
    it "writes its boundary's CDEF, and nothing scoped elsewhere or wider" do
      expect(described_class.may_write?(owner, on_x)).to be(true)
      expect(described_class.may_write?(owner, on_y)).to be(false)
      expect(described_class.may_write?(owner, org_wide)).to be(false)
      expect(described_class.may_write?(owner, unassigned)).to be(false)
      expect([ on_x, on_y, org_wide, unassigned ].map { described_class.may_write?(policy_manager, _1) }).to all(be(true))
    end

    it "is not given a CDEF by linking it to an environment" do
      BoundaryCdefDocument.create!(boundary: x_env, cdef_document: unassigned)
      BoundaryCdefDocument.create!(boundary: x_env, cdef_document: on_y)

      expect(described_class.may_write?(owner, unassigned)).to be(false)
      expect(described_class.may_write?(owner, on_y)).to be(false)
    end

    it "treats an older row carrying a boundary and globally_available as its tier" do
      org_wide.update_column(:import_metadata, { CdefScopeService::METADATA_KEY => x.id })
      expect(described_class.may_write?(owner, org_wide.reload)).to be(false)
    end

    it "keeps the scope boundary when a parse replaces import_metadata" do
      on_x.update!(import_metadata: { "format" => "oscal_cdef" })
      expect(described_class.may_write?(owner, on_x.reload)).to be(true)
    end

    it "lets a boundary writer choose only their boundary" do
      expect(described_class.may_scope?(owner, "boundary", x.id)).to be(true)
      expect(described_class.may_scope?(owner, "boundary", y.id)).to be(false)
      expect(described_class.may_scope?(owner, "global")).to be(false)
      expect(described_class.may_scope?(owner, "instance")).to be(false)
      expect(described_class.may_scope?(policy_manager, "global")).to be(true)
    end
  end

  describe "web" do
    before { sign_in_as(owner) }

    it "edits its boundary's CDEF and is refused another boundary's" do
      patch update_metadata_cdef_document_path(on_x), params: { cdef_document: { name: "Renamed on X" } }
      expect(on_x.reload.name).to eq("Renamed on X")

      patch update_metadata_cdef_document_path(on_y), params: { cdef_document: { name: "Renamed on Y" } }
      expect(response).to redirect_to(root_path)
      expect(on_y.reload.name).not_to eq("Renamed on Y")
    end

    it "is refused an organization-wide and an unassigned CDEF" do
      [ org_wide, unassigned ].each do |cdef|
        delete cdef_document_path(cdef)
        expect(response).to redirect_to(root_path)
        expect(CdefDocument.exists?(cdef.id)).to be(true)
      end
    end

    it "shows Edit on its boundary's CDEF only" do
      get cdef_document_path(on_x)
      expect(Nokogiri::HTML(response.body).at_css("[data-testid='edit-cdef']")).to be_present

      get cdef_document_path(on_y)
      expect(Nokogiri::HTML(response.body).at_css("[data-testid='edit-cdef']")).to be_nil
    end

    it "authors a CDEF into its boundary, defaulting to its only one, and not into another" do
      expect { post cdef_documents_path, params: { cdef_document: authoring_attrs } }.to change(CdefDocument, :count).by(1)
      created = CdefDocument.order(:id).last
      expect(CdefScopeService.current_boundary_id(created)).to eq(x.id)
      expect(created.globally_available).to be(false)

      expect {
        post cdef_documents_path, params: { cdef_document: authoring_attrs(scope: "boundary", authorization_boundary_id: y.id) }
      }.not_to change(CdefDocument, :count)
      expect(response).to redirect_to(root_path)
    end

    it "offers only its own boundaries, and not organization-wide, on the create form" do
      get new_cdef_document_path
      doc = Nokogiri::HTML(response.body)

      offered = doc.css("#cdef_author_authorization_boundary_id option").map(&:text)
      expect(offered).to include(x.name)
      expect(offered).not_to include(y.name)
      expect(doc.at_css("#cdef_author_scope_global")["disabled"]).to be_present
      expect(doc.at_css("#cdef_document_scope_global")["disabled"]).to be_present
    end

    it "cannot author an organization-wide CDEF" do
      expect {
        post cdef_documents_path, params: { cdef_document: authoring_attrs(scope: "global") }
      }.not_to change(CdefDocument, :count)
    end

    it "copies an instance-wide AWS Labs CDEF into its own boundary, not instance-wide" do
      aws = create(:cdef_document, cdef_type: "custom", globally_available: true, organization: nil,
                                   import_metadata: { "source_type" => "aws_labs" })

      expect { post copy_cdef_document_path(aws) }.to change(CdefDocument, :count).by(1)
      copy = CdefDocument.order(:id).last
      expect(copy.globally_available).to be(false)
      expect(CdefScopeService.current_boundary_id(copy)).to eq(x.id)
    end

    it "copies into the source's boundary when it writes for several" do
      create(:user_role, user: owner, role: Role.find_by!(name: "so_iso"), authorization_boundary_id: y.id)

      expect { post copy_cdef_document_path(on_y) }.to change(CdefDocument, :count).by(1)
      expect(CdefScopeService.current_boundary_id(CdefDocument.order(:id).last)).to eq(y.id)
    end

    it "moves a CDEF it writes only within its boundaries" do
      patch update_scope_cdef_document_path(on_x), params: { cdef_document: { scope: "global" } }
      expect(response).to redirect_to(root_path)
      expect(on_x.reload.globally_available).to be(false)

      patch update_scope_cdef_document_path(on_x), params: { cdef_document: { scope: "boundary", authorization_boundary_id: y.id } }
      expect(CdefScopeService.current_boundary_id(on_x.reload)).to eq(x.id)
    end

    it "needs write access to the CDEF for bulk apply, as well as converters.write" do
      grant_permission(owner, "converters.write")
      get bulk_apply_cdef_document_path(on_y)
      expect(response).to redirect_to(root_path)

      get bulk_apply_cdef_document_path(on_x)
      expect(response).to have_http_status(:ok)
    end
  end

  describe "API" do
    it "updates its boundary's CDEF and is refused another's, and wider ones" do
      patch "/api/v1/cdef_documents/#{on_x.slug}", headers: headers(owner), as: :json,
            params: { cdef_document: { description: "Updated on X" } }
      expect(response).to have_http_status(:ok), response.body

      [ on_y, org_wide, unassigned ].each do |cdef|
        patch "/api/v1/cdef_documents/#{cdef.slug}", headers: headers(owner), as: :json,
              params: { cdef_document: { description: "Updated elsewhere" } }
        expect(response).to have_http_status(:forbidden), "#{cdef.name}: #{response.status}"
      end
    end

    it "creates into its boundary and is refused another, or none it may choose" do
      post "/api/v1/cdef_documents", headers: headers(owner), as: :json,
           params: { cdef_document: authoring_attrs(scope: "boundary", authorization_boundary_id: x.id) }
      expect(response).to have_http_status(:created), response.body
      expect(CdefScopeService.current_boundary_id(CdefDocument.find(response.parsed_body.dig("data", "id")))).to eq(x.id)

      expect {
        post "/api/v1/cdef_documents", headers: headers(owner), as: :json,
             params: { cdef_document: authoring_attrs(scope: "boundary", authorization_boundary_id: y.id) }
      }.not_to change(CdefDocument, :count)
      expect(response).to have_http_status(:forbidden)

      post "/api/v1/cdef_documents", headers: headers(owner), as: :json,
           params: { cdef_document: authoring_attrs(scope: "instance") }
      expect(response).to have_http_status(:forbidden)
    end

    it "refuses scope on update: it changes through update_scope" do
      patch "/api/v1/cdef_documents/#{on_x.slug}", headers: headers(owner), as: :json,
            params: { cdef_document: { scope: "global" } }
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "re-scopes only within its boundaries" do
      patch "/api/v1/cdef_documents/#{on_x.slug}/scope", headers: headers(owner), as: :json,
            params: { scope: "boundary", authorization_boundary_id: y.id }
      expect(response).to have_http_status(:forbidden)

      patch "/api/v1/cdef_documents/#{on_x.slug}/scope", headers: headers(policy_manager), as: :json,
            params: { scope: "global" }
      expect(response).to have_http_status(:ok), response.body
    end

    it "lets a Policy Manager write every tier" do
      [ on_x, on_y, org_wide, unassigned ].each do |cdef|
        patch "/api/v1/cdef_documents/#{cdef.slug}", headers: headers(policy_manager), as: :json,
              params: { cdef_document: { description: "PM edit" } }
        expect(response).to have_http_status(:ok), "#{cdef.name}: #{response.body}"
      end
    end
  end
end
