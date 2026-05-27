# frozen_string_literal: true

require "rails_helper"

RSpec.describe DataMigrationRun do
  describe "validations" do
    it "requires a name" do
      run = described_class.new(name: nil, status: "pending")
      expect(run).not_to be_valid
    end

    it "enforces unique name" do
      described_class.create!(name: "PromoteFoo", status: "pending")
      dup = described_class.new(name: "PromoteFoo", status: "pending")
      expect(dup).not_to be_valid
    end

    it "rejects an unknown status" do
      run = described_class.new(name: "PromoteBar", status: "bogus")
      expect(run).not_to be_valid
    end

    it "rejects negative records_processed" do
      run = described_class.new(name: "PromoteBaz", status: "pending", records_processed: -1)
      expect(run).not_to be_valid
    end

    it "accepts a valid record" do
      run = described_class.new(name: "PromoteX", status: "pending")
      expect(run).to be_valid
    end
  end

  describe "status scopes + predicates" do
    let!(:p) { described_class.create!(name: "P", status: "pending") }
    let!(:r) { described_class.create!(name: "R", status: "running") }
    let!(:c) { described_class.create!(name: "C", status: "completed") }
    let!(:f) { described_class.create!(name: "F", status: "failed") }

    it "scopes by status" do
      expect(described_class.pending).to eq([ p ])
      expect(described_class.running).to eq([ r ])
      expect(described_class.completed).to eq([ c ])
      expect(described_class.failed).to eq([ f ])
    end

    it "predicates match status" do
      expect(p).to be_pending
      expect(r).to be_running
      expect(c).to be_completed
      expect(f).to be_failed
    end
  end

  describe "#duration_seconds" do
    it "returns nil while pending" do
      run = described_class.create!(name: "Q", status: "pending")
      expect(run.duration_seconds).to be_nil
    end

    it "returns nil while running (no completed_at)" do
      run = described_class.create!(name: "Q", status: "running", started_at: 30.seconds.ago)
      expect(run.duration_seconds).to be_nil
    end

    it "returns elapsed seconds when completed" do
      started   = 2.minutes.ago
      completed = 30.seconds.ago
      run = described_class.create!(name: "Q", status: "completed",
                                    started_at: started, completed_at: completed)
      expect(run.duration_seconds).to eq((completed - started).to_i)
    end
  end

  describe ".recent" do
    it "orders by created_at desc" do
      old = described_class.create!(name: "old", status: "completed", created_at: 1.hour.ago)
      mid = described_class.create!(name: "mid", status: "completed", created_at: 30.minutes.ago)
      new = described_class.create!(name: "new", status: "completed", created_at: 1.minute.ago)
      expect(described_class.recent.to_a).to eq([ new, mid, old ])
    end
  end
end
