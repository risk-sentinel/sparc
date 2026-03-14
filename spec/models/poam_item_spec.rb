require "rails_helper"

RSpec.describe PoamItem, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:poam_document) }
  end

  describe "#to_hash" do
    it "returns a hash representation" do
      item = create(:poam_item)
      hash = item.to_hash

      expect(hash).to be_a(Hash)
      expect(hash).to have_key(:title)
    end
  end
end
