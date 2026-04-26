# Signs and verifies authoritative back-matter federation bundles using
# HMAC-SHA256. The shared secret is per-peer (FederationPeer#signing_secret)
# so trust is bilateral; the secret itself is encrypted at rest using a
# SparcKeyDerivation key derived from SPARC_HASH.
#
# Bundle envelope format:
#   {
#     "payload":   "<base64url-encoded canonical JSON>",
#     "signature": "<hex HMAC-SHA256 of the base64url payload>",
#     "alg":       "HS256",
#     "key_id":    "<peer name — used for log + audit, NOT trust>"
#   }
#
# The signature covers the base64url-encoded payload exactly so middleboxes
# that re-encode JSON cannot break verification. The `key_id` is metadata
# only; verification always uses the configured peer's secret.
#
# NIST 800-53:
#   SC-8   Transmission Confidentiality and Integrity
#   SC-12  Cryptographic Key Establishment
#   SC-13  Cryptographic Protection (HMAC-SHA256)
#   AU-10  Non-Repudiation (signature ties bundle to peer)
class FederationBundleSigningService
  ALGORITHM    = "HS256"
  DIGEST       = "SHA256"
  MAX_CLOCK_SKEW = 5.minutes

  Result = Struct.new(:success, :payload, :error, keyword_init: true) do
    def success? = success
  end

  # ── Sign ────────────────────────────────────────────────────────────
  # `payload_hash` is a Ruby Hash that will be canonicalized + signed.
  # Returns the envelope hash ready to be rendered as JSON.
  def self.sign(payload_hash, peer:)
    secret = peer.signing_secret
    raise ArgumentError, "Peer #{peer.name.inspect} has no signing_secret configured" if secret.blank?

    canonical = canonicalize(payload_hash)
    encoded   = Base64.urlsafe_encode64(canonical, padding: false)
    {
      "alg"       => ALGORITHM,
      "key_id"    => peer.name,
      "payload"   => encoded,
      "signature" => OpenSSL::HMAC.hexdigest(DIGEST, secret, encoded)
    }
  end

  # ── Verify ──────────────────────────────────────────────────────────
  # Accepts a parsed envelope hash and a peer; returns Result.
  # Validates structure, algorithm, signature, and (if present) bundle
  # `generated_at` is within MAX_CLOCK_SKEW of now.
  def self.verify(envelope, peer:)
    secret = peer.signing_secret
    return failure("Peer has no signing_secret configured") if secret.blank?
    return failure("Envelope is not a hash")              unless envelope.is_a?(Hash)
    return failure("Unsupported algorithm")               unless envelope["alg"] == ALGORITHM

    encoded   = envelope["payload"].to_s
    signature = envelope["signature"].to_s
    return failure("Missing payload or signature") if encoded.empty? || signature.empty?

    expected = OpenSSL::HMAC.hexdigest(DIGEST, secret, encoded)
    return failure("Signature does not verify") unless secure_compare(expected, signature)

    payload = decode_payload(encoded)
    return failure("Payload is not valid JSON") if payload.nil?

    skew_error = clock_skew_error(payload)
    return failure(skew_error) if skew_error

    Result.new(success: true, payload: payload)
  end

  def self.canonicalize(hash)
    JSON.generate(deep_sort(hash))
  end

  # Sort hash keys recursively so canonicalization is deterministic.
  def self.deep_sort(value)
    case value
    when Hash
      value.keys.map(&:to_s).sort.each_with_object({}) do |k, acc|
        acc[k] = deep_sort(value[k] || value[k.to_sym])
      end
    when Array
      value.map { |v| deep_sort(v) }
    else
      value
    end
  end

  def self.decode_payload(encoded)
    JSON.parse(Base64.urlsafe_decode64(encoded))
  rescue ArgumentError, JSON::ParserError
    nil
  end

  def self.clock_skew_error(payload)
    raw = payload.dig("metadata", "generated_at")
    return nil if raw.blank?

    generated_at = Time.iso8601(raw)
    drift = (Time.current - generated_at).abs
    return "Bundle clock skew #{drift.to_i}s exceeds tolerance" if drift > MAX_CLOCK_SKEW

    nil
  rescue ArgumentError
    "Bundle metadata.generated_at is not a valid ISO-8601 timestamp"
  end

  def self.secure_compare(a, b)
    ActiveSupport::SecurityUtils.secure_compare(a.to_s, b.to_s)
  end

  def self.failure(message)
    Result.new(success: false, error: message)
  end
end
