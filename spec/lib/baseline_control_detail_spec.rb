# frozen_string_literal: true

require "rails_helper"

# #997 — what a baseline requires of one control, assembled once for the
# Profile screen and the SSP screen. The rule these examples exist to hold is
# that PROSE IS ALWAYS RESOLVED: showing a reviewer
# `{{ insert: param, ac-20_odp.01 }}` is worse than showing nothing.
RSpec.describe BaselineControlDetail do
  let(:catalog) { create(:control_catalog) }
  let(:family)  { create(:control_family, control_catalog: catalog, code: "AC") }

  let(:control) do
    create(:catalog_control,
      control_family: family,
      control_id: "ac-20",
      title: "Use of External Systems",
      priority: "P2",
      guidance_data: {
        "statement" => "Establish {{ insert: param, ac-20_odp.01 }}, consistent with the trust relationships established with other organizations.",
        "supplemental_guidance" => "External systems are systems outside the authorization boundary.",
        "related_controls" => "ac-3, ac-17, sc-7"
      },
      params_data: [
        { "id" => "ac-20_odp.01", "label" => "terms and conditions" },
        { "id" => "ac-20_odp.02",
          "select" => { "how-many" => "one-or-more", "choice" => [ "removes", "disables" ] } }
      ])
  end

  describe "the resolution rule" do
    it "substitutes a set value into the statement" do
      detail = described_class.new(control, values: { "ac-20_odp.01" => "the Acme access terms" })

      expect(detail.statement).to include("Establish the Acme access terms,")
      expect(detail.statement).not_to include("insert:")
    end

    it "falls back to the parameter's own label when the profile has set nothing" do
      detail = described_class.new(control, values: {})

      expect(detail.statement).to include("terms and conditions")
      expect(detail.statement).not_to include("{{")
    end

    # The one thing that must never happen on either screen.
    it "never leaves insert markup in any string it hands to a template" do
      detail = described_class.new(control, values: { "ac-20_odp.01" => "x" })
      strings = [ detail.statement, detail.guidance ] +
                detail.parameters.flat_map { |p| [ p.display, *p.choices ] }

      expect(strings.compact.join(" ")).not_to match(/\{\{\s*insert/)
    end
  end

  describe "parameters" do
    it "lists every parameter the catalog defines, answered or not" do
      detail = described_class.new(control, values: { "ac-20_odp.01" => "x" })

      expect(detail.parameters.map(&:id)).to eq(%w[ac-20_odp.01 ac-20_odp.02])
      expect(detail.parameters.find { |p| p.id == "ac-20_odp.01" }).to be_answered
      expect(detail.parameters.find { |p| p.id == "ac-20_odp.02" }).not_to be_answered
    end

    it "marks a select as a select and resolves its choices for display" do
      detail = described_class.new(control, values: {})
      selection = detail.parameters.find { |p| p.id == "ac-20_odp.02" }

      expect(selection).to be_select
      expect(selection.how_many).to eq("one-or-more")
      expect(selection.choices).to eq(%w[removes disables])
    end

    # A selection stores WHICH branches were chosen, which is not the text the
    # control ends up asserting — so the screen shows the reading, not the row.
    it "reports a selection's resolved reading rather than its stored value" do
      detail = described_class.new(control, values: { "ac-20_odp.02" => "removes | disables" })
      selection = detail.parameters.find { |p| p.id == "ac-20_odp.02" }

      expect(selection.value).to eq("removes | disables")
      expect(selection.display).to eq("removes disables")
    end
  end

  describe "the rest of what a reviewer needs" do
    let(:detail) { described_class.new(control, values: {}) }

    it "carries the guidance" do
      expect(detail.guidance).to include("outside the authorization boundary")
    end

    it "splits related controls into ids" do
      expect(detail.related_controls).to eq(%w[ac-3 ac-17 sc-7])
    end

    it "prefers the profile's priority override to the catalog's" do
      expect(described_class.new(control, values: {}).priority).to eq("P2")
      expect(described_class.new(control, values: {}, priority: "P1").priority).to eq("P1")
    end
  end

  describe "#any?" do
    it "is false for a control with nothing to show, so no empty panel renders" do
      bare = create(:catalog_control, control_family: family, control_id: "ac-99",
                                      title: "Bare", guidance_data: {}, params_data: [])

      expect(described_class.new(bare, values: {})).not_to be_any
    end

    it "is true as soon as there is a statement" do
      expect(described_class.new(control, values: {})).to be_any
    end
  end
end
