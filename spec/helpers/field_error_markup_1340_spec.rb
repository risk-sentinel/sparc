# frozen_string_literal: true

require "rails_helper"

# #1340 — a field a record-backed form re-renders with an error is outlined,
# flagged invalid, and carries its message, with no change to the form.
RSpec.describe "field_error_proc (#1340)", type: :helper do
  let(:document) { SspDocument.new.tap { _1.errors.add(:name, "can't be blank") } }

  def render_form
    helper.form_with(model: document, url: "/x") do |f|
      f.label(:name) + f.text_field(:name) + f.hidden_field(:name, id: "hidden_name")
    end
  end

  let(:html) { Nokogiri::HTML5.fragment(render_form) }

  it "outlines the field, flags it, and points it at its message" do
    field = html.at_css("input#ssp_document_name")

    expect(field["class"].split).to include("is-invalid")
    expect(field["aria-invalid"]).to eq("true")
    expect(field["aria-describedby"]).to eq("ssp_document_name-error")
    expect(html.at_css("#ssp_document_name-error").text).to eq("Name can't be blank")
  end

  it "leaves the label and hidden fields alone, and adds no field_with_errors wrapper" do
    expect(html.at_css("label")["class"].to_s).not_to include("is-invalid")
    expect(html.at_css("input#hidden_name")["aria-invalid"]).to be_nil
    expect(html.css(".field_with_errors")).to be_empty
  end

  it "escapes the message" do
    document.errors.add(:system_id, "<script>x</script>")
    out = helper.form_with(model: document, url: "/x") { |f| f.text_field(:system_id) }

    expect(out).not_to include("<script>")
    expect(out).to include("&lt;script&gt;")
  end
end
