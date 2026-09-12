# frozen_string_literal: true

require "rails_helper"

# #940 — the completeness report, as the owner reframed it: "How complete is the
# boundary's documentation… and what does SPARC know about it (Profile, SSP,
# Metadata, Back Matter, CDEFs, Evidence, all personnel identified, 1 to n
# environments documented)."
RSpec.describe BoundaryReadinessService do
  let(:boundary) { create(:authorization_boundary) }

  def status_of(key)
    described_class.new(boundary.reload).sections.find { |s| s.key == key }&.status
  end

  describe "an empty boundary" do
    it "reports every answerable section as absent rather than guessing" do
      answerable = described_class.new(boundary).sections.reject { |s| s.status == :not_modelled }

      expect(answerable.map(&:status).uniq).to eq([ :absent ])
    end

    it "never raises when the SSP does not exist yet" do
      expect { described_class.new(boundary).report }.not_to raise_error
    end
  end

  describe "personnel" do
    it "is absent with no roster" do
      expect(status_of(:personnel)).to eq(:absent)
    end

    # The three roles without which nobody can act on the boundary.
    it "is PARTIAL when someone is on the roster but the required roles are not all filled" do
      create(:authorization_boundary_membership, authorization_boundary: boundary, role: "isso")

      expect(status_of(:personnel)).to eq(:partial)
    end

    it "is complete once System Owner, ISSO and AO are all present" do
      %w[system_owner isso authorizing_official].each do |role|
        create(:authorization_boundary_membership, authorization_boundary: boundary, role: role)
      end

      expect(status_of(:personnel)).to eq(:complete)
    end
  end

  describe "components" do
    let!(:ssp) { create(:ssp_document, authorization_boundary: boundary) }

    # Typing everything `this-system` is the path of least resistance, and it
    # costs the ability to say what is inherited, shared or operated. The report
    # says partial rather than congratulating the boundary.
    it "is PARTIAL when every component is typed this-system" do
      create(:ssp_component, ssp_document: ssp, component_type: "this-system",
                             protocols_data: [ { "name" => "https", "port" => 443 } ])

      expect(status_of(:components)).to eq(:partial)
    end

    it "is PARTIAL when components carry no ports or protocols" do
      create(:ssp_component, ssp_document: ssp, component_type: "software", protocols_data: nil)

      expect(status_of(:components)).to eq(:partial)
    end

    it "is complete when components are differentiated AND carry protocols" do
      create(:ssp_component, ssp_document: ssp, component_type: "software",
                             protocols_data: [ { "name" => "https", "port" => 443 } ])
      create(:ssp_component, ssp_document: ssp, component_type: "this-system",
                             protocols_data: [ { "name" => "ssh", "port" => 22 } ])

      expect(status_of(:components)).to eq(:complete)
    end
  end

  describe "evidence" do
    it "is absent with none uploaded" do
      expect(status_of(:evidence)).to eq(:absent)
    end

    it "is complete once evidence exists" do
      create(:evidence, authorization_boundary: boundary)

      expect(status_of(:evidence)).to eq(:complete)
    end

    # There is no `partial` state for evidence, and this is why: the model
    # refuses to save evidence with no control link at all, so "uploaded but
    # linked to nothing" is unreachable. A readiness check for it would be dead
    # code wearing the costume of a check.
    it "cannot exist unlinked — the invariant is enforced at the model" do
      expect {
        create(:evidence, :without_control_links, authorization_boundary: boundary)
      }.to raise_error(ActiveRecord::RecordInvalid, /Link at least one control/)
    end
  end

  # #940 S3 made the boundary authoritative for categorization, so the report
  # reads it there — and can now say something no earlier version could.
  describe "classification" do
    it "is absent with no categorization and no information types" do
      expect(status_of(:classification)).to eq(:absent)
    end

    # A level recorded by hand with nothing justifying it is not complete — the
    # SP 800-60 information types ARE the justification.
    it "is PARTIAL when a level is recorded but no information type justifies it" do
      boundary.update!(security_objective_confidentiality: "fips-199-moderate")

      expect(status_of(:classification)).to eq(:partial)
    end

    it "is complete when information types derive the level" do
      create(:ssp_document, authorization_boundary: boundary)
      SspInformationType.create!(
        ssp_document: boundary.ssp_document, authorization_boundary: boundary,
        uuid: SecureRandom.uuid, title: "T", description: "D",
        confidentiality_impact_selected: "fips-199-moderate"
      )

      expect(status_of(:classification)).to eq(:complete)
    end

    # The condition that was undetectable before S3.
    it "is PARTIAL and says so when the recorded objectives contradict the types" do
      create(:ssp_document, authorization_boundary: boundary)
      boundary.update!(security_objective_confidentiality: "fips-199-low")
      SspInformationType.create!(
        ssp_document: boundary.ssp_document, authorization_boundary: boundary,
        uuid: SecureRandom.uuid, title: "T", description: "D",
        confidentiality_impact_selected: "fips-199-high"
      )

      section = described_class.new(boundary.reload).sections.find { |x| x.key == :classification }
      expect(section.status).to eq(:partial)
      expect(section.detail).to match(/CONTRADICT/)
    end
  end

  # The honest state, and the reason it exists. The owner asked for "1 to n
  # environments documented"; SPARC models environments nowhere. Reporting that
  # as `absent` would blame the boundary for SPARC's gap, and reporting nothing
  # would read as "nothing to do".
  describe "environments" do
    it "is reported as not_modelled, never as absent or complete" do
      expect(status_of(:environments)).to eq(:not_modelled)
    end

    it "says plainly that SPARC cannot answer it" do
      section = described_class.new(boundary).sections.find { |s| s.key == :environments }

      expect(section.detail).to match(/does not model environments/i)
      expect(section.count).to be_nil
    end

    it "is excluded from the answerable sections rather than counted as a gap" do
      summary = described_class.new(boundary).report[:summary]

      expect(summary[:not_modelled]).to eq(1)
    end
  end

  describe "the report as a whole" do
    it "points every section at the guide section that explains how to close it" do
      sections = described_class.new(boundary).sections

      expect(sections.map(&:guide_anchor)).to all(be_present)
    end

    it "summarises by state" do
      summary = described_class.new(boundary).report[:summary]

      expect(summary.keys).to match_array(described_class::STATES)
      expect(summary.values.sum).to eq(described_class.new(boundary).sections.size)
    end

    it "is read-only — it mutates nothing" do
      create(:ssp_document, authorization_boundary: boundary)

      before_counts = [ SspDocument.count, AuthorizationBoundary.count, Evidence.count,
                        SspInformationType.count ]

      described_class.new(boundary).report

      expect([ SspDocument.count, AuthorizationBoundary.count, Evidence.count,
               SspInformationType.count ]).to eq(before_counts)
    end
  end
end
