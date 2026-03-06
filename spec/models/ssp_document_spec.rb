require 'rails_helper'

RSpec.describe SspDocument, type: :model do
  describe 'validations' do
    it { should validate_presence_of(:name) }
    it { should validate_inclusion_of(:file_type).in_array(%w[excel json]) }
  end

  describe 'associations' do
    it { should have_many(:ssp_controls).dependent(:destroy) }
  end

  describe '#to_json_data' do
    let(:document) { create(:ssp_document) }
    let!(:control) { create(:ssp_control, ssp_document: document) }
    let!(:field) { create(:ssp_control_field, ssp_control: control) }

    it 'returns properly formatted JSON data' do
      result = document.to_json_data

      expect(result[:document_name]).to eq(document.name)
      expect(result[:controls]).to be_an(Array)
      expect(result[:controls].first[:control_id]).to eq(control.control_id)
    end
  end

  describe '.from_excel' do
    let(:file_path) { Rails.root.join('spec', 'fixtures', 'ssp_sample.xlsx') }
    let(:filename) { 'ssp_sample.xlsx' }

    it 'creates document and parses controls' do
      expect {
        SspDocument.from_excel(file_path, filename)
      }.to change(SspDocument, :count).by(1)
        .and change(SspControl, :count).by_at_least(1)
    end

    it 'sets status to completed on success' do
      document = SspDocument.from_excel(file_path, filename)
      expect(document.status).to eq('completed')
    end
  end
end
