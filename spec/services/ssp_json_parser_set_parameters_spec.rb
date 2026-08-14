# frozen_string_literal: true

require "rails_helper"

# #958 — the provided/responsibility markers are read from
# `by-component.export`, which is where OSCAL models them and where SPARC's
# own exporter now writes them. Without this the round-trip is broken: a SPARC
# export could not be re-imported as the thing it was.
#
# The older shapes (`satisfied` / `responsibilities` directly on the
# by-component) stay supported, because documents imported before the fix
# carry them and dropping support would silently reclassify their statements.
RSpec.describe SspJsonParserService, "#958 provided/responsibility markers" do
  let(:boundary) { create(:authorization_boundary) }
  let(:ssp) { create(:ssp_document, :oscal_import).tap { |d| d.update!(authorization_boundary: boundary) } }

  def json_with(by_component)
    {
      "system-security-plan" => {
        "uuid" => SecureRandom.uuid,
        "metadata" => { "title" => "Probe", "version" => "1.0.0", "oscal-version" => "1.1.2" },
        "import-profile" => { "href" => "#" },
        "system-characteristics" => {
          "system-ids" => [ { "id" => "P-1" } ],
          "system-name" => "Probe",
          "security-sensitivity-level" => "fips-199-moderate",
          "system-information" => { "information-types" => [] },
          "status" => { "state" => "operational" },
          "authorization-boundary" => { "description" => "n/a" }
        },
        "system-implementation" => { "users" => [], "components" => [] },
        "control-implementation" => {
          "description" => "n/a",
          "implemented-requirements" => [
            {
              "uuid" => SecureRandom.uuid,
              "control-id" => "ac-2",
              "statements" => [
                { "statement-id" => "ac-2_smt", "uuid" => SecureRandom.uuid,
                  "by-components" => [ by_component ] }
              ]
            }
          ]
        }
      }
    }
  end

  def markers_for(document)
    document.ssp_controls.find_by(control_id: "ac-2")
            .ssp_control_statements.find_by(statement_id: "ac-2_smt")
            .set_parameters_data
  end

  def component(extra)
    { "component-uuid" => SecureRandom.uuid, "uuid" => SecureRandom.uuid,
      "description" => "by component" }.merge(extra)
  end

  it "reads provided from by-component.export.provided" do
    described_class.new(ssp, nil).parse_from_hash(
      json_with(component("export" => { "provided" => [ { "uuid" => SecureRandom.uuid, "description" => "p" } ] }))
    )

    expect(markers_for(ssp.reload)).to include("tag" => "provided")
  end

  it "reads responsibility from by-component.export.responsibilities" do
    described_class.new(ssp, nil).parse_from_hash(
      json_with(component("export" => { "responsibilities" => [ { "uuid" => SecureRandom.uuid, "description" => "r" } ] }))
    )

    expect(markers_for(ssp.reload)).to include("tag" => "responsibility")
  end

  it "reads both when the by-component exports both" do
    described_class.new(ssp, nil).parse_from_hash(
      json_with(component("export" => {
        "provided" => [ { "uuid" => SecureRandom.uuid, "description" => "p" } ],
        "responsibilities" => [ { "uuid" => SecureRandom.uuid, "description" => "r" } ]
      }))
    )

    expect(markers_for(ssp.reload)).to contain_exactly({ "tag" => "provided" }, { "tag" => "responsibility" })
  end

  it "still reads the pre-fix shapes so older documents keep working" do
    described_class.new(ssp, nil).parse_from_hash(
      json_with(component("satisfied" => [ { "uuid" => SecureRandom.uuid, "description" => "s" } ],
                          "responsibilities" => [ { "uuid" => SecureRandom.uuid, "description" => "r" } ]))
    )

    expect(markers_for(ssp.reload)).to contain_exactly({ "tag" => "provided" }, { "tag" => "responsibility" })
  end

  it "records no marker when the by-component exports neither" do
    described_class.new(ssp, nil).parse_from_hash(json_with(component({})))

    expect(markers_for(ssp.reload)).to be_empty
  end

  it "does not duplicate a marker across several by-components" do
    two = json_with(component("export" => { "provided" => [ { "uuid" => SecureRandom.uuid, "description" => "p" } ] }))
    statement = two.dig("system-security-plan", "control-implementation", "implemented-requirements", 0, "statements", 0)
    statement["by-components"] << component("export" => { "provided" => [ { "uuid" => SecureRandom.uuid, "description" => "p2" } ] })

    described_class.new(ssp, nil).parse_from_hash(two)

    expect(markers_for(ssp.reload)).to eq([ { "tag" => "provided" } ])
  end
end
