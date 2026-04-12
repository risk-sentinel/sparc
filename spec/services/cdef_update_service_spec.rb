require "rails_helper"

RSpec.describe CdefUpdateService, type: :service do
  let(:cdef_document) { create(:cdef_document, status: "completed") }
  let!(:control) { create(:cdef_control, cdef_document: cdef_document, control_id: "ac-1", severity: "medium") }
  let!(:notes_field) do
    create(:cdef_control_field, cdef_control: control, field_name: "notes", field_value: "original notes")
  end
  let(:service) { described_class.new(cdef_document) }

  describe "#update_field" do
    it "updates an editable field" do
      service.update_field("ac-1", "notes", "updated notes")
      expect(notes_field.reload.field_value).to eq("updated notes")
    end

    it "creates a new field row if it doesn't exist" do
      service.update_field("ac-1", "implementation_status", "implemented")
      field = control.cdef_control_fields.find_by(field_name: "implementation_status")
      expect(field).to be_present
      expect(field.field_value).to eq("implemented")
      expect(field.editable).to be true
    end

    it "regenerates the document UUID" do
      old_uuid = cdef_document.uuid
      service.update_field("ac-1", "notes", "changed")
      expect(cdef_document.reload.uuid).not_to eq(old_uuid)
    end

    it "rejects non-editable fields" do
      expect {
        service.update_field("ac-1", "description", "hacked")
      }.to raise_error(ArgumentError, /not editable/)
    end

    it "raises for unknown control_id" do
      expect {
        service.update_field("zz-99", "notes", "value")
      }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end

  describe "#update_severity" do
    it "updates the severity column" do
      service.update_severity("ac-1", "high")
      expect(control.reload.severity).to eq("high")
    end

    it "rejects invalid severity values" do
      expect {
        service.update_severity("ac-1", "critical")
      }.to raise_error(ArgumentError, /Invalid severity/)
    end
  end

  describe "#update_control" do
    it "updates multiple fields at once" do
      service.update_control("ac-1", {
        "notes" => "batch update",
        "implementation_status" => "partial"
      })
      expect(notes_field.reload.field_value).to eq("batch update")
      status_field = control.cdef_control_fields.find_by(field_name: "implementation_status")
      expect(status_field.field_value).to eq("partial")
    end
  end

  describe "#bulk_update" do
    let!(:control2) { create(:cdef_control, cdef_document: cdef_document, control_id: "ac-2", severity: "low") }

    it "updates multiple controls in one transaction" do
      service.bulk_update({
        "ac-1" => { "notes" => "updated ac-1" },
        "ac-2" => { "severity" => "high", "implementation_status" => "implemented" }
      })
      expect(notes_field.reload.field_value).to eq("updated ac-1")
      expect(control2.reload.severity).to eq("high")
    end
  end
end
