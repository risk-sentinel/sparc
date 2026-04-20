require "rails_helper"

# Exercises #396 + #398 parse paths on SspJsonParserService:
#   - resolves statements[].links[rel=implements|inherited] into SspControlStatementInheritance
#   - upserts boundary-level LeveragedAuthorization from system-implementation.leveraged-authorizations[]
#   - tags set_parameters_data with provided/responsibility markers from nested by-components
RSpec.describe SspJsonParserService, "#396+#398 inheritance parsing" do
  let(:leveraged_b)  { create(:authorization_boundary) }
  let(:leveraged_ssp) do
    create(:ssp_document).tap { |d| d.update!(authorization_boundary: leveraged_b) }
  end
  let(:leveraged_ctrl) { create(:ssp_control, ssp_document: leveraged_ssp, control_id: "ac-2") }
  let!(:source_stmt) do
    create(:ssp_control_statement, ssp_control: leveraged_ctrl,
           statement_id: "ac-2_smt.a")
  end

  let(:leveraging_b)  { create(:authorization_boundary) }
  let(:leveraging_ssp) { create(:ssp_document, :oscal_import).tap { |d| d.update!(authorization_boundary: leveraging_b) } }

  let(:base_json) do
    {
      "system-security-plan" => {
        "uuid" => SecureRandom.uuid,
        "metadata" => { "title" => "Leveraging SSP", "version" => "1.0.0", "oscal-version" => "1.1.2" },
        "import-profile" => { "href" => "#" },
        "system-characteristics" => {
          "system-ids" => [ { "id" => "LEV-1" } ],
          "system-name" => "Leveraging",
          "security-sensitivity-level" => "fips-199-moderate",
          "system-information" => { "information-types" => [] },
          "security-impact-level" => { "security-objective-confidentiality" => "fips-199-moderate",
                                       "security-objective-integrity" => "fips-199-moderate",
                                       "security-objective-availability" => "fips-199-low" },
          "status" => { "state" => "operational" },
          "authorization-boundary" => { "description" => "x" }
        },
        "system-implementation" => {
          "users" => [],
          "components" => [],
          "leveraged-authorizations" => [
            {
              "uuid" => SecureRandom.uuid,
              "title" => "Example IaaS",
              "party-uuid" => SecureRandom.uuid,
              "date-authorized" => "2026-01-15",
              "links" => [ { "href" => "uuid:#{leveraged_ssp.uuid}", "rel" => "leveraged-system" } ]
            }
          ]
        },
        "control-implementation" => {
          "description" => "x",
          "implemented-requirements" => [
            {
              "uuid" => SecureRandom.uuid,
              "control-id" => "ac-2",
              "statements" => [
                {
                  "statement-id" => "ac-2_smt.a",
                  "uuid" => SecureRandom.uuid,
                  "remarks" => "Leveraging narrative",
                  "links" => [ { "href" => "uuid:#{source_stmt.uuid}", "rel" => "inherited" } ]
                }
              ]
            }
          ]
        }
      }
    }
  end

  it "creates boundary-level LeveragedAuthorization resolving the href" do
    # `leveraged_ssp.uuid` comes from the DB gen_random_uuid() default on
    # ssp_documents; it's populated on INSERT.
    base_json["system-security-plan"]["system-implementation"]["leveraged-authorizations"][0]["links"][0]["href"] =
      "uuid:#{leveraged_ssp.uuid}"

    parser = described_class.new(leveraging_ssp, nil)
    parser.parse_from_hash(base_json)

    la = LeveragedAuthorization.find_by(leveraging_boundary_id: leveraging_b.id)
    expect(la).to be_present
    expect(la.crm_type).to eq("oscal_with_access")
    expect(la.leveraged_boundary_id).to eq(leveraged_b.id)
  end

  it "creates SspControlStatementInheritance links from statements[].links[rel=inherited]" do
    parser = described_class.new(leveraging_ssp, nil)
    parser.parse_from_hash(base_json)

    leveraging_stmt = leveraging_ssp.ssp_controls.find_by(control_id: "ac-2")
                                    .ssp_control_statements.find_by(statement_id: "ac-2_smt.a")
    link = leveraging_stmt.inheritance_links.first
    expect(link).to be_present
    expect(link.source_type).to eq("SspControlStatement")
    expect(link.source_uuid).to eq(source_stmt.uuid)
  end

  it "falls back to oscal_no_access when the href cannot be resolved" do
    base_json["system-security-plan"]["system-implementation"]["leveraged-authorizations"][0]["links"][0]["href"] =
      "uuid:#{SecureRandom.uuid}"

    parser = described_class.new(leveraging_ssp, nil)
    parser.parse_from_hash(base_json)

    la = LeveragedAuthorization.find_by(leveraging_boundary_id: leveraging_b.id)
    expect(la.crm_type).to eq("oscal_no_access")
    expect(la.leveraged_boundary_id).to be_nil
  end
end
