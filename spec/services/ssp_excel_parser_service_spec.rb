require 'rails_helper'

RSpec.describe SspExcelParserService do
  let(:document) { create(:ssp_document) }
  let(:file_path) { Rails.root.join('spec', 'fixtures', 'ssp_sample.xlsx') }
  let(:service) { described_class.new(document, file_path) }

  describe '#parse' do
    it 'creates controls from Excel file' do
      expect {
        service.parse
      }.to change(document.ssp_controls, :count).by_at_least(1)
    end

    it 'creates fields for each control' do
      service.parse
      control = document.ssp_controls.first

      expect(control.ssp_control_fields.count).to be > 0
    end

    it 'marks appropriate fields as editable' do
      service.parse
      control = document.ssp_controls.first

      editable_fields = control.ssp_control_fields.where(editable: true)
      expect(editable_fields.count).to be > 0
    end
  end
end
