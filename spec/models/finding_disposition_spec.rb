# frozen_string_literal: true

require "rails_helper"

RSpec.describe FindingDisposition do
  it "has a valid factory" do
    expect(build(:finding_disposition)).to be_valid
  end

  it "requires control_id, reason, and decided_by" do
    expect(build(:finding_disposition, control_id: nil)).not_to be_valid
    expect(build(:finding_disposition, reason: nil)).not_to be_valid
    expect(build(:finding_disposition, decided_by: nil)).not_to be_valid
  end

  it "rejects an unknown kind" do
    expect(build(:finding_disposition, kind: "bogus")).not_to be_valid
  end

  it "accepts all seven v3.4.0 override kinds" do
    described_class::KINDS.each do |kind|
      disp = build(:finding_disposition, kind: kind, expiration: 30.days.from_now,
                   linked_subject: (kind == "riskAdjustment" ? build(:risk_assessment) : nil))
      expect(disp).to be_valid, "expected kind=#{kind} to be valid: #{disp.errors.full_messages}"
    end
  end

  it "is unique per (authorization_boundary, control_id)" do
    boundary = create(:authorization_boundary)
    create(:finding_disposition, authorization_boundary: boundary, control_id: "CVE-2026-1")
    dup = build(:finding_disposition, authorization_boundary: boundary, control_id: "CVE-2026-1")
    expect(dup).not_to be_valid
  end

  describe "expiration requirement" do
    it "requires expiration for waiver and operationalRequirement" do
      expect(build(:finding_disposition, kind: "waiver", expiration: nil)).not_to be_valid
      expect(build(:finding_disposition, kind: "operationalRequirement", expiration: nil)).not_to be_valid
    end

    it "does not require expiration for other kinds" do
      expect(build(:finding_disposition, kind: "poam", expiration: nil)).to be_valid
      expect(build(:finding_disposition, kind: "falsePositive", expiration: nil)).to be_valid
    end
  end

  describe "#hdf_status" do
    it "maps suppressing kinds to notApplicable" do
      %w[falsePositive waiver inherited].each do |kind|
        disp = build(:finding_disposition, kind: kind, expiration: 30.days.from_now)
        expect(disp.hdf_status).to eq("notApplicable")
      end
    end

    it "maps tracked kinds to failed" do
      %w[poam vendorDependency operationalRequirement].each do |kind|
        disp = build(:finding_disposition, kind: kind, expiration: 30.days.from_now)
        expect(disp.hdf_status).to eq("failed")
      end
    end
  end

  describe "#expired?" do
    it "is true once the expiration has passed" do
      expect(build(:finding_disposition, :waiver, expiration: 1.day.ago)).to be_expired
      expect(build(:finding_disposition, :waiver, expiration: 1.day.from_now)).not_to be_expired
    end

    it "excludes expired dispositions from the active scope" do
      boundary = create(:authorization_boundary)
      active = create(:finding_disposition, :waiver, authorization_boundary: boundary,
                      control_id: "CVE-A", expiration: 30.days.from_now)
      create(:finding_disposition, :waiver, authorization_boundary: boundary,
             control_id: "CVE-B", expiration: 1.day.ago)
      expect(described_class.active).to contain_exactly(active)
    end
  end
end
