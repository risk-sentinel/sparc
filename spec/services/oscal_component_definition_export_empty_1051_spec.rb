# frozen_string_literal: true

require "rails_helper"

# #1051 — a CDEF with ZERO controls exported schema-invalid OSCAL.
#
# 163 of 232 documents (70% of the library) failed on one constraint:
#
#   /component-definition/components/0/control-implementations/0/
#     implemented-requirements: array size is less than: 1
#
# The exporter built a `control-implementations` scaffold unconditionally, so a
# document with no controls wrapped an EMPTY `implemented-requirements` array,
# which OSCAL forbids. All 163 are AWS Labs service CDEFs (#466, #939) carrying
# no control mappings.
#
# THIS FILE EXISTS BECAUSE ITS ABSENCE IS WHY THE BUG SURVIVED. Every other
# per-type export spec builds its fixture WITH controls — including the sibling
# spec for this very service, whose `before` block creates one — so the empty
# case was exercised nowhere.
RSpec.describe OscalComponentDefinitionExportService, "a CDEF with no controls (#1051)" do
  let(:cdef) do
    create(:cdef_document,
           name: "AWS aws_regions",
           cdef_type: "custom",
           cdef_version: "1.0.0")
  end

  subject(:service) { described_class.new(cdef) }

  it "has no controls — the precondition this file is about" do
    expect(cdef.cdef_controls).to be_empty
  end

  it "exports OSCAL that validates at the default schema version" do
    expect { service.export }.not_to raise_error,
      "a control-less CDEF still exports an empty implemented-requirements " \
      "array, which OSCAL forbids (#1051)"
  end

  it "omits control-implementations rather than emitting an empty scaffold" do
    component = JSON.parse(service.export)
                    .dig("component-definition", "components", 0)

    expect(component).not_to have_key("control-implementations"),
      "a component with no controls must omit control-implementations — an " \
      "empty implemented-requirements array is invalid, and claiming an " \
      "implementation that does not exist would be worse"
  end

  it "still exports exactly one component — OSCAL requires at least one" do
    components = JSON.parse(service.export).dig("component-definition", "components")

    expect(components.length).to eq(1)
    expect(components.first["title"]).to be_present
  end

  # The honest-export point: omitting the key says "this maps no controls",
  # which is true, rather than asserting an empty implementation.
  it "keeps the component's own metadata intact" do
    component = JSON.parse(service.export).dig("component-definition", "components", 0)

    expect(component["uuid"]).to be_present
    expect(component["type"]).to be_present
    expect(component["description"]).to be_present
  end
end
