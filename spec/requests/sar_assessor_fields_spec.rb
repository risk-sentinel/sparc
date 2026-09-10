# frozen_string_literal: true

require "rails_helper"

# #1114 — what an assessor records, pruned to what NIST can carry.
#
# The list was the legacy Test Plan Results SPREADSHEET vocabulary, inherited
# when `0b04dc25` renamed TPR to SAR "for OSCAL alignment" without remodelling
# the fields. Owner review: "Custom, Custom Name should be removed from the UI.
# Custom Author should be 'Assessor' and be the user logged in", "Date should be
# a date picker with the current date/time pre-selected", "Test Text is still
# missing the 800-53a".
RSpec.describe "SAR assessor fields (#1114)", type: :request do
  let(:user) { create(:user, :admin) }
  let(:sar)  { create(:sar_document) }
  let!(:control) { sar.sar_controls.create!(control_id: "ac-1", title: "Policy", row_order: 0) }

  before { sign_in_as(user) }

  describe "the retired spreadsheet columns" do
    it "offers no editor for custom or custom name" do
      get sar_document_path(sar)

      expect(response.body).not_to include("fields[custom]")
      expect(response.body).not_to include("fields[custom_name]")
      expect(response.body).not_to include("fields[custom_author]")
    end

    # 800-53A states the expected result as determination statements, and SPARC
    # stores them. A human retyping it duplicates the catalog and can contradict
    # it — the catalog is authoritative (#1113).
    it "offers no editor for expected result or test text" do
      get sar_document_path(sar)

      expect(response.body).not_to include("fields[expected_result]")
      expect(response.body).not_to include("fields[test_text]")
    end

    # The columns stay: existing SARs hold values and the Excel importer writes
    # them. Retiring the UI must not delete an assessor's work.
    it "keeps the columns readable" do
      control.sar_control_fields.create!(field_name: "expected_result", field_value: "legacy value")

      expect(control.reload.sar_control_fields.find_by(field_name: "expected_result").field_value)
        .to eq("legacy value")
    end
  end

  describe "assessor" do
    it "is offered instead of custom author" do
      get sar_document_path(sar)

      expect(response.body).to include("fields[assessor]")
    end

    it "defaults to the signed-in user rather than an empty box" do
      get sar_document_path(sar)

      expect(response.body).to match(/fields\[assessor\][^>]*value="[^"]+"/),
        "the assessor field must be pre-filled with who is signed in"
    end

    it "keeps a value already recorded rather than overwriting it" do
      control.sar_control_fields.create!(field_name: "assessor", field_value: "Prior Assessor")

      get sar_document_path(sar)

      expect(response.body).to include("Prior Assessor")
    end
  end

  describe "date" do
    # This feeds OSCAL `observation.collected`, which the schema REQUIRES and
    # which must be a real timestamp — it was a 3-row textarea an assessor typed
    # a date into in whatever format occurred to them.
    it "is a datetime control, not a textarea" do
      get sar_document_path(sar)

      expect(response.body).to match(/type="datetime-local"[^>]*name="fields\[date\]"/)
        .or match(/name="fields\[date\]"[^>]*type="datetime-local"/)
    end

    it "pre-selects the current date and time" do
      get sar_document_path(sar)

      today = Time.zone.now.strftime("%Y-%m-%d")
      expect(response.body).to include(today)
    end
  end
end
