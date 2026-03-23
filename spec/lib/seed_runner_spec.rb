require "rails_helper"
require "seed_runner"

RSpec.describe SeedRunner do
  before do
    SeedSection.delete_all
  end

  describe ".run_section" do
    it "creates a completed SeedSection record on success" do
      SeedRunner.run_section("test_section", version: "1.0.0") do
        # no-op — success
      end

      section = SeedSection.find_by(name: "test_section")
      expect(section).to be_present
      expect(section.status).to eq("completed")
      expect(section.version).to eq("1.0.0")
      expect(section.completed_at).to be_present
      expect(section.error_message).to be_nil
    end

    it "skips an already-completed section at the same version" do
      SeedSection.create!(name: "test_section", version: "1.0.0", status: "completed", completed_at: 1.hour.ago)

      ran = false
      SeedRunner.run_section("test_section", version: "1.0.0") do
        ran = true
      end

      expect(ran).to be false
    end

    it "re-runs a section when version is bumped" do
      SeedSection.create!(name: "test_section", version: "1.0.0", status: "completed", completed_at: 1.hour.ago)

      ran = false
      SeedRunner.run_section("test_section", version: "2.0.0") do
        ran = true
      end

      expect(ran).to be true
      section = SeedSection.find_by(name: "test_section")
      expect(section.version).to eq("2.0.0")
      expect(section.status).to eq("completed")
    end

    it "re-runs a previously failed section" do
      SeedSection.create!(name: "test_section", version: "1.0.0", status: "failed", error_message: "previous error")

      SeedRunner.run_section("test_section", version: "1.0.0") do
        # success this time
      end

      section = SeedSection.find_by(name: "test_section")
      expect(section.status).to eq("completed")
      expect(section.error_message).to be_nil
    end

    it "catches exceptions and marks section as failed without re-raising" do
      expect {
        SeedRunner.run_section("failing_section", version: "1.0.0") do
          raise StandardError, "intentional test failure"
        end
      }.not_to raise_error

      section = SeedSection.find_by(name: "failing_section")
      expect(section.status).to eq("failed")
      expect(section.error_message).to include("intentional test failure")
      expect(section.error_message).to include("StandardError")
    end

    it "does not affect other sections when one fails" do
      SeedRunner.run_section("section_a", version: "1.0.0") do
        raise "fail a"
      end

      SeedRunner.run_section("section_b", version: "1.0.0") do
        # success
      end

      expect(SeedSection.find_by(name: "section_a").status).to eq("failed")
      expect(SeedSection.find_by(name: "section_b").status).to eq("completed")
    end
  end

  describe ".summary" do
    it "outputs a summary without raising" do
      SeedSection.create!(name: "good", version: "1.0.0", status: "completed")
      SeedSection.create!(name: "bad", version: "1.0.0", status: "failed", error_message: "boom")

      expect { SeedRunner.summary }.to output(/SEED COMPLETENESS REPORT/).to_stdout
    end
  end

  describe ".verify_completeness" do
    it "outputs a completeness check without raising" do
      expect { SeedRunner.verify_completeness }.to output(/DATA COMPLETENESS CHECK/).to_stdout
    end
  end
end
