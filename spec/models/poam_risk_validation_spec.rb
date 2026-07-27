# frozen_string_literal: true

require "rails_helper"

# #832 — PoamRisk used to validate only `uuid`, so a risk could be saved with no
# title, description, statement, status or deadline. The consequence was not a
# cosmetic gap: the resulting POA&M failed OSCAL schema validation at EXPORT,
# far from the input that caused it, with nothing to say which record was at
# fault. This is the #816 bug class at its source.
RSpec.describe PoamRisk, "#832 required fields" do
  let(:document) { create(:poam_document) }

  def build_risk(**overrides)
    described_class.new({
      poam_document: document,
      uuid: SecureRandom.uuid,
      title: "Hard-coded credentials in the admin panel",
      description: "Static credentials are present in the deployed configuration.",
      statement: "An attacker with read access to the image can authenticate as an administrator.",
      status: "open",
      deadline: 30.days.from_now
    }.merge(overrides))
  end

  it "accepts a complete risk" do
    expect(build_risk).to be_valid
  end

  # Each field individually, so a single over-broad validation cannot pass this
  # by rejecting everything.
  describe "rejects a risk missing" do
    {
      title: "OSCAL requires risk/title",
      description: "OSCAL requires risk/description",
      statement: "OSCAL requires risk/statement",
      status: "OSCAL requires risk/status"
    }.each do |field, why|
      it "#{field} (#{why})" do
        risk = build_risk(field => nil)

        expect(risk).not_to be_valid
        expect(risk.errors[field]).to be_present
      end
    end

    # Not an OSCAL requirement — a SPARC one. A POA&M whose items carry no time
    # commitment is not a plan of action, and `hdf convert --from oscal-poam
    # --to hdf-amendments` refuses it outright. hdf-cli 3.3.2 used to invent
    # "conversion time + one year"; 3.4.1 correctly stopped.
    it "deadline (SPARC requires a time commitment)" do
      risk = build_risk(deadline: nil)

      expect(risk).not_to be_valid
      expect(risk.errors[:deadline]).to be_present
    end
  end

  it "still requires uuid" do
    expect(build_risk(uuid: nil)).not_to be_valid
  end

  # Blank is not the same as nil, and a whitespace-only statement satisfies
  # neither OSCAL nor a reader.
  it "rejects whitespace-only content" do
    expect(build_risk(statement: "   ")).not_to be_valid
  end

  describe "#missing_required_fields" do
    it "is empty for a complete risk" do
      expect(build_risk.missing_required_fields).to be_empty
    end

    it "names every gap, which is what the audit task and the API report" do
      risk = build_risk(statement: nil, deadline: nil, title: "")

      expect(risk.missing_required_fields).to contain_exactly(:title, :statement, :deadline)
    end
  end

  # The rules apply on UPDATE too, not just create. Grandfathering existing rows
  # would preserve exactly the invalid data these validations exist to stop, and
  # would do it silently — the audit task exists to surface those rows instead.
  it "rejects blanking a required field on an existing record" do
    risk = build_risk
    risk.save!

    expect(risk.update(statement: nil)).to be(false)
    expect(risk.reload.statement).to be_present
  end

  # A row that predates the validations is still readable and still reports its
  # gaps; it simply cannot be saved again until completed.
  it "reports gaps on a row written before the rules existed" do
    risk = build_risk
    risk.save!
    described_class.where(id: risk.id).update_all(statement: nil, deadline: nil)

    stale = described_class.find(risk.id)
    expect(stale.missing_required_fields).to contain_exactly(:statement, :deadline)
    expect(stale.update(remarks: "an unrelated edit")).to be(false),
      "a row missing required content must not be saveable until it is completed"
  end
end
