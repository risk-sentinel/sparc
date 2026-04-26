# frozen_string_literal: true

require "rails_helper"

RSpec.describe "PoamItems", type: :request do
  let(:user)  { create(:user) }
  let(:poam)  { create(:poam_document, name: "Test POAM") }

  before { sign_in_as(user) }

  describe "POST /poam_documents/:poam_document_id/poam_items (#389 props/links)" do
    let(:base_attrs) do
      {
        title: "Test Item",
        description: "Item description",
        risk_status: "open"
      }
    end

    it "creates an item with props_data and links_data persisted as JSONB arrays" do
      post poam_document_poam_items_path(poam), params: {
        poam_item: base_attrs.merge(
          props_data: [
            { name: "severity", value: "high", class: "" },
            { name: "tracking_id", value: "TRK-42", class: "internal" }
          ],
          links_data: [
            { href: "https://example.gov/policy.pdf", rel: "reference",
              media_type: "application/pdf", text: "Policy" }
          ]
        )
      }

      item = poam.poam_items.find_by(title: "Test Item")
      expect(item).to be_present
      expect(item.props_data).to eq([
        { "name" => "severity", "value" => "high" },
        { "name" => "tracking_id", "value" => "TRK-42", "class" => "internal" }
      ])
      expect(item.links_data).to eq([
        { "href" => "https://example.gov/policy.pdf", "rel" => "reference",
          "media-type" => "application/pdf", "text" => "Policy" }
      ])
    end

    it "drops empty rows and converts media_type to OSCAL hyphen form" do
      post poam_document_poam_items_path(poam), params: {
        poam_item: base_attrs.merge(
          title: "Drops Empty Rows",
          props_data: [
            { name: "valid", value: "yes", class: "" },     # kept
            { name: "",      value: "",    class: "" },     # dropped (empty row)
            { name: "no_value", value: "", class: "" },     # dropped (no value)
            { name: "",      value: "no_name", class: "" }  # dropped (no name)
          ],
          links_data: [
            { href: "https://kept.gov", media_type: "text/html", rel: "reference" },
            { href: "",                 media_type: "text/html", rel: "reference" }, # dropped
            { href: "https://min.gov" } # kept, only required field
          ]
        )
      }

      item = poam.poam_items.find_by(title: "Drops Empty Rows")
      expect(item.props_data.size).to eq(1)
      expect(item.props_data.first["name"]).to eq("valid")
      expect(item.links_data.size).to eq(2)
      expect(item.links_data.first["media-type"]).to eq("text/html")
      expect(item.links_data.first).not_to have_key("media_type")
    end

    it "creates an item with neither props nor links" do
      post poam_document_poam_items_path(poam), params: { poam_item: base_attrs }

      item = poam.poam_items.find_by(title: "Test Item")
      expect(item).to be_present
      expect(item.props_data).to eq([])
      expect(item.links_data).to eq([])
    end
  end

  describe "PATCH /poam_documents/:poam_document_id/poam_items/:id (#389)" do
    let!(:item) do
      create(:poam_item, poam_document: poam, title: "Existing",
             props_data: [ { "name" => "old", "value" => "1" } ],
             links_data: [ { "href" => "https://old.gov" } ])
    end

    it "replaces props_data and links_data wholesale" do
      patch poam_document_poam_item_path(poam, item), params: {
        poam_item: {
          title: "Existing",
          props_data: [ { name: "new", value: "2" } ],
          links_data: [ { href: "https://new.gov", media_type: "text/html" } ]
        }
      }

      item.reload
      expect(item.props_data).to eq([ { "name" => "new", "value" => "2" } ])
      expect(item.links_data).to eq([ { "href" => "https://new.gov", "media-type" => "text/html" } ])
    end

    it "does not touch props/links when params omit those keys" do
      original_props = item.props_data
      original_links = item.links_data

      patch poam_document_poam_item_path(poam, item), params: {
        poam_item: { title: "Renamed" }
      }

      item.reload
      expect(item.title).to eq("Renamed")
      expect(item.props_data).to eq(original_props)
      expect(item.links_data).to eq(original_links)
    end
  end
end
