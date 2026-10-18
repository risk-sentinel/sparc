# frozen_string_literal: true

require "rails_helper"

# #1223 — which rows the 5-minute sweep picks up. Too wide and a genuine
# failure retries every 5 minutes; too narrow and a row an older release
# misjudged during a rolling deploy waits for the next boot.
RSpec.describe DataMigrationRun, ".awaiting_this_release" do
  let(:release) { SparcConfig::VERSION }
  let(:newer)   { Gem::Version.new(release).bump.to_s + ".0" }

  def row(name, status:, error_message: nil, registered_release: release)
    described_class.create!(name: name, status: status, error_message: error_message,
                            registered_release: registered_release)
  end

  it "takes pending rows and rows an older release failed with the bare not-loadable message" do
    row("Pending", status: "pending")
    row("MisjudgedByTheOldRelease", status: "failed", error_message: "Class MisjudgedByTheOldRelease not loadable")

    expect(described_class.awaiting_this_release.map(&:name)).to contain_exactly("Pending", "MisjudgedByTheOldRelease")
  end

  it "leaves genuine failures to the once-per-boot retry" do
    row("Raised", status: "failed", error_message: "RuntimeError: boom")
    row("Archived", status: "failed",
                    error_message: "Class Archived not loadable: no migration file in this release (1.17.2)")
    row("BrokenFile", status: "failed", error_message: "Class BrokenFile not loadable: its migration file failed to load")
    row("Done", status: "completed")

    expect(described_class.awaiting_this_release).to be_empty
  end

  it "leaves a row a newer release registered to that release" do
    row("FromTheNextRelease", status: "pending", registered_release: newer)

    expect(described_class.awaiting_this_release).to be_empty
  end

  describe "#registered_by_newer_release?" do
    it "is false for an unknown or malformed release" do
      expect(row("Unknown", status: "pending", registered_release: nil).registered_by_newer_release?).to be(false)
      expect(row("Garbage", status: "pending", registered_release: "not a version").registered_by_newer_release?)
        .to be(false)
    end
  end
end
