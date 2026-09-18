# frozen_string_literal: true

require "rails_helper"

# #737 — SSP enrichment imports from canonical SPARC sources.
RSpec.describe "SSP enrich imports (#737)", type: :request do
  let(:user) { create(:user, :admin) }

  before { sign_in_as(user) }

  describe "POST /ssp_documents/:id/import_boundary_users" do
    let(:boundary) { create(:authorization_boundary) }
    let(:ssp) { create(:ssp_document, authorization_boundary: boundary) }

    before do
      AuthorizationBoundaryMembership.create!(authorization_boundary: boundary, user_name: "Jane AO", role: "authorizing_official")
      AuthorizationBoundaryMembership.create!(authorization_boundary: boundary, user_name: "John SO", role: "system_owner")
    end

    it "imports boundary members as system users" do
      expect { post import_boundary_users_ssp_document_path(ssp) }.to change { ssp.ssp_users.count }.by(2)
      expect(response).to redirect_to(enrich_ssp_document_path(ssp))
      expect(ssp.ssp_users.pluck(:title)).to include("Jane AO", "John SO")
    end

    it "is idempotent — does not duplicate members already present" do
      ssp.ssp_users.create!(uuid: SecureRandom.uuid, title: "Jane AO")
      expect { post import_boundary_users_ssp_document_path(ssp) }.to change { ssp.ssp_users.count }.by(1)
      expect(ssp.ssp_users.where(title: "Jane AO").count).to eq(1)
    end

    # #1134 — this used to write the raw membership role (`authorizing_official`)
    # into `role-ids`: underscored, never declared, a dangling reference.
    describe "role-ids (#1134)" do
      def user_role_ids(title) = ssp.ssp_users.find_by!(title: title).role_ids_data

      it "stores NIST's id for a membership role NIST names, not the membership value" do
        post import_boundary_users_ssp_document_path(ssp)

        expect(user_role_ids("Jane AO")).to eq([ "authorizing-official" ])
        expect(user_role_ids("John SO")).to eq([ "system-owner" ])
      end

      it "declares an organization-defined role for one NIST does not name" do
        AuthorizationBoundaryMembership.create!(authorization_boundary: boundary, user_name: "Casey CISO", role: "ciso")

        post import_boundary_users_ssp_document_path(ssp)

        expect(user_role_ids("Casey CISO")).to eq([ "ciso" ])
        declared = ssp.reload.declared_roles.find { |r| r["id"] == "ciso" }
        expect(declared).to be_present
        expect(OscalRole.organization_defined?(declared)).to be(true)
      end

      it "keeps the default roles declared when it adds one" do
        AuthorizationBoundaryMembership.create!(authorization_boundary: boundary, user_name: "Casey CISO", role: "ciso")

        post import_boundary_users_ssp_document_path(ssp)

        expect(ssp.reload.declared_role_ids).to include(*OscalRole::SSP_DEFAULT_IDS, "ciso")
      end

      it "writes no roles when every one it references is already declared" do
        post import_boundary_users_ssp_document_path(ssp)

        # Both members map onto SSP defaults, so the document keeps declaring
        # them implicitly rather than freezing them into its metadata.
        expect(ssp.reload.metadata_extra.to_h).not_to have_key("roles")
      end

      it "exports a document with no unresolved role-ids — access-only members included" do
        AuthorizationBoundaryMembership.create!(authorization_boundary: boundary, user_name: "Casey CISO", role: "ciso")
        AuthorizationBoundaryMembership.create!(authorization_boundary: boundary, user_name: "Val Viewer", role: "view_only")

        post import_boundary_users_ssp_document_path(ssp)

        exported = JSON.parse(OscalSspExportService.new(ssp.reload).export_unvalidated)
        users = exported.dig("system-security-plan", "system-implementation", "users")
        expect(users.flat_map { |u| u["role-ids"] }).to include("authorizing-official", "ciso", "view-only")

        result = OscalConformanceService.new(exported, model: "system-security-plan").validate
        unresolved = result.violations.select { |v| v.rule == "role-id-unresolved" }
        expect(unresolved).to be_empty, -> { unresolved.map(&:message).join("\n") }
      end
    end
  end
  describe "POST /ssp_documents/:id/import_cdef_components" do
    let(:boundary) { create(:authorization_boundary) }
    let(:ssp) { create(:ssp_document, authorization_boundary: boundary) }
    let(:cdef) { create(:cdef_document, name: "Auth Service CDEF") }

    it "imports selected component definitions as SSP components linked to the CDEF" do
      expect {
        post import_cdef_components_ssp_document_path(ssp), params: { cdef_ids: [ cdef.id ] }
      }.to change { ssp.ssp_components.count }.by(1)
      comp = ssp.ssp_components.find_by(cdef_document_id: cdef.id)
      expect(comp.title).to eq("Auth Service CDEF")
      expect(response).to redirect_to(enrich_ssp_document_path(ssp))
    end

    it "does not re-import a CDEF already linked to a component" do
      ssp.ssp_components.create!(uuid: SecureRandom.uuid, component_type: "software",
                                 title: "x", description: "x", cdef_document_id: cdef.id)
      expect {
        post import_cdef_components_ssp_document_path(ssp), params: { cdef_ids: [ cdef.id ] }
      }.not_to change { ssp.ssp_components.count }
    end
  end
  describe "POST /ssp_documents/:id/import_back_matter" do
    let(:ssp) { create(:ssp_document) }
    let(:other) { create(:ssp_document) }
    let!(:reusable) do
      BackMatterResource.create!(resourceable: other, source: "managed", uuid: SecureRandom.uuid,
                                 globally_available: true, title: "Org Policy PDF", rel: "reference")
    end

    it "copies a selected reusable resource onto this SSP as a managed resource" do
      expect {
        post import_back_matter_ssp_document_path(ssp), params: { back_matter_ids: [ reusable.id ] }
      }.to change { BackMatterResource.where(resourceable: ssp).count }.by(1)
      copy = BackMatterResource.where(resourceable: ssp).last
      expect(copy.title).to eq("Org Policy PDF")
      expect(copy.source).to eq("managed")
      expect(copy.id).not_to eq(reusable.id)
    end

    it "does not duplicate a resource already present by title" do
      BackMatterResource.create!(resourceable: ssp, source: "managed", uuid: SecureRandom.uuid, title: "Org Policy PDF")
      expect {
        post import_back_matter_ssp_document_path(ssp), params: { back_matter_ids: [ reusable.id ] }
      }.not_to change { BackMatterResource.where(resourceable: ssp).count }
    end
  end
end

# #1134 — the enrich page's declare-a-role form: a thin client over the same model
# path as the roles API, asserted in both directions with a NON-admin allow leg.
RSpec.describe "SSP enrich: declare a role (#1134)", type: :request do
  before { allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true) }

  let(:boundary) { create(:authorization_boundary) }
  let(:ssp) { create(:ssp_document, authorization_boundary: boundary) }
  let(:author) do
    create(:user).tap do |u|
      grant_permission(u, "ssp.read", authorization_boundary: boundary)
      grant_permission(u, "ssp.write", authorization_boundary: boundary)
    end
  end
  let(:reader) { create(:user).tap { |u| grant_permission(u, "ssp.read", authorization_boundary: boundary) } }

  def declare(membership_role) = post declare_role_ssp_document_path(ssp), params: { membership_role: membership_role }

  it "lets a permission-holding non-admin declare a role from the boundary vocabulary" do
    sign_in_as(author)

    expect { declare("ciso") }.to change { AuditEvent.where(action: "ssp_role_declared").count }.by(1)

    expect(response).to redirect_to(enrich_ssp_document_path(ssp))
    expect(flash[:success]).to include("ciso")
    role = ssp.reload.declared_roles.find { |r| r["id"] == "ciso" }
    expect(OscalRole.organization_defined?(role)).to be(true)
    expect(ssp.declared_role_ids).to include(*OscalRole::SSP_DEFAULT_IDS)
  end

  it "refuses an access-only membership role with a message, declaring nothing" do
    sign_in_as(author)

    declare("view_only")

    expect(response).to redirect_to(enrich_ssp_document_path(ssp))
    expect(flash[:error]).to match(/responsibility-bearing/)
    expect(ssp.reload.metadata_extra.to_h).not_to have_key("roles")
  end

  it "refuses a reader without ssp.write" do
    sign_in_as(reader)

    declare("ciso")

    expect(response).to redirect_to(root_path)
    expect(ssp.reload.declared_role_ids).not_to include("ciso")
  end

  describe "the enrich page" do
    before { sign_in_as(author) }

    it "lists declared roles and offers only undeclared, responsibility-bearing ones by label" do
      get enrich_ssp_document_path(ssp)

      page = Nokogiri::HTML(response.body)
      listed = page.css("[data-testid=ssp-declared-roles-list] code").map(&:text)
      expect(listed).to match_array(OscalRole::SSP_DEFAULT_IDS)

      offered = page.css("#ssp-declare-role-select option").to_h { |o| [ o["value"], o.text ] }
      expect(offered.keys).to include("ciso", "assessor")
      expect(offered.keys).not_to include("isso", "system_owner", *OscalRole::ACCESS_ONLY_MEMBERSHIP_ROLES)
      expect(offered["ciso"]).to include("organization-defined")
      expect(offered.values).to all(satisfy { |label| !label.match?(/\A[a-z_]+\z/) }), "offered by LABEL, not by value"
    end

    it "says so when every responsibility-bearing role is declared" do
      OscalRole.membership_role_options.each { |(_l, v)| ssp.declare_membership_roles([ v ]) }
      ssp.save!

      get enrich_ssp_document_path(ssp)

      expect(response.body).to include("Every responsibility-bearing boundary role is already declared.")
      expect(Nokogiri::HTML(response.body).css("#ssp-declare-role-select")).to be_empty
    end
  end
end
