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
  end

  describe ".responsibility_gaps" do
    it "returns leveraged responsibility statements that aren't addressed on the leveraging side" do
      gaps = described_class.responsibility_gaps(la)
      expect(gaps.map(&:uuid)).to contain_exactly(responsibility_stmt.uuid)
    end

    it "excludes responsibilities that have been addressed via inheritance" do
      described_class.populate_from_leveraged!(la)
      gaps = described_class.responsibility_gaps(la)
      expect(gaps).to be_empty
    end
  end
end
