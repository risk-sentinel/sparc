# frozen_string_literal: true

require "rails_helper"

RSpec.describe ReferenceEstateBuilder do
  # A small catalog carrying a handful of the lean set: two the platform
  # provides, one it hands back, and one with no statement at all — the
  # last matters because 5 of the real lean 40 (ac-2, ac-3, au-2, ca-7,
  # ia-2) genuinely have no catalog statement.
  let(:catalog) { create(:control_catalog, name: "Test Rev 5 Catalog") }
  let(:family)  { create(:control_family, control_catalog: catalog, code: "AC") }

  let!(:controls) do
    {
      "pe-3"  => "Control physical access to the system.",
      "sc-7"  => "Monitor communications at external boundaries.",
      "sa-9"  => "Require external providers to comply.",
      "ac-1"  => "Develop and document access control policy.",
      "ac-2"  => nil
    }.map do |control_id, statement|
      create(:catalog_control,
             control_family: family,
             control_id:     control_id,
             title:          "Control #{control_id.upcase}",
             guidance_data:  statement ? { "statement" => statement } : {})
    end
  end

  subject(:builder) { described_class.new(tier: :lean, catalog: catalog) }

  describe "#build" do
    it "refuses to run in production" do
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("production"))

      expect { builder.build }.to raise_error(described_class::UnsafeEnvironment, /will not run in production/)
    end

    it "rejects an unknown tier before touching the database" do
      expect { described_class.new(tier: :medium) }
        .to raise_error(ArgumentError, /unknown tier/)
    end

    it "builds two boundaries under two different organizations" do
      result = builder.build

      expect(result.leveraged[:organization]).not_to eq(result.leveraging[:organization])
      expect(result.leveraged[:boundary]).not_to eq(result.leveraging[:boundary])
      expect(result.tier).to eq(:lean)
    end

    it "gives each boundary the whole chain" do
      side = builder.build.leveraged

      expect(side[:profile].lifecycle_status).to eq("published")
      expect(side[:profile].resolved_catalog_json).to be_present
      expect(side[:ssp].ssp_controls.count).to eq(controls.size)
      expect(side[:sap]).to be_present
      expect(side[:sar].sar_results.first.sar_risks.count).to eq(controls.size)
      expect(side[:poams].size).to eq(3)
      expect(side[:evidence].size).to eq(3)
    end

    # #952 — SspFromProfileService leaves authorization_boundary_id nil, and a
    # nil boundary is treated as instance-wide and shown to every signed-in
    # user. An estate that reproduced that would be actively misleading.
    it "attaches every SSP to its boundary" do
      result = builder.build

      expect(result.leveraged[:ssp].authorization_boundary_id).to eq(result.leveraged[:boundary].id)
      expect(result.leveraging[:ssp].authorization_boundary_id).to eq(result.leveraging[:boundary].id)
    end

    it "creates statements only for controls the catalog gives one" do
      side = builder.build.leveraged
      statements = SspControlStatement.joins(:ssp_control)
                                      .where(ssp_controls: { ssp_document_id: side[:ssp].id })

      expect(statements.count).to eq(controls.size - 1)
      expect(statements.joins(:ssp_control).where(ssp_controls: { control_id: "ac-2" })).to be_empty
    end

    it "declares what the platform provides and what it hands back" do
      side = builder.build.leveraged
      statements = SspControlStatement.joins(:ssp_control)
                                      .where(ssp_controls: { ssp_document_id: side[:ssp].id })
                                      .includes(:ssp_control)

      tagged = statements.group_by { |s| s.set_parameters_data.first&.dig("tag") }

      expect(tagged["provided"].map { |s| s.ssp_control.control_id }).to contain_exactly("pe-3", "sc-7")
      expect(tagged["responsibility"].map { |s| s.ssp_control.control_id }).to contain_exactly("sa-9")
    end

    it "wires the leveraging boundary to inherit from the leveraged one" do
      result = builder.build

      expect(result.inheritance_links).to eq(3)
      authorization = LeveragedAuthorization.find_by(
        leveraging_boundary: result.leveraging[:boundary],
        leveraged_boundary:  result.leveraged[:boundary]
      )
      expect(authorization.crm_type).to eq("oscal_with_access")
      expect(authorization.scenario).to eq(1)
    end

    it "carries the platform's prose onto the leveraging system" do
      result = builder.build
      inherited = SspControlStatement
                    .joins(:ssp_control)
                    .where(ssp_controls: { ssp_document_id: result.leveraging[:ssp].id })
                    .find { |s| s.ssp_control.control_id == "pe-3" }

      expect(inherited.source_kind).to eq(:leveraged)
      expect(inherited.implementation_prose).to include("implemented centrally")
    end

    # An SLA-derived deadline is Time.current-relative. Left unpinned, every
    # regeneration of the committed OSCAL would carry a fresh diff.
    it "pins every deadline so regeneration does not churn" do
      side = builder.build.leveraged

      expect(side[:sar].sar_results.first.sar_risks.pluck(:deadline).uniq)
        .to eq([ described_class::PINNED_DEADLINE ])
    end

    it "gives the three POA&Ms genuinely different postures" do
      poams = builder.build.leveraged[:poams]

      expect(poams.map(&:lifecycle_status)).to contain_exactly("published", "in_progress", "in_progress")
      expect(poams.map { |p| p.poam_risks.first.deadline.to_date }.uniq.size).to eq(3)
      expect(poams).to all(satisfy { |p| p.poam_items.any? })
    end

    describe "idempotency" do
      it "creates nothing new on a second run" do
        builder.build
        counts = lambda do
          { ssp: SspDocument.count, poam: PoamDocument.count, sap: SapDocument.count,
            sar: SarDocument.count, boundary: AuthorizationBoundary.count,
            org: Organization.count, evidence: Evidence.count,
            profile: ProfileDocument.count,
            statements: SspControlStatement.count,
            links: SspControlStatementInheritance.count }
        end

        before = counts.call
        described_class.new(tier: :lean, catalog: catalog).build

        expect(counts.call).to eq(before)
      end

      it "still reports the same inheritance links on a re-run" do
        first  = builder.build.inheritance_links
        second = described_class.new(tier: :lean, catalog: catalog).build.inheritance_links

        expect(second).to eq(first)
      end
    end
  end

  describe "the full tier" do
    let(:full) { described_class.new(tier: :full, catalog: catalog) }

    it "sources its control ids from the real NIST baseline profiles" do
      low      = full.send(:baseline_control_ids, "LOW")
      moderate = full.send(:baseline_control_ids, "MODERATE")

      expect(low.size).to eq(149)
      expect(moderate.size).to eq(287)
      expect(low).to all(match(/\A[a-z]{2}-\d/))
      # MODERATE genuinely supersets LOW — that is what makes the pair a
      # meaningful leveraging relationship rather than two unrelated systems.
      expect(low - moderate).to be_empty
    end

    # Inheritance flows from the leveraged (providing) boundary to the
    # leveraging (consuming) one, so the PROVIDER must hold the superset. With
    # these reversed, 138 controls on the consumer would reference a platform
    # never assessed against them and could never be inherited.
    it "gives the providing boundary the higher baseline" do
      provider = full.send(:leveraged_spec)
      consumer = full.send(:leveraging_spec)

      expect(provider[:baseline]).to eq("moderate")
      expect(consumer[:baseline]).to eq("low")
      expect(provider[:control_ids].size).to eq(287)
      expect(consumer[:control_ids].size).to eq(149)
      expect(consumer[:control_ids] - provider[:control_ids]).to be_empty
    end
  end
end
