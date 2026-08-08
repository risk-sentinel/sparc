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

  # #913 — a row with no control id is not a control.
  #
  # In a spreadsheet SSP these are continuation lines; OSCAL models them as a
  # LEVERAGED SSP, not as a control of this system. Importing them produced
  # `SspControl` rows with no control_id and no derived family, which is what
  # made `control_id.to_s.split("-").first.upcase` raise across the app. The
  # blank state was manufactured here and guarded against everywhere else.
  #
  # The sample fixture carries exactly one such row (row 3: no control id,
  # prose "Provider statement: IAM system enforces MFA for all privileged
  # users."), so this is a real case rather than a constructed one.
  describe 'rows with no control id (#913)' do
    it 'imports none of them as controls' do
      service.parse

      expect(document.ssp_controls.where(control_id: [ nil, '' ])).to be_empty
    end

    it 'keeps every row that does name a control' do
      service.parse

      expect(document.ssp_controls.pluck(:control_id)).to contain_exactly('ac-1', 'ac-2', 'ac-3')
    end

    # A lossy import must not be a silent one.
    it 'records how many rows it dropped' do
      service.parse

      expect(document.reload.import_metadata['dropped_rows_without_control_id']).to eq(1)
    end

    # The point of the whole change: the state that made the family derivation
    # raise can no longer be produced by an import.
    it 'leaves no control whose family cannot be derived' do
      service.parse

      expect {
        document.ssp_controls.each { |c| c.control_id.to_s.split('-').first.upcase }
      }.not_to raise_error
    end
  end
end
