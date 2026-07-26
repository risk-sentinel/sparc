# frozen_string_literal: true

require "rails_helper"

RSpec.describe ScanRun do
  it "has a valid factory" do
    expect(build(:scan_run)).to be_valid
  end

  it "requires a scanner" do
    expect(build(:scan_run, scanner: nil)).not_to be_valid
  end

  it "assigns a uuid on validation" do
    run = build(:scan_run, uuid: nil)
    run.valid?
    expect(run.uuid).to be_present
  end

  it "defaults ingested_at on create" do
    run = build(:scan_run, ingested_at: nil)
    run.valid?
    expect(run.ingested_at).to be_present
  end

  it "destroys its scanner_findings" do
    run = create(:scan_run, :with_findings)
    expect { run.destroy }.to change(ScannerFinding, :count).by(-2)
  end

  it "is addressed by uuid" do
    run = create(:scan_run)
    expect(run.to_param).to eq(run.uuid)
  end
end
