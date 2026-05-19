# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("lib/aws_labs_cdef_bootstrap")

# Issue #492 — direct unit tests for the extracted bootstrap module.
# Each example exercises run! once and asserts on the outcome symbol;
# the enqueue itself is verified via have_enqueued_job.
RSpec.describe AwsLabsCdefBootstrap do
  before do
    # Test env uses :null_store; stub Rails.cache so the lock semantics
    # are deterministic per-example. Default: lock not held.
    allow(Rails.cache).to receive(:exist?).with(described_class::LOCK_KEY).and_return(false)
    allow(Rails.cache).to receive(:write).with(described_class::LOCK_KEY, anything, hash_including(expires_in: described_class::LOCK_TTL))
    allow(Rails.cache).to receive(:delete).with(described_class::LOCK_KEY)

    # Test env is skipped by default; force the production path for these
    # specs so we exercise the real decision tree.
    allow(Rails.env).to receive(:test?).and_return(false)
    # Rails::Console isn't loaded in RSpec, so defined?(Rails::Console)
    # is naturally false. No stub needed.
  end

  describe ".run!" do
    context "when SPARC_AWS_LABS_CDEF_ENABLED is false" do
      before { allow(SparcConfig).to receive(:aws_labs_cdef_enabled?).and_return(false) }

      it "returns :skipped_disabled and does not enqueue" do
        expect { expect(described_class.run!).to eq(:skipped_disabled) }.not_to have_enqueued_job(AwsLabsCdefRefreshJob)
      end
    end

    context "when the feature is enabled" do
      before { allow(SparcConfig).to receive(:aws_labs_cdef_enabled?).and_return(true) }

      it "returns :skipped_env_override when SPARC_SKIP_AWS_LABS_BOOTSTRAP=true" do
        ENV["SPARC_SKIP_AWS_LABS_BOOTSTRAP"] = "true"
        expect { expect(described_class.run!).to eq(:skipped_env_override) }.not_to have_enqueued_job(AwsLabsCdefRefreshJob)
      ensure
        ENV.delete("SPARC_SKIP_AWS_LABS_BOOTSTRAP")
      end

      it "returns :skipped_already_populated when AWS Labs rows exist" do
        create(:cdef_document,
               name: "Pre-existing",
               import_metadata: { "source_type" => "aws_labs", "source_url" => "u", "source_sha" => "s" })

        expect { expect(described_class.run!).to eq(:skipped_already_populated) }.not_to have_enqueued_job(AwsLabsCdefRefreshJob)
      end

      it "still enqueues when only cloned rows exist (clones don't count)" do
        original = create(:cdef_document, name: "Original aws").id
        create(:cdef_document, name: "Clone", cloned_from_id: original,
               import_metadata: { "source_type" => "user_upload" })

        expect { expect(described_class.run!).to eq(:enqueued) }.to have_enqueued_job(AwsLabsCdefRefreshJob)
      end

      it "enqueues exactly one job when called and writes the lock" do
        expect(Rails.cache).to receive(:write).with(described_class::LOCK_KEY, anything, hash_including(expires_in: described_class::LOCK_TTL)).once

        expect { expect(described_class.run!).to eq(:enqueued) }.to have_enqueued_job(AwsLabsCdefRefreshJob).exactly(:once)
      end

      it "returns :skipped_lock_held when the dedup lock is set" do
        allow(Rails.cache).to receive(:exist?).with(described_class::LOCK_KEY).and_return(true)

        expect { expect(described_class.run!).to eq(:skipped_lock_held) }.not_to have_enqueued_job(AwsLabsCdefRefreshJob)
      end

      it "swallows ActiveRecord errors and returns :skipped_db_error" do
        allow(described_class).to receive(:already_populated?).and_raise(ActiveRecord::StatementInvalid.new("boom"))

        expect { expect(described_class.run!).to eq(:skipped_db_error) }.not_to have_enqueued_job(AwsLabsCdefRefreshJob)
      end
    end
  end

  describe "multi-process boot scenario (#492 defect 2)" do
    before { allow(SparcConfig).to receive(:aws_labs_cdef_enabled?).and_return(true) }

    it "second + third call within the lock TTL are no-ops" do
      # Simulate a real lock TTL: write sets, exist? returns true after write.
      lock_state = { held: false }
      allow(Rails.cache).to receive(:exist?).with(described_class::LOCK_KEY) { lock_state[:held] }
      allow(Rails.cache).to receive(:write).with(described_class::LOCK_KEY, anything, anything) { lock_state[:held] = true }

      results = 3.times.map { described_class.run! }

      expect(results).to eq([ :enqueued, :skipped_lock_held, :skipped_lock_held ])
    end
  end
end
