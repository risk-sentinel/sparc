require "rails_helper"

RSpec.describe FederationPeerReencryptionService do
  # The "current" master is whatever SparcKeyDerivation reads from
  # SPARC_HASH (or falls back to secret_key_base in test). The "old"
  # master is provided explicitly for these tests.
  let(:old_master) { "x" * 48 }

  # Build a peer whose stored ciphertexts were encrypted under the OLD
  # master. We do this by temporarily encrypting via the old-master
  # encryptor, then writing the ciphertext directly to the model.
  def peer_encrypted_with_old(name:, token:, signing_secret:)
    peer = FederationPeer.create!(name: name, base_url: "https://#{name.parameterize}.example.gov")
    old_token_enc  = FederationPeer.build_encryptor_with_master(old_master, FederationPeer::TOKEN_KEY_PURPOSE)
    old_secret_enc = FederationPeer.build_encryptor_with_master(old_master, FederationPeer::SECRET_KEY_PURPOSE)
    peer.update_columns(
      encrypted_service_token:  old_token_enc.encrypt_and_sign(token),
      encrypted_signing_secret: old_secret_enc.encrypt_and_sign(signing_secret)
    )
    peer
  end

  describe ".call" do
    it "re-encrypts every peer's secrets under the current master" do
      peer = peer_encrypted_with_old(name: "Peer A", token: "tok-A", signing_secret: "sig-A")

      result = described_class.call(old_master: old_master)

      expect(result).to be_success
      expect(result.rotated.size).to eq(1)
      expect(result.skipped).to be_empty

      peer.reload
      expect(peer.service_token).to eq("tok-A")
      expect(peer.signing_secret).to eq("sig-A")
    end

    it "is idempotent — re-running after a successful rotation skips already-rotated peers" do
      peer_encrypted_with_old(name: "Peer B", token: "tok-B", signing_secret: "sig-B")

      first  = described_class.call(old_master: old_master)
      second = described_class.call(old_master: old_master)

      expect(first).to be_success
      expect(first.rotated.size).to eq(1)
      expect(second).to be_success
      expect(second.rotated.size).to eq(0)
      expect(second.skipped.size).to eq(1)
    end

    it "rotates only the fields that need it (mixed peer)" do
      # Peer with service_token under old master + signing_secret already
      # under current master. Should rotate only service_token.
      peer = FederationPeer.create!(name: "Mixed", base_url: "https://m.example.gov",
                                     signing_secret: "current-sig")
      old_token_enc = FederationPeer.build_encryptor_with_master(old_master, FederationPeer::TOKEN_KEY_PURPOSE)
      peer.update_column(:encrypted_service_token,
                         old_token_enc.encrypt_and_sign("old-token"))

      result = described_class.call(old_master: old_master)

      expect(result).to be_success
      expect(result.rotated.size).to eq(1)
      expect(result.rotated.first[:fields]).to eq([ :service_token ])
      peer.reload
      expect(peer.service_token).to eq("old-token")
      expect(peer.signing_secret).to eq("current-sig")
    end

    it "ignores peers with no encrypted credentials" do
      FederationPeer.create!(name: "Empty", base_url: "https://e.example.gov")

      result = described_class.call(old_master: old_master)

      expect(result).to be_success
      expect(result.rotated).to be_empty
      expect(result.skipped.size).to eq(1)
    end

    it "fails fast when OLD_SPARC_HASH is shorter than 32 chars" do
      result = described_class.call(old_master: "short")
      expect(result).not_to be_success
      expect(result.error).to match(/at least 32 characters/i)
    end

    it "refuses when OLD_SPARC_HASH equals the current master" do
      current = SparcKeyDerivation.send(:master_secret)
      result = described_class.call(old_master: current)
      expect(result).not_to be_success
      expect(result.error).to match(/equals the current/i)
    end

    it "aborts the transaction and surfaces the offending peer when ciphertext decrypts under neither master" do
      good_peer = peer_encrypted_with_old(name: "Good", token: "tok-G", signing_secret: "sig-G")
      bad_peer  = FederationPeer.create!(name: "Bad", base_url: "https://b.example.gov")
      bad_peer.update_column(:encrypted_service_token, "garbage-not-a-real-ciphertext")

      result = described_class.call(old_master: old_master)

      expect(result).not_to be_success
      expect(result.error).to match(/decrypts under neither/i)
      expect(result.error_peer_id).to eq(bad_peer.id)

      # Good peer was NOT rotated because the transaction rolled back.
      good_peer.reload
      old_token_enc = FederationPeer.build_encryptor_with_master(old_master, FederationPeer::TOKEN_KEY_PURPOSE)
      expect(old_token_enc.decrypt_and_verify(good_peer.encrypted_service_token)).to eq("tok-G")
    end

    it "exposes old + new fingerprints on the success result for audit logging" do
      peer_encrypted_with_old(name: "Audit", token: "t", signing_secret: "s")

      result = described_class.call(old_master: old_master)

      expect(result.old_fingerprint).to eq(described_class.fingerprint(old_master))
      expect(result.new_fingerprint).not_to eq(result.old_fingerprint)
      expect(result.new_fingerprint.length).to eq(16)
    end
  end
end
