require "rails_helper"

RSpec.describe BackMatterResourceChange, type: :model do
  let(:ssp) { create(:ssp_document) }
  let(:resource) do
    BackMatterResource.create!(resourceable: ssp, title: "T", uuid: SecureRandom.uuid)
  end

  it "requires change_type and changed_at" do
    change = described_class.new(back_matter_resource: resource)
    expect(change).not_to be_valid
    expect(change.errors[:change_type]).to be_present
    expect(change.errors[:changed_at]).to be_present
  end

  it "rejects unknown change_type" do
    change = described_class.new(back_matter_resource: resource,
                                 change_type: "magic", changed_at: Time.current)
    expect(change).not_to be_valid
    expect(change.errors[:change_type]).to be_present
  end

  it "accepts each canonical change_type" do
    described_class::CHANGE_TYPES.each do |t|
      change = described_class.new(back_matter_resource: resource,
                                   change_type: t, changed_at: Time.current)
      expect(change).to be_valid, "expected #{t.inspect} to be a valid change_type"
    end
  end

  describe "scopes" do
    it "orders chronologically and reverse-chronologically" do
      first  = described_class.create!(back_matter_resource: resource,
                                       change_type: "create", changed_at: 2.days.ago)
      second = described_class.create!(back_matter_resource: resource,
                                       change_type: "update", changed_at: 1.day.ago)
      expect(described_class.chronological.pluck(:id)).to eq([ first.id, second.id ])
      expect(described_class.reverse_chronological.pluck(:id)).to eq([ second.id, first.id ])
    end

    it "filters by batch_uuid" do
      batch = SecureRandom.uuid
      described_class.create!(back_matter_resource: resource, change_type: "promote",
                              changed_at: Time.current, batch_uuid: batch)
      described_class.create!(back_matter_resource: resource, change_type: "update",
                              changed_at: Time.current, batch_uuid: SecureRandom.uuid)
      expect(described_class.for_batch(batch).count).to eq(1)
    end
  end
end
