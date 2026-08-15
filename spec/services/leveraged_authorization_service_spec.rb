require "rails_helper"

RSpec.describe LeveragedAuthorizationService do
  let(:leveraging_b) { create(:authorization_boundary) }
  let(:leveraged_b)  { create(:authorization_boundary) }

  let!(:leveraging_ssp) { create(:ssp_document).tap { |d| d.update!(authorization_boundary: leveraging_b) } }
  let!(:leveraged_ssp)  { create(:ssp_document).tap { |d| d.update!(authorization_boundary: leveraged_b) } }

  let!(:leveraging_ctrl) { create(:ssp_control, ssp_document: leveraging_ssp, control_id: "ac-2") }
  let!(:leveraged_ctrl)  { create(:ssp_control, ssp_document: leveraged_ssp, control_id: "ac-2") }

  # Leveraged-side statements tagged as provided/responsibility.
  let!(:provided_stmt) do
    create(:ssp_control_statement, ssp_control: leveraged_ctrl,
           statement_id: "ac-2_smt.a",
           implementation_prose: "Leveraged prose A",
           set_parameters_data: [ { "tag" => "provided" } ])
  end
  let!(:responsibility_stmt) do
    create(:ssp_control_statement, ssp_control: leveraged_ctrl,
           statement_id: "ac-2_smt.b",
           implementation_prose: "Customer must configure MFA",
           set_parameters_data: [ { "tag" => "responsibility" } ])
  end

  let(:la) do
    create(:leveraged_authorization,
           leveraging_boundary: leveraging_b,
           leveraged_boundary: leveraged_b)
  end

  describe ".populate_from_leveraged!" do
    it "creates statements + inheritance links on the leveraging SSP" do
      expect do
        described_class.populate_from_leveraged!(la)
      end.to change { leveraging_ctrl.reload.ssp_control_statements.count }.by(2)

      link = SspControlStatementInheritance
               .where(source_type: "SspControlStatement", source_id: provided_stmt.id).first
      expect(link).to be_present
      expect(link.source_uuid).to eq(provided_stmt.uuid)
    end

    it "no-ops for non-scenario-1 (oscal_no_access)" do
      la.update!(crm_type: "oscal_no_access", leveraged_boundary: nil)
      expect(described_class.populate_from_leveraged!(la)).to eq(0)
    end

    it "is idempotent" do
      described_class.populate_from_leveraged!(la)
      expect do
        described_class.populate_from_leveraged!(la)
      end.not_to change { SspControlStatementInheritance.count }
    end

    # #955 made profile-generated SSPs arrive with statements already
    # scaffolded, so the leveraging target is no longer a new record. The
    # old new_record?-only guard then linked the statement and left it empty.
    context "when the leveraging SSP already has the statement scaffolded" do
      let!(:scaffolded) do
        create(:ssp_control_statement, ssp_control: leveraging_ctrl,
               statement_id: "ac-2_smt.a",
               implementation_prose: nil)
      end

      it "fills blank prose from the source instead of leaving it empty" do
        described_class.populate_from_leveraged!(la)

        expect(scaffolded.reload.implementation_prose).to eq("Leveraged prose A")
      end

      it "still creates the inheritance link" do
        expect { described_class.populate_from_leveraged!(la) }
          .to change { scaffolded.inheritance_links.count }.by(1)
        expect(scaffolded.reload.source_kind).to eq(:leveraged)
      end

      it "never clobbers prose the author has already written" do
        scaffolded.update!(implementation_prose: "Our own implementation")

        described_class.populate_from_leveraged!(la)

        expect(scaffolded.reload.implementation_prose).to eq("Our own implementation")
      end

      it "leaves blank prose alone when the source has none either" do
        provided_stmt.update!(implementation_prose: nil)

        described_class.populate_from_leveraged!(la)

        expect(scaffolded.reload.implementation_prose).to be_blank
      end
    end
  end

  describe ".responsibility_gaps" do
    it "returns leveraged responsibility statements that aren't addressed on the leveraging side" do
      gaps = described_class.responsibility_gaps(la)
      expect(gaps.map(&:uuid)).to contain_exactly(responsibility_stmt.uuid)
    end

    # #956 — this spec previously asserted the OPPOSITE: that populating
    # cleared the gap. It pinned the defect rather than catching it, so it is
    # deliberately rewritten rather than deleted. Populating creates an
    # inheritance link, and a link records where a responsibility came FROM;
    # it says nothing about whether anyone has acted on it.
    it "still reports the gap after populating — a link is not an implementation" do
      described_class.populate_from_leveraged!(la)

      gaps = described_class.responsibility_gaps(la)

      expect(gaps.map(&:uuid)).to contain_exactly(responsibility_stmt.uuid)
    end

    # The half that mattered more: doing the right thing used to CREATE a gap.
    it "clears the gap once the leveraging system implements it itself" do
      described_class.populate_from_leveraged!(la)
      target = leveraging_ctrl.ssp_control_statements.find_by(statement_id: responsibility_stmt.statement_id)
      target.inheritance_links.each { |l| l.update!(overridden: true, overridden_prose: "ours") }
      target.update!(implementation_prose: "We enforce MFA ourselves.")

      expect(described_class.responsibility_gaps(la)).to be_empty
    end

    it "counts prose authored with no inheritance link at all as addressing it" do
      create(:ssp_control_statement, ssp_control: leveraging_ctrl,
             statement_id: responsibility_stmt.statement_id,
             implementation_prose: "We enforce MFA ourselves.")

      expect(described_class.responsibility_gaps(la)).to be_empty
    end

    it "does not count a blank statement as addressing it" do
      described_class.populate_from_leveraged!(la)
      target = leveraging_ctrl.ssp_control_statements.find_by(statement_id: responsibility_stmt.statement_id)
      target.update!(implementation_prose: "")

      expect(described_class.responsibility_gaps(la).map(&:uuid)).to contain_exactly(responsibility_stmt.uuid)
    end

    # Documents populated BEFORE this fix carry the provider's "you must do
    # this" text as their own prose, with a still-active link. That prose is
    # not an implementation and must not clear the gap — which is the whole
    # reason `addressed?` inspects the link rather than trusting prose alone.
    it "does not count inherited prose on an active link as addressing it" do
      described_class.populate_from_leveraged!(la)
      target = leveraging_ctrl.ssp_control_statements.find_by(statement_id: responsibility_stmt.statement_id)
      target.update!(implementation_prose: responsibility_stmt.implementation_prose)

      expect(target.inheritance_links.map(&:overridden?)).to eq([ false ])
      expect(described_class.responsibility_gaps(la).map(&:uuid)).to contain_exactly(responsibility_stmt.uuid)
    end

    # Overriding and then clearing the prose leaves an overridden link with
    # nothing behind it. The override alone must not count.
    it "reopens the gap when an implemented responsibility is emptied again" do
      described_class.populate_from_leveraged!(la)
      target = leveraging_ctrl.ssp_control_statements.find_by(statement_id: responsibility_stmt.statement_id)
      target.inheritance_links.each { |l| l.update!(overridden: true, overridden_prose: "ours") }
      target.update!(implementation_prose: "We enforce MFA ourselves.")
      expect(described_class.responsibility_gaps(la)).to be_empty

      target.update!(implementation_prose: "")

      expect(described_class.responsibility_gaps(la).map(&:uuid)).to contain_exactly(responsibility_stmt.uuid)
    end

    it "never treats a provided statement as a responsibility gap" do
      described_class.populate_from_leveraged!(la)

      expect(described_class.responsibility_gaps(la).map(&:uuid)).not_to include(provided_stmt.uuid)
    end
  end

  # #956 — a responsibility says "the customer must do this". Copying that in
  # as the customer's own implementation asserts the opposite, and it was
  # visible on screen: the leveraging SSP read "The reference platform does
  # not implement AC-20" as its own narrative.
  describe "prose inheritance by tag" do
    before { described_class.populate_from_leveraged!(la) }

    it "inherits prose for a provided statement" do
      target = leveraging_ctrl.ssp_control_statements.find_by(statement_id: provided_stmt.statement_id)

      expect(target.implementation_prose).to eq("Leveraged prose A")
      expect(target.source_kind).to eq(:leveraged)
    end

    it "leaves a responsibility statement blank for the customer to author" do
      target = leveraging_ctrl.ssp_control_statements.find_by(statement_id: responsibility_stmt.statement_id)

      expect(target.implementation_prose).to be_blank
      expect(target.source_kind).to eq(:responsibility)
    end

    it "marks an implemented responsibility distinctly from an inherited one" do
      target = leveraging_ctrl.ssp_control_statements.find_by(statement_id: responsibility_stmt.statement_id)
      target.inheritance_links.each { |l| l.update!(overridden: true, overridden_prose: "ours") }
      target.update!(implementation_prose: "We enforce MFA ourselves.")

      expect(target.reload.source_kind).to eq(:overridden_responsibility)
    end
  end
end
