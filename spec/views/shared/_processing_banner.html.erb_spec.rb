# frozen_string_literal: true

require "rails_helper"

# Issue #548 — auto-refresh trap bailout. Documents stuck in pending /
# processing past SparcConfig.processing_stuck_minutes must stop emitting
# the auto-refresh poll and show a "stuck" message instead, so the browser
# tab is no longer trapped in a redirect loop.
#
# #599 Round 4: the poll is a `data-controller="auto-refresh"` Stimulus
# element (Turbo visit) rather than a `<meta http-equiv="refresh">` tag,
# which fails the axe meta-refresh rule (WCAG 2.2.1).
RSpec.describe "shared/_processing_banner.html.erb", type: :view do
  let(:locals) do
    {
      document: document,
      back_path: "/cdef_documents",
      back_label: "Back to list"
    }
  end

  context "when the document is fresh (within the stuck threshold)" do
    let(:document) do
      build_stubbed(:cdef_document, status: "pending", created_at: 1.minute.ago)
    end

    it "emits the auto-refresh poll" do
      render partial: "shared/processing_banner", locals: locals
      expect(rendered).to include(%(data-controller="auto-refresh"))
      expect(rendered).to include("is being parsed")
    end
  end

  context "when the document has been stuck past the threshold" do
    let(:document) do
      build_stubbed(:cdef_document, status: "pending", created_at: 10.minutes.ago)
    end

    before { allow(SparcConfig).to receive(:processing_stuck_minutes).and_return(5) }

    it "does NOT emit the auto-refresh poll" do
      render partial: "shared/processing_banner", locals: locals
      expect(rendered).not_to include(%(data-controller="auto-refresh"))
    end

    it "shows a 'Processing Stuck' message with the threshold" do
      render partial: "shared/processing_banner", locals: locals
      expect(rendered).to include("Processing Stuck")
      expect(rendered).to include("5 minutes")
    end

    it "shows a Back link so the user can navigate away" do
      render partial: "shared/processing_banner", locals: locals
      expect(rendered).to include("Back to list")
      expect(rendered).to include('href="/cdef_documents"')
    end
  end

  context "when the document has explicitly failed" do
    let(:document) do
      build_stubbed(:cdef_document, status: "failed", error_message: "boom")
    end

    it "does NOT emit the auto-refresh poll (existing behavior)" do
      render partial: "shared/processing_banner", locals: locals
      expect(rendered).not_to include(%(data-controller="auto-refresh"))
      expect(rendered).to include("boom")
    end
  end

  context "when processing_started_at is set in metadata" do
    let(:document) do
      build_stubbed(
        :cdef_document,
        status: "processing",
        created_at: 20.minutes.ago,
        metadata_extra: { "processing_started_at" => 10.minutes.ago.iso8601 }
      )
    end

    before { allow(SparcConfig).to receive(:processing_stuck_minutes).and_return(5) }

    it "uses processing_started_at instead of created_at for stuck calculation" do
      # 10 min since processing_started_at > 5 min threshold → stuck
      render partial: "shared/processing_banner", locals: locals
      expect(rendered).not_to include(%(data-controller="auto-refresh"))
      expect(rendered).to include("Processing Stuck")
    end
  end
end
