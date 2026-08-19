require "rails_helper"

RSpec.describe LeveragedAuthorization, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:leveraging_boundary).class_name("AuthorizationBoundary") }
    it { is_expected.to belong_to(:leveraged_boundary).class_name("AuthorizationBoundary").optional }
    it { is_expected.to have_many(:leveraged_authorization_components).dependent(:destroy) }
  end

  describe "validations" do
    subject(:la) { build(:leveraged_authorization) }

    it { is_expected.to validate_presence_of(:name) }

    it "requires a known crm_type" do
      la.crm_type = "fantasy"
      expect(la).not_to be_valid
    end

    it "auto-assigns uuid if blank" do
      la.uuid = nil
      la.valid?
      expect(la.uuid).to match(BackMatterResource::UUID_V4_REGEX)
    end

    it "rejects self-reference" do
      b = create(:authorization_boundary)
      la = build(:leveraged_authorization, leveraging_boundary: b, leveraged_boundary: b)
      expect(la).not_to be_valid
      expect(la.errors[:leveraged_boundary]).to be_present
    end

    it "detects cycles" do
      a = create(:authorization_boundary)
      b = create(:authorization_boundary)
      create(:leveraged_authorization, leveraging_boundary: a, leveraged_boundary: b)
      # Creating a second link where b leverages a would cycle back to a.
      la = build(:leveraged_authorization, leveraging_boundary: b, leveraged_boundary: a)
      expect(la).not_to be_valid
      expect(la.errors[:leveraged_boundary]).to be_present
    end
  end

  # #988 — a system cannot leverage one that was never authorized. Both
  # directions, because only asserting the refusal would also pass against a
  # model that refused everything.
  describe "date_authorized (#988)" do
    it "accepts a leveraged authorization that names an authorization date" do
      la = build(:leveraged_authorization, date_authorized: Date.new(2026, 1, 15))

      expect(la).to be_valid
    end

    it "refuses one with no authorization date" do
      la = build(:leveraged_authorization, date_authorized: nil)

      expect(la).not_to be_valid
      expect(la.errors[:date_authorized].join).to match(/has not been authorized/)
    end

    # Rows written before the validation existed stay readable — the check fires
    # on their NEXT save, so an operator resolves each knowingly instead of
    # having a date invented for them (the #952 report-and-block precedent).
    it "refuses to save an existing undated row until it is dated" do
      la = build(:leveraged_authorization, date_authorized: nil)
      la.save!(validate: false)

      la.description = "an unrelated edit"

      expect(la.save).to be(false)
      expect(la.reload.description).not_to eq("an unrelated edit")
    end

    # The sibling model that feeds the SAME OSCAL array has always required
    # this. Pinning it here so the two cannot drift apart again.
    it "matches SspLeveragedAuthorization, which feeds the same OSCAL array" do
      sibling = SspLeveragedAuthorization.new(title: "x", party_uuid: SecureRandom.uuid)
      sibling.valid?

      expect(sibling.errors[:date_authorized]).to be_present
    end
  end

  describe "#scenario" do
    it { expect(build(:leveraged_authorization, crm_type: "oscal_with_access").scenario).to eq(1) }
    it { expect(build(:leveraged_authorization, :oscal_no_access).scenario).to eq(2) }
    it { expect(build(:leveraged_authorization, :legacy).scenario).to eq(3) }
  end
end
