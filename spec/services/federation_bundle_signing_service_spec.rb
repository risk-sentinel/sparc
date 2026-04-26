require "rails_helper"

RSpec.describe FederationBundleSigningService do
  let(:peer) do
    FederationPeer.create!(name: "Peer A", base_url: "https://peer-a.example.gov",
                           signing_secret: "shared-secret-32-bytes-or-longer-x")
  end
  let(:other_peer) do
    FederationPeer.create!(name: "Peer B", base_url: "https://peer-b.example.gov",
                           signing_secret: "different-secret-also-long-enough-y")
  end
  let(:payload) do
    {
      "bundle_version" => 1,
      "metadata" => {
        "instance_url" => "https://us.example.gov",
        "bundle_uuid"  => SecureRandom.uuid,
        "generated_at" => Time.current.utc.iso8601
      },
      "resources" => [
        { "uuid" => SecureRandom.uuid, "title" => "Policy" }
      ]
    }
  end

  describe ".sign and .verify" do
    it "round-trips a payload with the same peer" do
      envelope = described_class.sign(payload, peer: peer)
      expect(envelope["alg"]).to eq("HS256")
      expect(envelope["key_id"]).to eq("Peer A")
      expect(envelope["payload"]).to be_present
      expect(envelope["signature"]).to match(/\A[0-9a-f]{64}\z/)

      result = described_class.verify(envelope, peer: peer)
      expect(result).to be_success
      expect(result.payload["resources"].first["title"]).to eq("Policy")
    end

    it "rejects an envelope verified with the wrong peer" do
      envelope = described_class.sign(payload, peer: peer)
      result   = described_class.verify(envelope, peer: other_peer)

      expect(result).not_to be_success
      expect(result.error).to match(/Signature does not verify/i)
    end

    it "rejects a tampered payload" do
      envelope = described_class.sign(payload, peer: peer)
      tampered = envelope.merge("payload" => Base64.urlsafe_encode64('{"resources":[]}'))

      result = described_class.verify(tampered, peer: peer)
      expect(result).not_to be_success
      expect(result.error).to match(/Signature does not verify/i)
    end

    it "rejects an unknown algorithm" do
      envelope = described_class.sign(payload, peer: peer).merge("alg" => "RS256")
      result   = described_class.verify(envelope, peer: peer)

      expect(result).not_to be_success
      expect(result.error).to match(/Unsupported algorithm/i)
    end

    it "rejects an envelope with missing fields" do
      result = described_class.verify({ "alg" => "HS256" }, peer: peer)
      expect(result).not_to be_success
      expect(result.error).to match(/Missing payload or signature/i)
    end

    it "rejects when peer has no signing_secret configured" do
      bare = FederationPeer.create!(name: "Bare", base_url: "https://bare.example.gov")
      envelope = described_class.sign(payload, peer: peer)
      result   = described_class.verify(envelope, peer: bare)

      expect(result).not_to be_success
      expect(result.error).to match(/no signing_secret/i)
    end

    it "rejects payloads outside the clock-skew tolerance" do
      stale = payload.deep_dup
      stale["metadata"]["generated_at"] = (Time.current - 30.minutes).utc.iso8601

      envelope = described_class.sign(stale, peer: peer)
      result   = described_class.verify(envelope, peer: peer)

      expect(result).not_to be_success
      expect(result.error).to match(/clock skew/i)
    end
  end

  describe "canonical JSON" do
    it "produces stable signatures regardless of hash key order" do
      a = { "z" => 1, "a" => { "y" => 2, "x" => 3 } }
      b = { "a" => { "x" => 3, "y" => 2 }, "z" => 1 }

      expect(described_class.canonicalize(a)).to eq(described_class.canonicalize(b))
    end
  end

  describe ".sign" do
    it "raises when peer has no signing_secret" do
      bare = FederationPeer.create!(name: "Bare2", base_url: "https://bare2.example.gov")
      expect { described_class.sign(payload, peer: bare) }
        .to raise_error(ArgumentError, /no signing_secret/i)
    end
  end
end
