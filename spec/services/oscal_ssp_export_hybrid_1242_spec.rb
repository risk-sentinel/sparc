# frozen_string_literal: true

require "rails_helper"

# #1242 — the leveraging side of an inheritance, which the export never wrote.
# OSCAL carries what a statement takes from a leveraged system as
# `by-component.inherited` (pointing at the provider's `export.provided`) and
# the handed-back responsibility it meets as `satisfied` (pointing at the
# provider's `export.responsibilities`). A hybrid control carries both.
RSpec.describe OscalSspExportService, "#1242 inherited and satisfied" do
  # The validated path: the schema checks every field these emit.
  let!(:catalog_control) do
    catalog = create(:control_catalog)
    family  = create(:control_family, control_catalog: catalog, code: "AC")
    create(:catalog_control, control_family: family, control_id: "ac-2")
  end

  let(:ssp) { create(:ssp_document, :enriched) }
  let(:control) { create(:ssp_control, ssp_document: ssp, control_id: "ac-2") }
  let(:row) { create(:ssp_control_statement, ssp_control: control, statement_id: "ac-2_smt", implementation_prose: prose) }
  let(:prose) { nil }

  def provider(*tags)
    create(:ssp_control_statement, statement_id: "ac-2_smt", implementation_prose: "The provider's part.",
                                   set_parameters_data: tags.map { { "tag" => _1 } })
  end

  def leverage(source, overridden: false)
    create(:ssp_control_statement_inheritance, :from_ssp, ssp_control_statement: row, source: source,
                                                          source_uuid: source.uuid, overridden: overridden)
  end

  def by_component
    data = JSON.parse(OscalSspExportService.new(ssp.reload).export)
    statement = data.dig("system-security-plan", "control-implementation", "implemented-requirements")
                    .flat_map { Array(_1["statements"]) }.find { _1["statement-id"] == "ac-2_smt" }
    Array(statement&.dig("by-components")).first
  end

  it "writes inherited, pointing at the provider's provided uuid" do
    source = provider("provided")
    leverage(source)

    expect(by_component["inherited"]).to contain_exactly(
      include("provided-uuid" => OscalUuidService.derived(source.uuid, "ssp-statement-provided"))
    )
    expect(by_component).not_to have_key("satisfied")
  end

  it "writes no inherited once the author has replaced the provided text" do
    leverage(provider("provided"), overridden: true)
    expect(Array(by_component&.dig("inherited"))).to be_empty
  end

  context "a hybrid whose part this system has written" do
    let(:prose) { "This system's part." }

    it "writes inherited for the provider's part and satisfied for this system's, even once edited" do
      source = provider("provided", "responsibility")
      leverage(source, overridden: true)

      expect(by_component["inherited"].size).to eq(1)
      expect(by_component["satisfied"]).to contain_exactly(
        include("responsibility-uuid" => OscalUuidService.derived(source.uuid, "ssp-statement-responsibility"),
                "description" => "This system's part.")
      )
    end
  end

  it "writes no satisfied for a responsibility not yet written" do
    leverage(provider("responsibility"))
    expect(Array(by_component&.dig("satisfied"))).to be_empty
    expect(Array(by_component&.dig("inherited"))).to be_empty
  end
end

RSpec.describe SspJsonParserService, "#1242 reading satisfied" do
  def tags_for(by_component)
    described_class.allocate.send(:statement_set_parameters, "by-components" => [ by_component ])
                   .filter_map { _1["tag"] }
  end

  it "does not read a conformant satisfied (it names the responsibility it meets) as provided" do
    satisfied = [ { "uuid" => SecureRandom.uuid, "responsibility-uuid" => SecureRandom.uuid, "description" => "Met." } ]
    expect(tags_for("satisfied" => satisfied)).to be_empty
  end

  it "still reads the older shape, satisfied with no responsibility-uuid, as provided" do
    expect(tags_for("satisfied" => [ { "uuid" => SecureRandom.uuid, "description" => "Provided." } ])).to eq([ "provided" ])
  end
end

RSpec.describe CdefControlField, "#1242 control origin label" do
  it "labels a part-provided origin with NIST's term, keeping the stored value" do
    expect(described_class::CONTROL_ORIGIN_LABELS["shared"]).to eq("Hybrid")
  end
end
