require "rails_helper"

RSpec.describe Lifecycle do
  # Use ProfileDocument as a concrete model that includes the concern
  let(:document) { create(:profile_document, status: "completed", lifecycle_status: "in_progress") }

  describe "validations" do
    it "accepts valid lifecycle statuses" do
      %w[started in_progress published].each do |status|
        document.lifecycle_status = status
        expect(document).to be_valid
      end
    end

    it "rejects invalid lifecycle statuses" do
      document.lifecycle_status = "archived"
      expect(document).not_to be_valid
    end

    it "allows nil lifecycle_status" do
      document.lifecycle_status = nil
      expect(document).to be_valid
    end
  end

  describe "scopes" do
    let!(:started_doc)     { create(:profile_document, status: "completed", lifecycle_status: "started") }
    let!(:in_progress_doc) { create(:profile_document, status: "completed", lifecycle_status: "in_progress") }
    let!(:published_doc)   { create(:profile_document, status: "completed", lifecycle_status: "published") }

    it "returns draft documents (started + in_progress)" do
      drafts = ProfileDocument.draft
      expect(drafts).to include(started_doc, in_progress_doc)
      expect(drafts).not_to include(published_doc)
    end

    it "returns published_lifecycle documents" do
      published = ProfileDocument.published_lifecycle
      expect(published).to include(published_doc)
      expect(published).not_to include(started_doc, in_progress_doc)
    end
  end

  describe "predicates" do
    it "#published_lifecycle? returns true when published" do
      document.lifecycle_status = "published"
      expect(document.published_lifecycle?).to be true
    end

    it "#published_lifecycle? returns false when not published" do
      document.lifecycle_status = "in_progress"
      expect(document.published_lifecycle?).to be false
    end

    it "#draft? returns true when not published" do
      document.lifecycle_status = "in_progress"
      expect(document.draft?).to be true
    end

    it "#draft? returns false when published" do
      document.lifecycle_status = "published"
      expect(document.draft?).to be false
    end

    it "#lifecycle_started? returns true when started" do
      document.lifecycle_status = "started"
      expect(document.lifecycle_started?).to be true
    end

    it "#lifecycle_in_progress? returns true when in_progress" do
      document.lifecycle_status = "in_progress"
      expect(document.lifecycle_in_progress?).to be true
    end
  end

  describe "#publish_lifecycle!" do
    it "sets lifecycle_status to published" do
      document.publish_lifecycle!
      expect(document.reload.lifecycle_status).to eq("published")
    end

    it "sets published timestamp" do
      document.publish_lifecycle!
      expect(document.reload.published).to be_present
    end
  end

  describe "#lifecycle_label" do
    it "returns human-readable labels" do
      { "started" => "Started", "in_progress" => "In Progress", "published" => "Published" }.each do |status, label|
        document.lifecycle_status = status
        expect(document.lifecycle_label).to eq(label)
      end
    end
  end

  describe "#lifecycle_badge_class" do
    it "returns correct CSS classes" do
      { "started" => "badge-warn", "in_progress" => "badge-info", "published" => "badge-ok" }.each do |status, css_class|
        document.lifecycle_status = status
        expect(document.lifecycle_badge_class).to eq(css_class)
      end
    end
  end
end
