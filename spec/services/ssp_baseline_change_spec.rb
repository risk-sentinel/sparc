# frozen_string_literal: true

require "rails_helper"

# #1330 — changing the baseline an SSP is based on (owner decisions,
# 2026-11-03): controls the new baseline adds are created; controls in both are
# untouched; controls it drops are KEPT when they hold any answer (marked, and
# left out of the export) and REMOVED when they hold none. Published SSPs stay
# fixed.
RSpec.describe SspBaselineChange do
  def resolved(*ids)
    { "catalog" => { "uuid" => SecureRandom.uuid, "metadata" => { "title" => "Resolved", "oscal-version" => "1.1.2" },
                     "groups" => [ { "id" => "g", "title" => "Group",
                                     "controls" => ids.map { |id|
                                       { "id" => id, "title" => "Control #{id}",
                                         "parts" => [ { "id" => "#{id}_smt", "name" => "statement", "prose" => "Do #{id}.",
                                                        "parts" => [ { "id" => "#{id}_smt.a", "name" => "item",
                                                                       "prose" => "Part a of #{id}.",
                                                                       "props" => [ { "name" => "label", "value" => "a." } ] } ] } ] }
                                     } } ] } }
  end

  def baseline(name, *ids, published: true)
    create(:profile_document, name: name, lifecycle_status: published ? "published" : "started",
                              published: (Time.current.iso8601 if published), resolved_catalog_json: resolved(*ids))
  end

  let(:boundary) { create(:authorization_boundary) }
  let(:from) { baseline("Baseline A", "ac-1", "ac-2", "au-1") }
  let(:to) { baseline("Baseline B", "ac-1", "ac-3") }
  let(:ssp) { SspFromProfileService.new(from, authorization_boundary: boundary).create }

  def control(id) = ssp.ssp_controls.reload.find { ControlId.canonical(_1.control_id) == id }

  def answer!(id, text)
    control(id).ssp_control_statements.find_by!(statement_id: "#{id}_smt.a").update!(implementation_prose: text)
  end

  before do
    answer!("ac-1", "Kept in both.")
    answer!("ac-2", "Answered, but not in Baseline B.")
  end

  describe "#delta" do
    it "says what the change adds, keeps, removes and leaves alone" do
      delta = described_class.new(ssp, to).delta

      expect(delta.to_h).to eq(added: %w[ac-3], unchanged: %w[ac-1], kept: %w[ac-2], removed: %w[au-1])
    end

    it "keeps a dropped control for any recorded answer, not only a response" do
      control("au-1").ssp_control_statements.find_by!(statement_id: "au-1_smt.a")
                     .update!(implementation_status: "planned")

      expect(described_class.new(ssp, to).delta.kept).to include("au-1")
    end

    it "keeps a dropped control whose notes hold an answer" do
      control("au-1").ssp_control_fields.find_by!(field_name: "notes").update!(field_value: "Covered by the enterprise.")

      expect(described_class.new(ssp, to).delta.kept).to include("au-1")
    end

    it "changes nothing" do
      expect { described_class.new(ssp, to).delta }.not_to change { [ ssp.reload.profile_document_id, SspControl.count ] }
    end
  end

  describe "#apply!" do
    before { described_class.new(ssp, to).apply! }

    it "bases the SSP on the new baseline" do
      expect(ssp.reload.profile_document).to eq(to)
    end

    it "adds the new baseline's controls with a row for every item" do
      expect(control("ac-3").ssp_control_statements.pluck(:statement_id)).to match_array(%w[ac-3_smt ac-3_smt.a])
      expect(control("ac-3").uuid).to eq(OscalUuidService.derived(ssp.uuid, "ssp-control", "ac-3"))
    end

    it "leaves a control in both baselines, and its answer, as it was" do
      expect(control("ac-1").ssp_control_statements.find_by(statement_id: "ac-1_smt.a").implementation_prose)
        .to eq("Kept in both.")
      expect(control("ac-1").kept_outside_baseline).to be(false)
    end

    it "keeps an answered control the new baseline drops, marked as outside it" do
      expect(control("ac-2").kept_outside_baseline).to be(true)
      expect(control("ac-2").ssp_control_statements.find_by(statement_id: "ac-2_smt.a").implementation_prose)
        .to eq("Answered, but not in Baseline B.")
    end

    it "removes an unanswered control the new baseline drops" do
      expect(control("au-1")).to be_nil
    end

    it "clears the mark when a later change brings the control back into the baseline" do
      described_class.new(ssp.reload, from).apply!

      expect(control("ac-2").kept_outside_baseline).to be(false)
    end
  end

  describe "refusals" do
    it "refuses a published SSP, whose baseline is fixed" do
      ssp.update_columns(lifecycle_status: "published")

      expect { described_class.new(ssp, to).apply! }.to raise_error(described_class::Refused, /published.*copy/i)
      expect(ssp.reload.profile_document).to eq(from)
    end

    it "refuses a baseline that is not published" do
      draft = baseline("Draft", "ac-1", published: false)

      expect { described_class.new(ssp, draft).apply! }.to raise_error(described_class::Refused, /not published/)
    end

    it "refuses the baseline the SSP already uses" do
      expect { described_class.new(ssp, from).apply! }.to raise_error(described_class::Refused, /already uses/)
    end

    it "refuses no baseline" do
      expect { described_class.new(ssp, nil).apply! }.to raise_error(described_class::Refused, /Choose a baseline/)
    end
  end
end
