# Re-encrypts FederationPeer credentials after a SPARC_HASH rotation
# (#419). The currently configured master (read by SparcKeyDerivation
# from the SPARC_HASH env var) is treated as the *new* master; the
# explicit `old_master` argument is used to decrypt rows that have not
# yet been rotated.
#
# Idempotency: each peer field is checked against the *current*
# encryptor first. If it decrypts cleanly, the row is already on the
# new master and is skipped. If it fails, the *old* encryptor decrypts
# it (raising if the ciphertext is corrupted), and the plaintext is
# re-assigned through the standard public setter so the row gets
# re-encrypted under the current master.
#
# All work runs inside a `FederationPeer.transaction`. Any peer with a
# ciphertext that decrypts under neither master aborts the transaction
# and returns an error result naming the offending peer.
#
# NIST 800-53:
#   IA-5  Authenticator Management — rotation of stored credentials
#   SC-12 Cryptographic Key Establishment — re-key under new master
#   AU-2  Audit Events — caller is expected to write a single
#         `sparc_hash_rotated` AuditEvent on success
class FederationPeerReencryptionService
  Result = Struct.new(:success, :rotated, :skipped, :error, :error_peer_id,
                      :old_fingerprint, :new_fingerprint,
                      keyword_init: true) do
    def success? = success
  end

  # Short prefix of SHA-256(master). Used in audit metadata to identify
  # which master was rotated from / to without exposing the raw value.
  def self.fingerprint(master)
    Digest::SHA256.hexdigest(master.to_s)[0, 16]
  end

  PROBE_PURPOSE = "sparc:v1:rotation_probe"

  def self.call(old_master:)
    new(old_master: old_master).call
  end

  def initialize(old_master:)
    @old_master      = old_master.to_s
    @rotated_peers   = []
    @skipped_peers   = []
    @old_encryptors  = {}
    @cur_encryptors  = {}
  end

  def call
    if @old_master.length < 32
      return failure("OLD_SPARC_HASH must be at least 32 characters")
    end

    if SparcKeyDerivation.master_matches_current?(@old_master)
      return failure("OLD_SPARC_HASH equals the current SPARC_HASH — nothing to rotate")
    end

    FederationPeer.transaction do
      FederationPeer.find_each do |peer|
        process_peer(peer)
      end
    end

    # ActiveRecord::Rollback is swallowed by the transaction block, so
    # check the abort flag set inside `decrypt_with_old` rather than
    # rescuing the (never-propagated) Rollback at this level.
    if @abort_reason
      return Result.new(success: false, error: @abort_reason, error_peer_id: @abort_peer_id)
    end

    Result.new(success: true,
               rotated: @rotated_peers, skipped: @skipped_peers,
               old_fingerprint: self.class.fingerprint(@old_master),
               new_fingerprint: self.class.fingerprint(SparcKeyDerivation.send(:master_secret)))
  end

  private

  def process_peer(peer)
    rotated_fields = []

    if try_rotate_field(peer, :encrypted_service_token, :service_token=,
                         FederationPeer::TOKEN_KEY_PURPOSE)
      rotated_fields << :service_token
    end

    if try_rotate_field(peer, :encrypted_signing_secret, :signing_secret=,
                         FederationPeer::SECRET_KEY_PURPOSE)
      rotated_fields << :signing_secret
    end

    if rotated_fields.any?
      peer.save!
      @rotated_peers << { peer_id: peer.id, name: peer.name, fields: rotated_fields }
    else
      @skipped_peers << { peer_id: peer.id, name: peer.name }
    end
  end

  # Returns true when this peer's field needed rotation and was
  # successfully re-encrypted. Returns false when there's nothing to do
  # (no ciphertext, or already under the current master). Aborts the
  # outer transaction when the ciphertext decrypts under neither master.
  def try_rotate_field(peer, ciphertext_attr, plaintext_setter, purpose)
    ciphertext = peer.public_send(ciphertext_attr)
    return false if ciphertext.blank?

    return false if decrypts_with_current?(ciphertext, purpose)

    plaintext = decrypt_with_old(ciphertext, purpose, peer: peer, attr: ciphertext_attr)
    peer.public_send(plaintext_setter, plaintext)
    true
  end

  def decrypts_with_current?(ciphertext, purpose)
    current_encryptor(purpose).decrypt_and_verify(ciphertext)
    true
  rescue StandardError
    # Any decryption/verification/decoding failure means the ciphertext
    # is not under the current master. Caller will then try the old
    # master.
    false
  end

  def decrypt_with_old(ciphertext, purpose, peer:, attr:)
    old_encryptor(purpose).decrypt_and_verify(ciphertext)
  rescue StandardError => e
    @abort_reason = "Peer #{peer.name.inspect} field #{attr} decrypts under neither old nor current master: #{e.class}"
    @abort_peer_id = peer.id
    raise ActiveRecord::Rollback
  end

  def current_encryptor(purpose)
    @cur_encryptors[purpose] ||= FederationPeer.build_encryptor(purpose)
  end

  def old_encryptor(purpose)
    @old_encryptors[purpose] ||= FederationPeer.build_encryptor_with_master(@old_master, purpose)
  end

  def failure(message)
    Result.new(success: false, error: message)
  end
end
