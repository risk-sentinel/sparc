require "rails_helper"

RSpec.describe SspUpdateService do
  let(:ssp) { create(:ssp_document) }
  let(:service) { described_class.new(ssp) }
  let(:control) { create(:ssp_control, ssp_document: ssp, control_id: "ac-1") }

  describe "#update_control" do
    it "updates an editable field" do
      create(:ssp_control_field, ssp_control: control, field_name: "status", field_value: "draft", editable: true)
      service.update_control("ac-1", { "status" => "implemented" })
      expect(control.ssp_control_fields.find_by(field_name: "status").field_value).to eq("implemented")
    end

    it "raises error for non-editable field" do
      create(:ssp_control_field, ssp_control: control, field_name: "control_id", field_value: "ac-1", editable: false)
      expect { service.update_control("ac-1", { "control_id" => "new-id" }) }.to raise_error(StandardError)
    end
  end
end
