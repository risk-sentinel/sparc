require "rails_helper"

RSpec.describe SspUpdateService do
  let(:ssp) { create(:ssp_document) }
  let(:service) { described_class.new(ssp) }
  let(:control) { create(:ssp_control, ssp_document: ssp, control_id: "ac-1") }

  describe "#update_control" do
    it "updates an editable field" do
      create(:ssp_control_field, ssp_control: control, field_name: "notes", field_value: "draft", editable: true)
      service.update_control("ac-1", { "notes" => "revised" })
      expect(control.ssp_control_fields.find_by(field_name: "notes").field_value).to eq("revised")
    end

    # #1312 — status is each statement item's own.
    it "refuses the retired control-level status" do
      control
      expect { service.update_control("ac-1", { "status" => "Implemented" }) }.to raise_error(StandardError, /not editable/)
    end

    it "raises error for non-editable field" do
      create(:ssp_control_field, ssp_control: control, field_name: "control_id", field_value: "ac-1", editable: false)
      expect { service.update_control("ac-1", { "control_id" => "new-id" }) }.to raise_error(StandardError)
    end
  end
end
