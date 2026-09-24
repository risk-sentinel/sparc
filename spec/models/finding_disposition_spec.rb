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

  # Every kind requires a review date, not only the clock kinds. It became
  # unconditional with the hdf-cli 3.7.0 pin: hdf requires an `expiresAt` on
  # every amendment override, so a disposition without one cannot be exported —
  # and SPARC refuses to invent a date rather than write one nobody chose into
  # signed evidence. Enforced on the model so the UI, the API and the exporter
  # cannot disagree.
  describe "expiration requirement" do
    described_class::KINDS.each do |kind|
      it "requires an expiration for #{kind}" do
        expect(build(:finding_disposition, kind: kind, expiration: nil)).not_to be_valid
      end
    end

    it "accepts every kind once a review date is set" do
      described_class::KINDS.each do |kind|
        d = build(:finding_disposition, kind: kind, expiration: 90.days.from_now)
        # Some kinds carry their own linkage rules; expiration is not why they
        # would fail, which is what this asserts.
        expect(d.errors.where(:expiration)).to be_empty if d.validate
        d.validate
        expect(d.errors[:expiration]).to be_empty, "#{kind}: #{d.errors[:expiration].join(', ')}"
      end
    end
  end

  # A disposition is a decision taken against a state of the world. A year on,
  # the package has moved and the CVE may be fixed, so an expiry further out
  # than the review window is indistinguishable from "never re-examined".
  #
  # Both directions, because a cap that rejects everything is not a cap.
  describe "review window (MAX_EXPIRATION_WINDOW)" do
    it "accepts an expiry inside the window" do
      d = build(:finding_disposition, decided_at: Time.current,
                expiration: Time.current + described_class::MAX_EXPIRATION_WINDOW - 1.day)

      expect(d).to be_valid
    end

    it "accepts an expiry exactly at the window" do
      anchor = Time.current
      d = build(:finding_disposition, decided_at: anchor,
                expiration: anchor + described_class::MAX_EXPIRATION_WINDOW)

      expect(d).to be_valid
    end

    it "rejects an expiry beyond the window, and says what to do" do
      anchor = Time.current
      d = build(:finding_disposition, decided_at: anchor,
                expiration: anchor + described_class::MAX_EXPIRATION_WINDOW + 1.day)

      expect(d).not_to be_valid
      expect(d.errors[:expiration].join).to include("re-decided rather than extended")
    end

    # The window runs from the DECISION, not from now — so back-dating the
    # decision does not buy a longer deferral.
    it "measures from decided_at, not from the present" do
      d = build(:finding_disposition, decided_at: 6.months.ago,
                expiration: Time.current + 7.months)

      expect(d).not_to be_valid
    end

    it "stays silent when there is no expiry, so presence speaks instead" do
      d = build(:finding_disposition, kind: "falsePositive", expiration: nil)
      d.validate

      # One error, not two. A missing review date is a missing review date; it
      # is not also "outside the review window", and reporting both would tell
      # the operator to fix something that is not wrong.
      expect(d.errors[:expiration]).to eq([ "can't be blank" ])
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

  describe "approval (#809)" do
    it "defaults to draft and is not applicable until approved" do
      d = create(:finding_disposition, kind: "poam")
      expect(d.approval_status).to eq("draft")
      expect(d).not_to be_approved
      expect(d).not_to be_applicable
    end

    it "is applicable when approved and within its validity window" do
      d = create(:finding_disposition, kind: "poam", approval_status: "approved",
                 approved_by: "ao@corp.io", approved_at: Time.current, valid_until: 30.days.from_now)
      expect(d).to be_applicable
    end

    # Two independent clocks: the decision's own `expiration` and the computed
    # ODP window. A lapsed waiver must stop suppressing even when the ODP window
    # is still open (or absent), or aggregation skips the POA&M item it owes.
    it "is not applicable once its own expiration has passed, whatever valid_until says" do
      lapsed = create(:finding_disposition, :waiver, approval_status: "approved",
                      approved_by: "ao@corp.io", approved_at: Time.current,
                      expiration: 1.day.ago, valid_until: 30.days.from_now)
      expect(lapsed).to be_expired
      expect(lapsed).not_to be_applicable

      no_window = create(:finding_disposition, :waiver, control_id: "CVE-NOWINDOW",
                         approval_status: "approved", approved_by: "ao@corp.io",
                         approved_at: Time.current, expiration: 1.day.ago, valid_until: nil)
      expect(no_window).not_to be_applicable
    end

    it "is not applicable once valid_until has passed" do
      d = create(:finding_disposition, kind: "poam", approval_status: "approved",
                 approved_by: "ao@corp.io", valid_until: 1.day.ago)
      expect(d).not_to be_applicable
    end

    it "rejects an unknown approval_status" do
      expect(build(:finding_disposition, kind: "poam", approval_status: "maybe")).not_to be_valid
    end
  end
end
