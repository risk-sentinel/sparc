# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("scripts/generate_oscal_element_order")

# The ordering table OscalJsonToXmlConverter uses (#827) is generated from the
# OSCAL XSDs and committed, so it costs nothing at runtime and is reviewable in
# a diff. The risk of a committed generated file is that it silently stops
# matching its source — someone edits the table by hand, or updates
# lib/oscal_xsd_schemas/ for a new OSCAL revision without regenerating.
#
# This spec closes that gap by re-running the generator and comparing.
RSpec.describe "OSCAL element order table" do
  let(:committed) { JSON.parse(Rails.root.join("lib/oscal_element_order.json").read) }
  let(:generated) { OscalElementOrderGenerator.generate }

  it "matches what the generator produces from the committed XSDs" do
    expect(generated).to eq(committed),
      "lib/oscal_element_order.json is out of date with lib/oscal_xsd_schemas/. " \
      "Regenerate it: bundle exec ruby scripts/generate_oscal_element_order.rb"
  end

  it "covers every model the converter can export" do
    roots = committed.fetch("roots")

    OscalJsonToXmlConverter::ROOT_ELEMENTS.each_value do |root_element|
      # `mapping-collection` has no XSD shipped with the others; it is the one
      # root the converter accepts that this table cannot order. It must stay
      # visible here rather than silently degrading to insertion order.
      next if root_element == "mapping-collection"

      expect(roots).to include(root_element),
        "no ordering for <#{root_element}>, so its XML export falls back to JSON key order"
    end
  end

  describe "the facts the converter depends on" do
    let(:types) { committed.fetch("types") }

    # Ordering is per PARENT, not global. If these two ever agreed, a single
    # name-to-rank map would have been enough and the table would be overkill —
    # they do not, which is the whole reason it exists.
    it "orders `prop` differently under metadata than under param" do
      metadata = types.fetch("oscal-metadata-metadata-ASSEMBLY").fetch("order")
      param    = types.fetch("oscal-control-common-parameter-ASSEMBLY").fetch("order")

      expect(metadata.index("prop")).to be > 0
      expect(param.index("prop")).to eq(0)
    end

    # `name` is an attribute of <prop> but a child ELEMENT of <party>. A global
    # attribute list — which is what the converter used before #827 — cannot
    # represent that, and emitted <party name="..."/>, which the XSD rejects.
    it "treats `name` as an attribute of prop but not of party" do
      prop  = types.fetch("oscal-metadata-property-ASSEMBLY")
      party = types.fetch("oscal-metadata-metadata-ASSEMBLY/party")

      expect(prop.fetch("attributes")).to include("name")
      expect(party.fetch("attributes")).not_to include("name")
      expect(party.fetch("order")).to include("name")
    end

    # markup-line takes text directly and REJECTS a <p> child; markup-multiline
    # requires one. Emitting the wrong form is invalid either way.
    it "distinguishes markup-line from markup-multiline" do
      expect(types.fetch("MarkupLineDatatype").fetch("markup")).to eq("line")

      description = types.values.find { |t| t["markup"] == "multiline" }
      expect(description).not_to be_nil,
        "no multiline markup types found — prose would be emitted without <p>"
    end

    # A wrapper holds its repeated child (<revisions><revision/></revisions>);
    # `satisfied` merely repeats. Confusing the two nests elements wrongly.
    it "marks `revisions` as a wrapper but not `satisfied`" do
      revisions = types.fetch("oscal-metadata-metadata-ASSEMBLY/revisions")
      expect(revisions["wraps"]).to eq("revision")

      satisfied = types.values.find { |t| t["order"] == [ "description", "prop", "link", "responsible-role", "remarks" ] }
      expect(satisfied&.key?("wraps")).to be_falsey if satisfied
    end

    # The one fact the XSD cannot express: OSCAL JSON sometimes names a group
    # differently from its XML element.
    it "records the JSON group names that differ from their XML element" do
      aliases = committed.fetch("json_aliases")

      expect(aliases.fetch("remediations")).to include("response")
      expect(aliases.fetch("related-risks")).to include("associated-risk")
      expect(aliases.fetch("tasks")).to include("assessment-task")
    end
  end
end
