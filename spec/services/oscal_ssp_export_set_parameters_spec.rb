# frozen_string_literal: true

require "rails_helper"

# #958 — `set-parameters` is not legal on an OSCAL statement, so emitting it
# there made EVERY SSP carrying one fail schema validation on export. Since
# SspJsonParserService parks its provided/responsibility markers in exactly
# that column, importing any leveraged SSP was enough to make the document
# unexportable.
RSpec.describe OscalSspExportService, "#958 statement set-parameters" do
  # #911 layer 2 refuses to export a control that resolves to no loaded
  # catalog, and these specs need the VALIDATED path — that is the whole
  # point, since export_unvalidated would sail past the bug being fixed.
  let!(:catalog_control) do
    catalog = create(:control_catalog)
    family  = create(:control_family, control_catalog: catalog, code: "AC")
    create(:catalog_control, control_family: family, control_id: "ac-2")
  end

  let(:boundary) { create(:authorization_boundary) }
  let(:ssp) do
    create(:ssp_document, :enriched).tap { |d| d.update!(authorization_boundary: boundary) }
  end
  let(:control) { create(:ssp_control, ssp_document: ssp, control_id: "ac-2") }

  def statement_for(json, statement_id)
    data = JSON.parse(json)
    data.dig("system-security-plan", "control-implementation", "implemented-requirements")
        .flat_map { |ir| Array(ir["statements"]) }
        .find { |s| s["statement-id"] == statement_id }
  end

  # The regression the issue is about: this raised before the fix.
  it "exports and validates when a statement carries the provided marker" do
    create(:ssp_control_statement, ssp_control: control, statement_id: "ac-2_smt",
           set_parameters_data: [ { "tag" => "provided" } ])

    expect { OscalSspExportService.new(ssp.reload).export }.not_to raise_error
  end

  it "exports and validates when a statement carries the responsibility marker" do
    create(:ssp_control_statement, ssp_control: control, statement_id: "ac-2_smt",
           set_parameters_data: [ { "tag" => "responsibility" } ])

    expect { OscalSspExportService.new(ssp.reload).export }.not_to raise_error
  end

  it "never emits set-parameters on a statement" do
    create(:ssp_control_statement, ssp_control: control, statement_id: "ac-2_smt",
           set_parameters_data: [ { "tag" => "provided" }, { "param-id" => "ac-2_prm_1", "values" => [ "30" ] } ])

    statement = statement_for(OscalSspExportService.new(ssp.reload).export, "ac-2_smt")

    expect(statement).not_to have_key("set-parameters")
  end

  # OSCAL models both under `by-component.export`, from the PROVIDER's point
  # of view — which is what a leveraged SSP is. `satisfied` is the mirror
  # image (the leveraging system declaring it met a responsibility) and does
  # not belong here.
  it "carries the provided marker to by-component.export.provided" do
    create(:ssp_control_statement, ssp_control: control, statement_id: "ac-2_smt",
           set_parameters_data: [ { "tag" => "provided" } ])

    statement = statement_for(OscalSspExportService.new(ssp.reload).export, "ac-2_smt")
    provided  = statement.dig("by-components", 0, "export", "provided")

    expect(provided).to be_present
    expect(provided.first).to include("uuid", "description")
    expect(statement.dig("by-components", 0)).not_to have_key("satisfied")
  end

  it "carries the responsibility marker to by-component.export.responsibilities" do
    create(:ssp_control_statement, ssp_control: control, statement_id: "ac-2_smt",
           set_parameters_data: [ { "tag" => "responsibility" } ])

    statement = statement_for(OscalSspExportService.new(ssp.reload).export, "ac-2_smt")

    expect(statement.dig("by-components", 0, "export", "responsibilities")).to be_present
  end

  # Genuine set-parameters must survive, on a by-component where OSCAL allows
  # them, rather than being dropped along with the internal markers.
  it "keeps a real set-parameter on the by-component" do
    create(:ssp_control_statement, ssp_control: control, statement_id: "ac-2_smt",
           set_parameters_data: [ { "param-id" => "ac-2_prm_1", "values" => [ "30" ] } ])

    statement = statement_for(OscalSspExportService.new(ssp.reload).export, "ac-2_smt")

    expect(statement.dig("by-components", 0, "set-parameters"))
      .to eq([ { "param-id" => "ac-2_prm_1", "values" => [ "30" ] } ])
  end

  it "leaks no SPARC-internal marker anywhere in the document" do
    create(:ssp_control_statement, ssp_control: control, statement_id: "ac-2_smt",
           set_parameters_data: [ { "tag" => "provided" }, { "tag" => "responsibility" } ])

    json = OscalSspExportService.new(ssp.reload).export

    expect(json).not_to include('"tag"')
  end

  it "adds no by-components when the statement carries nothing" do
    create(:ssp_control_statement, ssp_control: control, statement_id: "ac-2_smt",
           set_parameters_data: [])

    statement = statement_for(OscalSspExportService.new(ssp.reload).export, "ac-2_smt")

    expect(statement).not_to have_key("by-components")
  end

  it "names a component that actually exists in the document" do
    create(:ssp_control_statement, ssp_control: control, statement_id: "ac-2_smt",
           set_parameters_data: [ { "tag" => "provided" } ])

    data = JSON.parse(OscalSspExportService.new(ssp.reload).export)
    statement = statement_for(OscalSspExportService.new(ssp.reload).export, "ac-2_smt")
    declared  = data.dig("system-security-plan", "system-implementation", "components").map { |c| c["uuid"] }

    expect(declared).to include(statement.dig("by-components", 0, "component-uuid"))
  end
end
