# frozen_string_literal: true

require "rails_helper"

# The new-CDEF screen offers three independent ways in — upload, author,
# generate from a profile — each with its own form. They were stacked as plain
# cards, so the page read as one long form. Now a chooser (tabs) shows one at a
# time (cdef_new_chooser_controller.js); without JavaScript the chooser stays
# hidden and every form shows, so this spec reads the markup the controller
# drives and the server's choice of opening tab.
RSpec.describe "New CDEF chooser", type: :request do
  before { sign_in_as(create(:user, :admin)) }

  def page = Nokogiri::HTML(response.body)
  def chooser = page.at_css("[data-controller='cdef-new-chooser']")
  def tab(key) = page.at_css("[role='tab'][data-choice='#{key}']")
  def panel(key) = page.at_css("[role='tabpanel'][data-choice='#{key}']")

  it "offers the three ways in as tabs, each controlling its own panel" do
    get new_cdef_document_path

    expect(response).to have_http_status(:ok)
    expect(page.at_css("[role='tablist']")["hidden"]).not_to be_nil # shown by the controller
    %w[upload author profile].each do |key|
      expect(tab(key)).to be_present, key
      expect(tab(key)["aria-controls"]).to eq(panel(key)["id"]), key
      expect(panel(key)["aria-labelledby"]).to eq(tab(key)["id"]), key
      expect(panel(key)["hidden"]).to be_nil, "#{key}: every form shows without JavaScript"
    end
  end

  it "keeps each form inside its own panel" do
    get new_cdef_document_path

    expect(panel("upload").at_css("form input[type='file']")).to be_present
    expect(panel("upload").at_css("input[type='submit']")["value"]).to eq("Upload and Process")
    expect(panel("author").at_css("form input[type='file']")).to be_nil
    expect(panel("author").at_css("[data-testid='author-cdef-submit']")).to be_present
    expect(panel("profile").at_css("a[href='#{select_profile_cdef_documents_path}']")).to be_present
    expect(chooser.css("form").map { |f| f.ancestors("[role='tabpanel']").first["data-choice"] })
      .to contain_exactly("upload", "author")
  end

  it "opens on Upload by default" do
    get new_cdef_document_path

    expect(chooser["data-cdef-new-chooser-default-value"]).to eq("upload")
  end

  it "reopens on Author, with what was entered, when an authored CDEF is rejected" do
    post cdef_documents_path, params: { cdef_document: { name: "", component_type: "service", component_title: "Kept" } }

    expect(response).to have_http_status(:unprocessable_content)
    expect(chooser["data-cdef-new-chooser-default-value"]).to eq("author")
    expect(panel("author").at_css("input[name='cdef_document[component_title]']")["value"]).to eq("Kept")
  end

  it "folds the supported formats into the Upload panel and names the OSCAL version SPARC exports" do
    get new_cdef_document_path

    expect(panel("upload").at_css("details summary").text).to eq("Supported formats")
    expect(response.body).to include("NIST OSCAL v#{OscalSchema::DEFAULT_VERSION} Component Definition JSON")
    expect(response.body).not_to include("v1.1.2")
  end

  describe "the upload-only page (?only=upload)" do
    def upload_only = page.at_css("[data-testid='cdef-upload-only']")

    it "is the import on its own: no chooser, no other forms" do
      get new_cdef_document_path(only: "upload")

      expect(upload_only).to be_present
      expect(chooser).to be_nil
      expect(page.css("[role='tab']")).to be_empty
      expect(upload_only.at_css("form input[type='file']")).to be_present
      expect(upload_only.at_css("input[type='submit']")["value"]).to eq("Upload and Process")
      expect(upload_only.at_css("input[name='cdef_document[scope]']")).to be_present
      expect(upload_only.at_css("input[type='hidden'][name='only']")["value"]).to eq("upload")
      expect(page.at_css("[data-testid='author-cdef-submit']")).to be_nil
      expect(upload_only.at_css("a[href='#{new_cdef_document_path}']").text).to eq("Other ways to add one")
    end

    it "asks for a file, on the same page, when posted without one, and never authors" do
      expect {
        post cdef_documents_path, params: { only: "upload", cdef_document: { scope: "boundary" } }
      }.not_to change(CdefDocument, :count)

      expect(flash[:error]).to eq("Please select a file to upload")
      expect(upload_only).to be_present
    end
  end

  describe "the CDEF list" do
    it "offers Create New as every way in, and Upload File as the import alone" do
      get cdef_documents_path

      links = Nokogiri::HTML(response.body).css("a.sparc-action").to_h { |a| [ a.text.strip, a["href"] ] }
      expect(links["Create New"]).to eq(new_cdef_document_path)
      expect(links["Upload File"]).to eq(new_cdef_document_path(only: "upload"))
    end
  end
end
