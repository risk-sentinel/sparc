# frozen_string_literal: true

require "rails_helper"

# #1340 — saving the SSP Enrich page. The form is redrawn in place (a Turbo
# frame): on success with the saved values and a confirmation, on failure
# with the author's input kept, each refused field outlined with its message,
# and the row named in the message above the form. Nothing is written unless
# all of it is valid.
RSpec.describe "SSP Enrich save (#1340)", type: :request do
  let(:admin) { create(:user, :admin) }
  let(:ssp) { create(:ssp_document, :enriched) }
  let!(:component) { create(:ssp_component, ssp_document: ssp, title: "Load balancer", description: "Fronts the app") }
  let!(:info_type) do
    ssp.ssp_information_types.create!(uuid: SecureRandom.uuid, title: "Audit logs", description: "System audit records")
  end

  before { sign_in_as(admin) }

  def page = Nokogiri::HTML(response.body)
  def frame = page.at_css("turbo-frame#ssp-enrich-form")
  def error_lines = page.css("[data-testid=enrich-errors] li").map { _1.text.squish }

  def save(components: nil, information_types: nil, users: nil, **fields)
    body = { ssp_document: { description: "Updated description" }.merge(fields) }
    body[:ssp_document][:components] = components || [ { id: component.id, title: component.title, description: component.description,
                                                         component_type: component.component_type } ]
    body[:ssp_document][:information_types] = information_types || [ { id: info_type.id, title: info_type.title,
                                                                       description: info_type.description } ]
    body[:ssp_document][:users] = users if users
    patch update_enrich_ssp_document_path(ssp), params: body, headers: { "Turbo-Frame" => "ssp-enrich-form" }
  end

  describe "a save that succeeds" do
    it "stays on the Enrich page and redraws the form with a confirmation" do
      save

      expect(response).to have_http_status(:ok)
      expect(frame).to be_present
      expect(frame.at_css("[data-testid=enrich-saved]").text).to include("SSP enrichment data saved.")
      expect(frame.at_css("#ssp_document_description").text.strip).to eq("Updated description")
      expect(ssp.reload.description).to eq("Updated description")
    end

    it "keeps an added row once saved, so the next save updates it rather than adding it again" do
      save(components: [ { id: component.id, title: component.title, description: component.description },
                         { title: "WAF", description: "Filters requests", component_type: "service" } ])

      waf = ssp.ssp_components.find_by!(title: "WAF")
      ids = frame.css("input[name='ssp_document[components][][id]']").map { _1["value"].to_i }
      expect(ids).to include(component.id, waf.id)
    end

    it "is audited" do
      expect { save }.to change { AuditEvent.where(action: "ssp_document_updated").count }.by(1)
    end
  end

  describe "a save with an added row left blank" do
    let(:blank_row) { { title: "", description: "", component_type: "software" } }

    it "saves nothing and answers 422 with the form redrawn" do
      expect {
        save(components: [ { id: component.id, title: component.title, description: component.description }, blank_row ])
      }.not_to change { ssp.ssp_components.count }

      expect(response).to have_http_status(:unprocessable_content)
      expect(frame).to be_present
      expect(ssp.reload.description).not_to eq("Updated description")
    end

    it "names the row, outlines its field, and puts the message under it" do
      save(components: [ { id: component.id, title: component.title, description: component.description }, blank_row ])

      expect(error_lines).to eq([ "Component 2: Title is empty: fill it in, or remove the row" ])
      field = frame.at_css("#ssp-component-1-title")
      expect(field["class"].split).to include("is-invalid")
      expect(field["aria-invalid"]).to eq("true")
      expect(field["aria-describedby"]).to eq("ssp-component-1-title-error")
      expect(frame.at_css("#ssp-component-1-title-error").text).to eq("Title is empty: fill it in, or remove the row")
      expect(frame.at_css("#ssp-component-0-title")["class"].split).not_to include("is-invalid")
    end

    it "keeps everything the author typed, and offers to remove the added row" do
      save(description: "Typed but not saved",
           components: [ { id: component.id, title: "Renamed balancer", description: component.description }, blank_row ])

      expect(frame.at_css("#ssp_document_description").text.strip).to eq("Typed but not saved")
      expect(frame.at_css("#ssp-component-0-title")["value"]).to eq("Renamed balancer")
      added = frame.css(".component-entry")[1]
      expect(added.at_css("input[name='ssp_document[components][][id]']")).to be_nil
      expect(added.at_css("[data-testid=enrich-remove-row]")).to be_present
      expect(component.reload.title).to eq("Load balancer")
    end

    it "reports a blank added user row too, though a user needs no title once filled in" do
      save(users: [ { title: "", description: "", short_name: "" } ])

      expect(error_lines).to eq([ "User 1: Title is empty: fill it in, or remove the row" ])
    end
  end

  describe "a save that blanks an existing row" do
    it "names each refused field of that row, and saves none of the others" do
      save(information_types: [ { id: info_type.id, title: "", description: "" } ],
           components: [ { id: component.id, title: "Renamed balancer", description: component.description } ])

      expect(response).to have_http_status(:unprocessable_content)
      expect(error_lines).to contain_exactly("Information type 1: Title can't be blank",
                                             "Information type 1: Description can't be blank")
      expect(frame.at_css("#ssp-info-type-0-title")["aria-invalid"]).to eq("true")
      expect(frame.at_css("#ssp-info-type-0-description")["aria-invalid"]).to eq("true")
      expect(info_type.reload.title).to eq("Audit logs")
      expect(component.reload.title).to eq("Load balancer")
    end

    it "opens the section that holds the refused field" do
      save(information_types: [ { id: info_type.id, title: "", description: "Kept" } ])

      section = frame.at_css("details#enrich-information-types")
      expect(section.at_css(".is-invalid")).to be_present
      expect(frame.css("form[data-controller~='field-errors']")).to be_present
    end
  end

  it "keeps a removed row removed, and a this-system component it never showed" do
    this_system = ssp.ssp_components.create!(uuid: SecureRandom.uuid, component_type: SspComponent::THIS_SYSTEM,
                                             title: "This system", description: "The system itself")
    save(components: [])

    expect(ssp.ssp_components.reload).to contain_exactly(this_system)
  end
end
