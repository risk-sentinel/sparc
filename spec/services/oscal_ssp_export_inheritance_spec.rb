require "rails_helper"

# Exercises #396 + #398 export paths on OscalSspExportService:
#   - statement emits link[rel="implements"] for CDEF source
#   - statement emits link[rel="inherited"] for leveraged source
#   - leveraged-authorizations[] merges legacy + boundary-level records
RSpec.describe OscalSspExportService, "#396+#398 inheritance export" do
  let(:leveraging_b) { create(:authorization_boundary) }
  let(:leveraged_b)  { create(:authorization_boundary) }

  let(:ssp) do
    create(:ssp_document, :enriched).tap { |d| d.update!(authorization_boundary: leveraging_b) }
  end
  let(:leveraged_ssp) { create(:ssp_document).tap { |d| d.update!(authorization_boundary: leveraged_b) } }

  let(:ctrl) { create(:ssp_control, ssp_document: ssp, control_id: "ac-2") }

  it "emits link[rel=implements] with uuid:<source_uuid> when statement is inherited from a CDEF" do
    cdef_stmt = create(:cdef_control_statement, implementation_prose: "from CDEF")
    stmt = create(:ssp_control_statement, ssp_control: ctrl,
                  implementation_prose: "from CDEF", statement_id: "ac-2_smt.a")
    create(:ssp_control_statement_inheritance,
           ssp_control_statement: stmt, source: cdef_stmt, source_uuid: cdef_stmt.uuid)

    json = OscalSspExportService.new(ssp.reload).export_unvalidated
    data = JSON.parse(json)
    ir = data.dig("system-security-plan", "control-implementation", "implemented-requirements").find { |r| r["control-id"] == "ac-2" }
    s = ir["statements"].find { |s| s["statement-id"] == "ac-2_smt.a" }

    expect(s["links"]).to include("href" => "uuid:#{cdef_stmt.uuid}", "rel" => "implements")
  end

  it "emits link[rel=inherited] for leveraged SSP source" do
    source_stmt = create(:ssp_control_statement, statement_id: "ac-2_smt.b")
    stmt = create(:ssp_control_statement, ssp_control: ctrl, statement_id: "ac-2_smt.b")
    create(:ssp_control_statement_inheritance, :from_ssp,
           ssp_control_statement: stmt, source: source_stmt, source_uuid: source_stmt.uuid)

    json = OscalSspExportService.new(ssp.reload).export_unvalidated
    data = JSON.parse(json)
    ir = data.dig("system-security-plan", "control-implementation", "implemented-requirements").find { |r| r["control-id"] == "ac-2" }
    s = ir["statements"].find { |s| s["statement-id"] == "ac-2_smt.b" }

    expect(s["links"]).to include("href" => "uuid:#{source_stmt.uuid}", "rel" => "inherited")
  end

  it "emits boundary-level leveraged-authorization entries" do
    la = create(:leveraged_authorization,
                leveraging_boundary: leveraging_b,
                leveraged_boundary: leveraged_b,
                name: "Example IaaS")

    json = OscalSspExportService.new(ssp.reload).export_unvalidated
    data = JSON.parse(json)
    las = data.dig("system-security-plan", "system-implementation", "leveraged-authorizations")
    expect(las).to be_present
    expect(las.map { |e| e["uuid"] }).to include(la.uuid)
    expect(las.find { |e| e["uuid"] == la.uuid }["title"]).to eq("Example IaaS")
  end
end
