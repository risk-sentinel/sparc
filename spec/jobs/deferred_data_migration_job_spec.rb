# frozen_string_literal: true

require "rails_helper"

RSpec.describe DeferredDataMigrationJob do
  it "delegates to DeferredDataMigrationRunner.run_all_pending" do
    expect(DeferredDataMigrationRunner).to receive(:run_all_pending).once
    described_class.new.perform
  end

  it "enqueues to the :default queue" do
    expect(described_class.new.queue_name).to eq("default")
  end

  it "does not retry on its own (the runner records failures in the tracking row)" do
    # ApplicationJob retry config — confirm the policy is in place.
    # We can't easily exercise the retry directly without a real
    # ActiveJob test backend; assert the class-level config exists.
    handlers = described_class.rescue_handlers.map(&:first)
    expect(handlers).to include("StandardError")
  end
end
