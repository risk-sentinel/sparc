# frozen_string_literal: true

require "rails_helper"

# #1390 — significant changes: the record of each evaluation, the notices
# each needs and when, and the Significant Change Notification.
RSpec.describe FedrampSignificantChangeService do
  include ActiveSupport::Testing::TimeHelpers

  let(:boundary) { create(:authorization_boundary, :fedramp, fedramp_package_overview_uri: "https://trust.example/cpo.json") }
  let(:service) { described_class.new(boundary) }
  let(:user) { create(:user) }

  def record(**attributes) = service.record(attributes: attributes, user: user).change

  it "records a routine change as evaluated, with no notices and no notification" do
    change = record(change_type: "Routine", description: "Monthly OS patching")
    expect(change).to have_attributes(created_by: user, updated_by: user)
    expect(service.deadlines(change)).to eq([])
    expect { service.notification(change) }.to raise_error(described_class::Error, /SCN-RTR-NNR/)
  end

  it "sets a transformative change's notices from its start, finish and verification in federal business days" do
    change = record(change_type: "Transformative", description: "Move to a new region", plan_summary: "Phased",
                    planned_start: "2027-01-15")
    due = service.deadlines(change).to_h { |d| [ d.key, d.due_on ] }
    # 30 and 10 business days before 15 January 2027: New Year's Day and Christmas skipped.
    expect(due).to eq("initial_plans" => Date.new(2026, 12, 2), "final_plans" => Date.new(2026, 12, 31),
                      "after_finish" => nil, "after_verification" => nil, "documentation" => nil)

    service.record(change: change, user: user, attributes: { started_on: "2027-01-19", finished_on: "2027-02-12",
                                                             verified_on: "2027-02-26" })
    due = service.deadlines(change.reload).to_h { |d| [ d.key, d.due_on ] }
    expect(due["initial_plans"]).to eq(Date.new(2026, 12, 3))       # 30 before the actual start; MLK Day skipped
    expect(due["after_finish"]).to eq(Date.new(2027, 2, 22))        # 5 after; Washington's Birthday skipped
    expect(due["after_verification"]).to eq(Date.new(2027, 3, 5))
    expect(due["documentation"]).to eq(Date.new(2027, 3, 29))       # SCN-TRF-UPD, 30 after the finish
  end

  it "gives an emergency change's before-start notices afterwards" do
    change = record(change_type: "Transformative", description: "Emergency firewall change", emergency: true,
                    started_on: "2026-11-02", finished_on: "2026-11-03")
    initial = service.deadlines(change).find { |d| d.key == "initial_plans" }
    expect(initial).to have_attributes(retroactive: true, due_on: Date.new(2026, 11, 10)) # Veterans Day skipped
  end

  it "gives an adaptive change one notice, 10 business days after it finishes" do
    change = record(change_type: "Adaptive", description: "New dashboard", finished_on: "2026-11-20")
    expect(service.deadlines(change).map { |d| [ d.rule_id, d.due_on ] }).to eq([ [ "SCN-ADP-NTF", Date.new(2026, 12, 7) ] ])
  end

  it "writes the notification, valid against FedRAMP's schema, with the approver and new risks as additional information" do
    change = record(change_type: "Adaptive", description: "New dashboard", reason: "Customer request",
                    plan_summary: "Ship behind a flag", planned_start: "2026-12-01",
                    milestones: { "0" => { description: "Beta", target_date: "2026-12-05" }, "1" => { description: "" } },
                    impacted_controls: "KSI-CMT-LMC, cm-3\ncm-3", approver_name: "Pat Doe", approver_title: "CISO",
                    new_risks: "None identified")
    doc = service.notification(change)
    expect(doc).to include("$schema" => FedrampPackageSchemas.fetch("significant-change-notifications").id,
                           "certificationPackageOverviewUri" => "https://trust.example/cpo.json",
                           "changeType" => "Adaptive", "changeDescription" => "New dashboard",
                           "impactedControls" => %w[KSI-CMT-LMC cm-3], "approverName" => "Pat Doe",
                           "approverTitle" => "CISO", "newRisksSummary" => "None identified")
    expect(doc["planAndTimeline"]).to eq("summary" => "Ship behind a flag", "plannedStart" => "2026-12-01",
                                         "milestones" => [ { "milestoneDescription" => "Beta", "targetDate" => "2026-12-05" } ])
    expect(DocumentValidationService.call(JSON.generate(doc), format: "fedramp")).to be_valid
  end

  it "records a notice with the notification as sent, and refuses one the change does not need" do
    travel_to Time.utc(2026, 12, 10, 12)
    change = record(change_type: "Adaptive", description: "New dashboard", finished_on: "2026-11-20")
    notice = service.record_notice(change, stage: "after_finish", sent_on: "2026-12-09", user: user)
    expect(notice).to include("rule_id" => "SCN-ADP-NTF", "sent_on" => "2026-12-09", "recorded_by_id" => user.id)
    expect(notice["document"]["changeDescription"]).to eq("New dashboard")
    expect(notice["sha256"]).to eq(Digest::SHA256.hexdigest(JSON.generate(notice["document"])))
    expect(service.deadlines(change.reload).first.status).to eq("late") # due 2026-12-07

    expect { service.record_notice(change, stage: "initial_plans", sent_on: "2026-12-09", user: user) }
      .to raise_error(described_class::Error, /no initial plans notice/)
    expect { service.record_notice(change, stage: "after_finish", sent_on: (Date.current + 1).iso8601, user: user) }
      .to raise_error(described_class::Error, /future/)
  end

  it "records the published documentation without a document" do
    change = record(change_type: "Transformative", description: "x", finished_on: "2026-11-02")
    notice = service.record_notice(change, stage: "documentation", sent_on: "2026-11-10", user: user)
    expect(notice).not_to have_key("document")
    expect(notice["rule_id"]).to eq("SCN-TRF-UPD")
  end

  it "refuses a value the record does not allow, saying why" do
    expect { record(change_type: "Major", description: "x") }.to raise_error(described_class::Error, /Change type/)
    expect { record(change_type: "Adaptive", description: "x", planned_start: "2026-12-01") }
      .to raise_error(described_class::Error, /Plan summary is required/)
    expect { record(change_type: "Adaptive", description: "x", started_on: "2026-12-02", finished_on: "2026-12-01") }
      .to raise_error(described_class::Error, /before the start/)
  end

  it "keeps 12 months of notifications, never routine changes" do
    old = record(change_type: "Adaptive", description: "old")
    old.update_columns(created_at: 13.months.ago)
    recent = record(change_type: "Transformative", description: "recent")
    record(change_type: "Routine", description: "patching")
    expect(service.history).to eq([ recent ])
  end
end
