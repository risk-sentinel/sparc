# frozen_string_literal: true

require "rails_helper"

# #1267 — a document could not be renamed or re-versioned from its page (400),
# and the OSCAL Metadata form dropped OSCAL Version, Published Date and
# Description. Both forms were built with `form_with url:` alone, which submits
# fields unwrapped, while every controller reads `params.require(<type>)`.
#
# The request specs that existed posted the wrapped shape directly, so they
# tested a request no page ever sent. These render the page, read each form as
# a browser would, and submit exactly what it holds.
RSpec.describe "Document metadata forms as rendered (#1267)", type: :request do
  # An admin, because what is under test is the shape of the form, not who may
  # submit it; each controller's write guard has its own specs.
  let(:user) { create(:user, admin: true) }

  before { sign_in_as(user) }

  def rendered_form(testid)
    form = Nokogiri::HTML(response.body).at_css(%(form[data-testid="#{testid}"]))
    expect(form).to be_present, "the page renders no #{testid}"
    form
  end

  # What a browser submits for the form: every named input and textarea with
  # its current value, then the edits the user typed, keyed by field name.
  def submit_as_rendered(form, edits)
    params = {}
    form.css("input[name], textarea[name]").each do |el|
      next if el["type"] == "submit"

      params[el["name"]] = el.name == "textarea" ? el.text : el["value"].to_s
    end
    edits.each do |field, value|
      name = params.keys.find { |key| key.end_with?("[#{field}]") }
      expect(name).to be_present, "the form has no #{field} field: #{params.keys.inspect}"
      params[name] = value
    end
    patch form["action"], params: params
  end

  {
    profile_document: :profile_version,
    cdef_document: :cdef_version,
    ssp_document: :ssp_version,
    sar_document: :sar_version,
    sap_document: :sap_version,
    poam_document: :poam_version
  }.each do |type, version_field|
    describe type.to_s do
      let(:document) { create(type, name: "Invented Original Name", version_field => "1.0") }

      it "renames the document and changes its version" do
        get send(:"#{type}_path", document)
        submit_as_rendered(rendered_form("document-name-form"), name: "Invented New Name", version_field => "2.0")

        expect(response).to have_http_status(:redirect)
        document.reload
        expect(document.name).to eq("Invented New Name")
        expect(document.public_send(version_field)).to eq("2.0")

        # The slug follows the name, so the redirect must name the new one.
        expect(response).to redirect_to(send(:"#{type}_path", document))
        follow_redirect!
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Invented New Name")
      end

      it "saves OSCAL Version, Published Date and Description" do
        get send(:"#{type}_path", document)
        submit_as_rendered(rendered_form("oscal-metadata-form"),
                           oscal_version: "1.1.3",
                           published: "2026-10-01T00:00:00Z",
                           description: "Invented description of the document")

        expect(response).to have_http_status(:redirect)
        document.reload
        expect(document.oscal_version).to eq("1.1.3")
        expect(document.published).to eq("2026-10-01T00:00:00Z")
        expect(document.description).to eq("Invented description of the document")
      end
    end
  end

  describe "control_catalog" do
    let(:catalog) { create(:control_catalog, lifecycle_status: "in_progress") }

    it "saves OSCAL Version, Published Date and Description" do
      get control_catalog_path(catalog)
      # A catalog page lives at its UUID; the id path redirects there.
      follow_redirect! if response.redirect?
      submit_as_rendered(rendered_form("oscal-metadata-form"),
                         oscal_version: "1.1.3",
                         published: "2026-10-01T00:00:00Z",
                         description: "Invented description of the catalog")

      expect(response).to have_http_status(:redirect)
      catalog.reload
      expect(catalog.oscal_version).to eq("1.1.3")
      expect(catalog.published).to eq("2026-10-01T00:00:00Z")
      expect(catalog.description).to eq("Invented description of the catalog")
    end
  end
end
