require "rails_helper"

RSpec.describe FederationPeer, type: :model do
  it "requires a unique name" do
    described_class.create!(name: "Peer A", base_url: "https://peer-a.example.gov")
    duplicate = described_class.new(name: "Peer A", base_url: "https://peer-a2.example.gov")
    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:name]).to be_present
  end

  it "requires a valid http(s) base_url" do
    peer = described_class.new(name: "P", base_url: "not-a-url")
    expect(peer).not_to be_valid
    expect(peer.errors[:base_url]).to be_present
  end

  it "accepts http and https base_urls" do
    expect(described_class.new(name: "Pa", base_url: "https://a.gov")).to be_valid
    expect(described_class.new(name: "Pb", base_url: "http://b.gov")).to be_valid
  end

  it "encrypts the service token at rest" do
    peer = described_class.create!(name: "Encrypted",
                                   base_url: "https://peer.example.gov",
                                   service_token: "secret-value")
    raw = ActiveRecord::Base.connection
                            .select_value("SELECT encrypted_service_token FROM federation_peers WHERE id = #{peer.id}")
    expect(raw).not_to include("secret-value")
    peer.reload
    expect(peer.service_token).to eq("secret-value")
  end

  describe "scopes" do
    it "filters enabled and disabled peers" do
      on  = described_class.create!(name: "On",  base_url: "https://on.example.gov",  enabled: true)
      off = described_class.create!(name: "Off", base_url: "https://off.example.gov", enabled: false)
      expect(described_class.enabled.pluck(:id)).to eq([ on.id ])
      expect(described_class.disabled.pluck(:id)).to eq([ off.id ])
    end
  end
end
