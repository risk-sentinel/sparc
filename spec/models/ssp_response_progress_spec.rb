# frozen_string_literal: true

require "rails_helper"

# #1242 — each required part is in exactly one state. The required set is given
# here; how it is derived from the baseline is spec/integration/
# ssp_response_progress_1242_spec.rb.
RSpec.describe SspResponseProgress do
  let(:ssp) { create(:ssp_document) }
  let(:ac1) { create(:ssp_control, ssp_document: ssp, control_id: "ac-1") }
  let(:required) { { "ac-1" => %w[ac-1_smt.a ac-1_smt.b] } }

  def progress(req = required) = described_class.new(ssp.reload, required: req)

  def statement(id, prose: nil, control: ac1)
    create(:ssp_control_statement, ssp_control: control, statement_id: id, implementation_prose: prose)
  end

  # A statement on a leveraged SSP, tagged as OSCAL's export marks it.
  def provider(*tags, prose: "The provider's implementation.")
    create(:ssp_control_statement, statement_id: "ac-1_smt.a", implementation_prose: prose,
                                   set_parameters_data: tags.map { { "tag" => _1 } })
  end

  def leverage(target, source, overridden: false)
    create(:ssp_control_statement_inheritance, :from_ssp, ssp_control_statement: target, source: source,
                                                          source_uuid: source.uuid, overridden: overridden)
  end

  def state(id) = progress.parts_for("ac-1").find { _1.part_id == id }.state

  it "counts a required part with no row as missing, rather than dropping it" do
    expect(progress.total.required).to eq(2)
    expect(progress.total.counts["missing"]).to eq(2)
    expect(progress.total.owed).to eq(2)
  end

  it "counts written text as implemented, and blank or whitespace text as missing" do
    statement("ac-1_smt.a", prose: "Invented implementation.")
    statement("ac-1_smt.b", prose: "  \n ")

    expect(state("ac-1_smt.a")).to eq("implemented")
    expect(state("ac-1_smt.b")).to eq("missing")
    expect(progress.total.done).to eq(1)
  end

  it "matches a control stored in another form (AC-01) to the baseline's id" do
    ac1.update_column(:control_id, "AC-01")
    statement("ac-1_smt.a", prose: "Invented implementation.")

    expect(state("ac-1_smt.a")).to eq("implemented")
  end

  it "does not count rows on an imported child control" do
    # The model refuses a second row for one control; a row written before
    # control ids were normalized (#911) can still spell it another way.
    child = create(:ssp_control, ssp_document: ssp, control_id: "ac-2", parent_id: ac1.id)
    child.update_column(:control_id, "AC-01")
    statement("ac-1_smt.a", prose: "Invented implementation.", control: child)

    expect(state("ac-1_smt.a")).to eq("missing")
  end

  describe "text filled from a CDEF" do
    let!(:row) { statement("ac-1_smt.a", prose: "The CDEF's text.") }
    let!(:link) { create(:ssp_control_statement_inheritance, ssp_control_statement: row) }

    it "is implemented and flagged until someone marks it reviewed" do
      expect(state("ac-1_smt.a")).to eq("implemented")
      expect(progress.total.cdef_unreviewed).to eq(1)

      link.mark_reviewed!(create(:user))
      expect(progress.total.cdef_unreviewed).to eq(0)
    end

    it "is no longer CDEF text once the author has edited it" do
      link.update!(overridden: true)
      expect(progress.total.cdef_unreviewed).to eq(0)
    end

    it "is missing when the CDEF filled nothing" do
      row.update!(implementation_prose: "")
      expect(state("ac-1_smt.a")).to eq("missing")
      expect(progress.total.cdef_unreviewed).to eq(0)
    end
  end

  describe "a leveraged statement the provider only provides" do
    let!(:row) { statement("ac-1_smt.a", prose: "The provider's implementation.") }

    it "is inherited while the link is active" do
      leverage(row, provider("provided"))
      expect(state("ac-1_smt.a")).to eq("inherited")
      expect(progress.total.owed).to eq(1) # only ac-1_smt.b
    end

    it "is this system's own once the author replaced it, and missing if they cleared it" do
      link = leverage(row, provider("provided"), overridden: true)
      expect(state("ac-1_smt.a")).to eq("implemented")

      row.update!(implementation_prose: "")
      link.reload
      expect(state("ac-1_smt.a")).to eq("missing")
    end
  end

  describe "a hybrid: the provider provides part and hands the rest back" do
    let!(:row) { statement("ac-1_smt.a") }
    before { leverage(row, provider("provided", "responsibility")) }

    it "is owed until this system writes its part, then satisfied" do
      expect(state("ac-1_smt.a")).to eq("hybrid_unsatisfied")
      expect(progress.total.owed).to eq(2)

      row.update!(implementation_prose: "This system's part.")
      expect(state("ac-1_smt.a")).to eq("hybrid_satisfied")
      expect(progress.total.owed).to eq(1)
    end
  end

  describe "a customer responsibility, with nothing provided" do
    let!(:row) { statement("ac-1_smt.a") }
    before { leverage(row, provider("responsibility")) }

    it "is owed until written, then implemented" do
      expect(state("ac-1_smt.a")).to eq("responsibility_unsatisfied")

      row.update!(implementation_prose: "This system implements it.")
      expect(state("ac-1_smt.a")).to eq("implemented")
    end
  end

  describe "text written above the parts that need it" do
    before { statement("ac-1_smt", prose: "One answer for the whole control.") }

    it "answers none of them, and is reported" do
      expect(progress.total.done).to eq(0)
      expect(progress.total.parent_level_text).to eq(1)
      expect(progress.parent_level_statement_ids.size).to eq(1)
    end

    it "is the response when the control has no parts" do
      expect(progress({ "ac-1" => %w[ac-1_smt] }).total.done).to eq(1)
      expect(progress({ "ac-1" => %w[ac-1_smt] }).total.parent_level_text).to eq(0)
    end
  end

  describe "per control" do
    before do
      statement("ac-1_smt.a", prose: "Invented.")
      statement("ac-1_smt.b", prose: "Invented.")
    end

    it "tallies one control, and is nil for a control the baseline does not select" do
      expect(progress.for_control("AC-1").to_h).to include("required" => 2, "done" => 2, "owed" => 0)
      expect(progress.for_control("AC-1")).to be_complete
      expect(progress.for_control("ac-99")).to be_nil
    end

    it "maps a required row to its part, and leaves other rows unmapped" do
      other = statement("ac-1_smt", prose: nil)
      row = ac1.ssp_control_statements.find_by(statement_id: "ac-1_smt.a")

      expect(progress.part_for_statement(row.id).state).to eq("implemented")
      expect(progress.part_for_statement(other.id)).to be_nil
    end
  end
end
