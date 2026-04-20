require "rails_helper"

RSpec.describe CdefToSspInheritanceService do
  let(:cdef_document) { create(:cdef_document) }
  let(:cdef_control)  { create(:cdef_control, cdef_document: cdef_document, control_id: "ac-2") }
  let!(:cdef_stmt)    { create(:cdef_control_statement, cdef_control: cdef_control,
                               statement_id: "ac-2_smt.a", implementation_prose: "CDEF prose A") }
  let!(:cdef_stmt_b)  { create(:cdef_control_statement, cdef_control: cdef_control,
                               statement_id: "ac-2_smt.b", implementation_prose: "CDEF prose B") }

  let(:ssp_document)  { create(:ssp_document) }
  let!(:ssp_control)  { create(:ssp_control, ssp_document: ssp_document, control_id: "ac-2") }

  # Suppress the SspComponent after_create_commit hook so we can exercise
  # the service directly and observe its return value. The hook itself
  # is covered by the ssp_component spec.
  before { ENV["SPARC_CDEF_AUTO_POPULATE"] = "false" }
  after  { ENV.delete("SPARC_CDEF_AUTO_POPULATE") }

  let(:ssp_component) do
    SspComponent.create!(
      ssp_document: ssp_document,
      cdef_document: cdef_document,
      uuid: SecureRandom.uuid,
      component_type: "software",
      title: "Example Component",
      description: "desc"
    )
  end

  describe ".populate_from_component!" do
    it "creates ssp_control_statements matching the CDEF statements" do
      expect do
        described_class.populate_from_component!(ssp_document, ssp_component)
      end.to change { ssp_control.reload.ssp_control_statements.count }.by(2)
    end

    it "creates inheritance links tagged with source_uuid" do
      described_class.populate_from_component!(ssp_document, ssp_component)
      ssp_stmt = ssp_control.ssp_control_statements.find_by(statement_id: "ac-2_smt.a")
      link = ssp_stmt.inheritance_links.first
      expect(link.source_type).to eq("CdefControlStatement")
      expect(link.source_uuid).to eq(cdef_stmt.uuid)
      expect(link.overridden).to be false
    end

    it "is idempotent" do
      described_class.populate_from_component!(ssp_document, ssp_component)
      expect do
        described_class.populate_from_component!(ssp_document, ssp_component)
      end.not_to change { SspControlStatementInheritance.count }
    end

    it "skips CDEF controls that don't match an SSP control" do
      # AC-3 is on CDEF only, not on SSP
      other_cdef_ctrl = create(:cdef_control, cdef_document: cdef_document, control_id: "ac-3")
      create(:cdef_control_statement, cdef_control: other_cdef_ctrl, statement_id: "ac-3_smt.a")
      described_class.populate_from_component!(ssp_document, ssp_component)
      expect(SspControl.where(control_id: "ac-3").count).to eq(0)
    end
  end

  describe ".refresh_from_cdef!" do
    before { described_class.populate_from_component!(ssp_document, ssp_component) }

    it "updates prose on non-overridden linked statements" do
      cdef_stmt.update!(implementation_prose: "updated CDEF prose A")
      described_class.refresh_from_cdef!(ssp_document, cdef_document)
      ssp_stmt = ssp_control.ssp_control_statements.find_by(statement_id: "ac-2_smt.a")
      expect(ssp_stmt.reload.implementation_prose).to eq("updated CDEF prose A")
    end

    it "leaves overridden statements untouched" do
      ssp_stmt = ssp_control.ssp_control_statements.find_by(statement_id: "ac-2_smt.a")
      ssp_stmt.inheritance_links.first.update!(overridden: true, overridden_prose: "kept")
      ssp_stmt.update!(implementation_prose: "kept")

      cdef_stmt.update!(implementation_prose: "updated CDEF prose A")
      described_class.refresh_from_cdef!(ssp_document, cdef_document)
      expect(ssp_stmt.reload.implementation_prose).to eq("kept")
    end
  end
end
