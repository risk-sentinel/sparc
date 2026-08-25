# frozen_string_literal: true

require "rails_helper"

# #944 — a component definition could not be authored from scratch, and could
# not be edited at all.
#
# `CdefDocumentsController` had `new`/`create` but no `edit` and no `update`,
# and `create` was unconditionally an upload handler — so the only way a CDEF
# entered SPARC was as a file someone else had authored. `config/routes.rb`
# generated the `edit`/`update` routes from a bare `resources`, so they existed
# and resolved to actions that did not.
RSpec.describe "CDEF authoring (#944)", type: :request do
  let(:admin) { create(:user, :admin) }

  before { sign_in_as(admin) }

  def authoring_attrs(**overrides)
    {
      name: "Okta Identity Platform",
      component_type: "service",
      component_title: "Okta",
      component_description: "Workforce identity provider.",
      control_implementation_source: "https://example.gov/catalogs/rev5.json",
      control_implementation_description: "Implements the IA family."
    }.merge(overrides)
  end

  describe "authoring from scratch" do
    it "creates a component definition with no file at all" do
      expect {
        post cdef_documents_path, params: { cdef_document: authoring_attrs }
      }.to change(CdefDocument, :count).by(1)

      cdef = CdefDocument.order(:id).last
      expect(cdef.component_type).to eq("service")
      expect(cdef.component_title).to eq("Okta")
      expect(response).to redirect_to(cdef_document_path(cdef))
    end

    it "refuses a component type OSCAL does not define" do
      post cdef_documents_path, params: { cdef_document: authoring_attrs(component_type: "wetware") }

      expect(response).to have_http_status(:unprocessable_content)
      expect(CdefDocument.where(name: "Okta Identity Platform")).to be_empty
    end

    it "still requires a name" do
      post cdef_documents_path, params: { cdef_document: authoring_attrs(name: "") }

      expect(response).to have_http_status(:unprocessable_content)
    end

    # Found by the ui-smoke run, not by this spec's first version: `status`
    # defaults to "pending" at the column, so the original `||=` never fired and
    # the document sat as though a parse were queued. The show screen then
    # rendered its processing view instead of the component — invisible from a
    # request spec that only checked the redirect and the attributes.
    it "marks an authored document completed, not pending" do
      post cdef_documents_path, params: { cdef_document: authoring_attrs }

      expect(CdefDocument.order(:id).last.status).to eq("completed")
    end

    it "records it as custom rather than leaving the type unset" do
      post cdef_documents_path, params: { cdef_document: authoring_attrs }

      expect(CdefDocument.order(:id).last.cdef_type).to eq("custom")
    end

    it "shows the authored document on its own page afterwards" do
      post cdef_documents_path, params: { cdef_document: authoring_attrs }
      follow_redirect!

      expect(response.body).to include("Okta Identity Platform")
    end

    it "offers the authoring form on the new page" do
      get new_cdef_document_path

      expect(response.body).to include("Author a Component Definition")
    end
  end

  describe "editing" do
    let(:cdef) { create(:cdef_document, name: "Editable") }

    it "renders the edit screen the route always promised" do
      get edit_cdef_document_path(cdef)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Component type")
    end

    it "updates the component's OSCAL fields" do
      patch cdef_document_path(cdef), params: { cdef_document: authoring_attrs(name: cdef.name) }

      expect(response).to redirect_to(cdef_document_path(cdef))
      expect(cdef.reload.component_type).to eq("service")
      expect(cdef.control_implementation_source).to eq("https://example.gov/catalogs/rev5.json")
    end

    it "refuses an invalid component type on update" do
      patch cdef_document_path(cdef), params: { cdef_document: { component_type: "wetware" } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(cdef.reload.component_type).to be_nil
    end
  end

  # The issue is explicit that authoring must not weaken these. They are the
  # reason an AWS Labs CDEF stays trustworthy and a published one stays fixed.
  describe "the existing guards are not weakened" do
    it "refuses to edit an AWS-Labs-sourced document" do
      aws = create(:cdef_document, import_metadata: { "source_type" => "aws_labs" })

      get edit_cdef_document_path(aws)

      expect(response).to redirect_to(cdef_document_path(aws))
      expect(flash[:error]).to match(/read-only/i)
    end

    it "refuses to update an AWS-Labs-sourced document" do
      aws = create(:cdef_document, import_metadata: { "source_type" => "aws_labs" })

      patch cdef_document_path(aws), params: { cdef_document: { component_title: "hijacked" } }

      expect(aws.reload.component_title).to be_nil
    end

    it "refuses to update a published document" do
      published = create(:cdef_document, lifecycle_status: "published")

      patch cdef_document_path(published), params: { cdef_document: { component_title: "hijacked" } }

      expect(published.reload.component_title).to be_nil
    end

    it "does not offer the Edit button on a read-only document" do
      aws = create(:cdef_document, import_metadata: { "source_type" => "aws_labs" })

      get cdef_document_path(aws)

      expect(response.body).not_to include(edit_cdef_document_path(aws))
    end
  end

  describe "what the export does with the authored values" do
    # OSCAL requires at least one implemented-requirement, so an exportable
    # document needs a control basis.
    def exportable_cdef
      cdef = create(:cdef_document, name: "Doc name", description: "Doc description")
      create(:cdef_control, cdef_document: cdef, control_id: "ac-1")
      cdef
    end

    it "uses them instead of the hardcoded defaults" do
      cdef = exportable_cdef
      cdef.update!(component_type: "policy", component_title: "Access Policy",
                   component_description: "The written policy.",
                   control_implementation_source: "https://example.gov/rev5.json")

      json = JSON.parse(OscalComponentDefinitionExportService.new(cdef).export)
      component = json.dig("component-definition", "components", 0)

      expect(component["type"]).to eq("policy")
      expect(component["title"]).to eq("Access Policy")
      expect(component["description"]).to eq("The written policy.")
      expect(component.dig("control-implementations", 0, "source"))
        .to eq("https://example.gov/rev5.json")
    end

    # A document nobody has authored must export exactly as it did before, or
    # this change silently rewrites every imported CDEF.
    it "falls back to the previous values when nothing was authored" do
      cdef = exportable_cdef

      json = JSON.parse(OscalComponentDefinitionExportService.new(cdef).export)
      component = json.dig("component-definition", "components", 0)

      expect(component["type"]).to eq("software")
      expect(component["title"]).to eq("Doc name")
      expect(component["description"]).to eq("Doc description")
    end
  end
end
