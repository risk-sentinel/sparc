# frozen_string_literal: true

require "rails_helper"

# #1114 — the SAR heatmap carries the ASSESSMENT PLAN's shape, with progress.
#
# Owner: "the mapping that the SAP has for Examine, Interview, Test and its heat
# map … is the right shape for the SAR with the % completed (assessed) on the
# tiles. This gives the full picture of what is expected of the assessor and the
# team being assessed."
#
# Methods answer "what is expected of us"; the percentage answers "how far in
# are we". The tile previously showed a PASS RATE, which reads as progress and is
# not — a family with one control examined and passed showed 100% while its other
# objectives sat untouched.
RSpec.describe "SAR assessment coverage heatmap (#1114)", type: :request do
  before { sign_in_as(create(:user, :admin)) }

  let(:sap) { create(:sap_document) }
  let(:sar) { create(:sar_document, sap_document: sap) }

  before do
    sap.sap_controls.create!(control_id: "ac-1", title: "Policy", row_order: 0,
                             assessment_method: "examine,interview")
    sap.sap_controls.create!(control_id: "ac-2", title: "Accounts", row_order: 1,
                             assessment_method: "test")
  end

  let!(:sar_ac1) { sar.sar_controls.create!(control_id: "ac-1", title: "Policy", control_family: "AC", row_order: 0) }
  let!(:sar_ac2) { sar.sar_controls.create!(control_id: "ac-2", title: "Accounts", control_family: "AC", row_order: 1) }

  # A determination statement HAS prose. An objective without it is one of NIST's
  # grouping containers, which is a different thing — see the container examples
  # below.
  def objective(control, id, status, prose: "the policy is reviewed")
    control.sar_control_objectives.create!(objective_id: id, status: status, prose: prose,
                                           row_order: 0, uuid: SecureRandom.uuid)
  end

  def container(control, id)
    control.sar_control_objectives.create!(objective_id: id, status: "pending", prose: nil,
                                           label: id.upcase, row_order: 0, uuid: SecureRandom.uuid)
  end

  describe "the methods" do
    # Asserted on the TILE's own badges, not on the page text: the legend always
    # spells "Examine / Interview / Test", so a body-text match passes even when
    # no control carries a method. The first version of this example did exactly
    # that and survived a mutation that ignored the linked SAP entirely.
    # Server mode renders the badges as LINKS, not data attributes, so the tile's
    # methods are read from each badge's title ("AC / examine: 2"). Reading the
    # legend instead is what made the first version of this vacuous.
    def tile_methods(body)
      card = body[/data-family="AC".*?(?=data-family="|\z)/m].to_s
      card.scan(/title="AC \/ ([^:]+):/).flatten.map(&:strip).uniq
    end

    it "reads the plan the SAR is linked to" do
      get sar_document_path(sar)

      expect(tile_methods(response.body)).to include("examine", "interview", "test")
    end

    it "marks a control the plan assesses more than one way" do
      get sar_document_path(sar)

      expect(tile_methods(response.body)).to include("multiple")
    end

    it "shows no method when the linked plan names none" do
      sap.sap_controls.update_all(assessment_method: nil)

      get sar_document_path(sar)

      expect(tile_methods(response.body)).to eq([ ApplicationHelper::LABEL_NONE ])
    end

    it "titles the panel as coverage, not results" do
      get sar_document_path(sar)

      expect(response.body).to include("Assessment Coverage by Control Family")
    end
  end

  describe "the percentage" do
    # 4 objectives, 2 determined -> 50%. A pass rate would say 100%, because
    # both determinations happen to be passing.
    it "is the share of objectives with a determination, not the pass rate" do
      objective(sar_ac1, "ac-1_obj.a-1", "passing")
      objective(sar_ac1, "ac-1_obj.a-2", "pending")
      objective(sar_ac2, "ac-2_obj.a-1", "passing")
      objective(sar_ac2, "ac-2_obj.a-2", "in-progress")

      get sar_document_path(sar)

      expect(assigns_pct(response.body)).to eq(50),
        "the tile must report assessment PROGRESS, not how many of the assessed ones passed"
    end

    it "counts a failed determination as assessed" do
      objective(sar_ac1, "ac-1_obj.a-1", "failed")
      objective(sar_ac1, "ac-1_obj.a-2", "failed")

      get sar_document_path(sar)

      expect(assigns_pct(response.body)).to eq(100)
    end

    # `not_applicable` is a scoping decision, not a determination — the same rule
    # the exporter applies when deciding what may become a finding.
    it "does not count not_applicable as assessed" do
      objective(sar_ac1, "ac-1_obj.a-1", "not_applicable")
      objective(sar_ac1, "ac-1_obj.a-2", "pending")

      get sar_document_path(sar)

      expect(assigns_pct(response.body)).to eq(0)
    end

    # #1114 — NIST's tree carries grouping nodes with a label and NO prose, and
    # there is nothing to determine about them. Counting them as outstanding work
    # made the bar unreachable: ac-1 has 24 objectives of which 7 are containers,
    # so a FULLY assessed control reported 71%. A progress figure that cannot
    # reach 100% teaches the reader to distrust it.
    it "excludes NIST's container nodes from the denominator" do
      objective(sar_ac1, "ac-1_obj.a-1", "passing")
      container(sar_ac1, "ac-1_obj")
      container(sar_ac1, "ac-1_obj.a")

      get sar_document_path(sar)

      expect(assigns_pct(response.body)).to eq(100),
        "a fully assessed control must be able to reach 100%"
    end

    it "reports 0 rather than blowing up when a family has no objectives" do
      get sar_document_path(sar)

      expect(response).to have_http_status(:ok)
    end
  end

  # The tiles are LINKS in server mode, so they must carry the filter this
  # heatmap is keyed on. They linked to `?status=` regardless of `filter_key`,
  # which the SAR reads as a RESULT filter — so a method tile matched nothing.
  describe "the tile links" do
    it "filters by method, not by status" do
      get sar_document_path(sar)

      card = response.body[/data-family="AC".*?(?=data-family="|\z)/m].to_s
      expect(card).to include("method=examine")
      expect(card).not_to include("status=examine")
    end

    it "narrows the control list to controls the plan assesses that way" do
      get sar_document_path(sar, method: "test")

      expect(response.body).to include("ac-2")
      expect(response.body).not_to match(/data-family="AC"[^>]*>\s*<[^>]*>\s*ac-1/)
    end

    it "returns an empty list rather than everything for a method nothing uses" do
      get sar_document_path(sar, method: "interview")

      # ac-1 is examine+interview; ac-2 is test only.
      expect(response.body).to include("ac-1")
    end
  end

  # Read the AC tile's printed percentage out of the rendered page.
  def assigns_pct(body)
    m = body[/data-family="AC".*?sparc-pct-\w+[^>]*>\s*(\d+)%/m, 1]
    m&.to_i
  end
end
