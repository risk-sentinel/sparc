# frozen_string_literal: true

require "rails_helper"

# #1094 — the SAR family filter compared the RAW parameter against values that
# are always uppercase, so `?family=ac` returned "0 of 150 controls" and reported
# that as the answer. Every family tile links uppercase, so the in-app path
# worked and only hand-typed, bookmarked or API-built URLs were affected —
# silently, which is what made it worth a spec rather than a one-line fix.
#
# Both storage paths are covered because the predicate has two halves:
#   control_family = :family                       -- denormalised, set on import
#   control_family IS NULL AND UPPER(SPLIT_PART(control_id, '-', 1)) = :family
# The second upcases the COLUMN, which is what disguised the bug: it looks like
# case is handled.
RSpec.describe "SAR family filter (#1094)", type: :request do
  let(:user) { create(:user, :admin) }
  let(:sar)  { create(:sar_document, name: "Family Filter SAR") }

  before { sign_in_as(user) }

  # `control_family` populated (the denormalised path).
  def seed_denormalised!
    sar.sar_controls.create!(control_id: "ac-1", title: "Policy And Procedures",
                             control_family: "AC", row_order: 0)
    sar.sar_controls.create!(control_id: "cm-2", title: "Baseline Configuration",
                             control_family: "CM", row_order: 1)
  end

  # `control_family` NULL, family inferred from the control_id prefix. Note the
  # ids are stored LOWERCASE, which is why a lowercase family is the natural
  # thing for a caller to send.
  def seed_fallback!
    sar.sar_controls.create!(control_id: "ac-1", title: "Policy And Procedures",
                             control_family: nil, row_order: 0)
    sar.sar_controls.create!(control_id: "cm-2", title: "Baseline Configuration",
                             control_family: nil, row_order: 1)
  end

  shared_examples "filters to the AC family" do
    it "returns the AC control and not the CM one for an UPPERCASE family" do
      get sar_document_path(sar, family: "AC")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Policy And Procedures")
      expect(response.body).not_to include("Baseline Configuration")
    end

    it "returns the same for a LOWERCASE family" do
      get sar_document_path(sar, family: "ac")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Policy And Procedures")
      expect(response.body).not_to include("Baseline Configuration")
    end

    it "returns the same for a MIXED-CASE family" do
      get sar_document_path(sar, family: "Ac")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Policy And Procedures")
      expect(response.body).not_to include("Baseline Configuration")
    end

    # The other direction: normalising must not make the filter match everything.
    it "still excludes both controls for a family that matches nothing" do
      get sar_document_path(sar, family: "zz")

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("Policy And Procedures")
      expect(response.body).not_to include("Baseline Configuration")
    end

    it "shows both controls when no family is given" do
      get sar_document_path(sar)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Policy And Procedures")
      expect(response.body).to include("Baseline Configuration")
    end
  end

  context "when control_family is populated" do
    before { seed_denormalised! }

    include_examples "filters to the AC family"
  end

  context "when control_family is NULL and the family comes from the control_id" do
    before { seed_fallback! }

    include_examples "filters to the AC family"
  end

  # The summary chip and the family tiles are uppercase, so a raw parameter left
  # the page contradicting itself: results for AC, a chip reading "ac", and no
  # tile highlighted.
  it "reports the normalised family in the filter summary" do
    seed_denormalised!
    get sar_document_path(sar, family: "ac")

    expect(response.body).to include("Family:")
    expect(response.body).to include("<strong>AC</strong>")
    expect(response.body).not_to include("<strong>ac</strong>")
  end
end
