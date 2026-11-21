# frozen_string_literal: true

require "base64"
require "digest"
require "ipaddr"
require "openssl"

# Another system SPARC pulls FedRAMP, OSCAL, HDF or XCCDF documents from
# (#1354). Registered in Settings by an administrator, or by a holder of
# `connections.manage`.
#
# A connection names:
#   - who: the provider's FedRAMP ID, certification class (A–D) and type
#     (20x or Rev5);
#   - where: the root trust-center address and each document to pull
#     (exchange_document_sources). SPARC may crawl the root to list documents,
#     but pulls only the ones set here (owner, 2026-11-20);
#   - the boundary its documents land in;
#   - how SPARC authenticates there: none, a bearer token, or a named header.
#     The credential is encrypted at rest (as FederationPeer's are) and is
#     never shown again;
#   - trust pins: the hosts SPARC may reach (the hosts of the addresses
#     registered here, and no others), the TLS public-key SHA-256 (up to two,
#     so the provider can rotate), and optionally the IP ranges it may resolve
#     to;
#   - push: the Ed25519 public keys (up to two, for rotation) whose signature
#     lets the provider tell SPARC a registered document changed
#     (ExchangePushService). With no key, the connection takes no pushes;
#   - Class A (FedRAMP FRC-CLA-ASF): the alternative security framework the
#     certification rests on and its date. It expires 12 months later
#     (FRC-CLA-ASF: "within the past 12 months"); the materials behind it
#     (FRC-CLA-EAM) are received documents of the boundary, reviewed there
#     (CertificationMaterialService).
#
# NIST SP 800-53: CA-3 (information exchange), SA-9 (external system
# services), IA-9 (service identification — key and host pinning), SC-8,
# IA-5 (encrypted credential), AC-3, SC-23 and AU-10 (signed push), CA-6
# (Class A expiry).
class ExchangeConnection < ApplicationRecord
  CREDENTIAL_KEY_PURPOSE = "exchange_connection_credential"
  AUTH_SCHEMES = %w[none bearer header].freeze
  CERTIFICATION_CLASSES = %w[A B C D].freeze
  CERTIFICATION_TYPES = %w[20x Rev5].freeze
  # GSA's form, as the FedRAMP Marketplace records it (ZD_frid_retro): F or FR,
  # ten digits, an optional suffix. Agency-registered IDs are letters.
  FEDRAMP_ID = /\A(?:FR?\d{10}[A-Z]{0,2}|AGENCY[A-Z0-9]+)\z/
  MAX_SPKI_PINS = 2
  MAX_PUSH_KEYS = 2
  CLASS_A_VALIDITY = 12.months

  # FRC-CLA-ASF's approved alternative security frameworks, in its words.
  # FedRAMP Ready is listed apart from Rev5 because FRC-CLA-EAM asks it for
  # different materials.
  CLASS_A_FRAMEWORKS = {
    "fedramp_rev5" => "FedRAMP Rev5",
    "fedramp_ready" => "FedRAMP Ready",
    "soc2_type2" => "SOC 2 Type II",
    "govramp" => "GovRAMP"
  }.freeze

  # FRC-CLA-EAM's external assessment materials, in its words.
  CLASS_A_MATERIALS = {
    "soc2_report" => "SOC 2 Type II complete report",
    "bridge_letter" => "Bridge or gap letter",
    "audit_engagement" => "Verified audit engagement documentation",
    "report_schedule" => "Estimated schedule for upcoming report",
    "readiness_assessment_report" => "Readiness Assessment Report",
    "security_assessment_plan" => "Security Assessment Plan",
    "supplemental_evidence" => "Supplemental compliance evidence",
    "other" => "Other required material"
  }.freeze

  belongs_to :authorization_boundary
  belongs_to :created_by, class_name: "User", optional: true
  has_many :document_sources, class_name: "ExchangeDocumentSource", dependent: :destroy, inverse_of: :exchange_connection
  has_many :received_documents, dependent: :nullify
  has_many :push_receipts, class_name: "ExchangePushReceipt", dependent: :destroy, inverse_of: :exchange_connection

  validates :name, presence: true, uniqueness: true
  validates :auth_scheme, inclusion: { in: AUTH_SCHEMES }
  validates :auth_header_name, presence: true, format: { with: /\A[A-Za-z0-9-]+\z/ }, if: -> { auth_scheme == "header" }
  validates :certification_class, inclusion: { in: CERTIFICATION_CLASSES }, allow_blank: true
  validates :certification_type, inclusion: { in: CERTIFICATION_TYPES }, allow_blank: true
  validates :fedramp_id, format: { with: FEDRAMP_ID, message: "is not a FedRAMP ID (F or FR and ten digits)" }, allow_blank: true
  validates :class_a_framework, inclusion: { in: CLASS_A_FRAMEWORKS.keys }, allow_blank: true
  validates :class_a_certified_on, presence: true, if: -> { class_a_framework.present? }
  validate :root_url_is_https
  validate :pins_are_well_formed
  validate :push_keys_are_ed25519
  validate :class_a_is_consistent

  before_validation :normalize_lists
  before_validation :drop_class_a_when_reclassified
  before_validation :set_class_a_expiry

  scope :enabled, -> { where(enabled: true) }

  def credential
    return nil if encrypted_credential.blank?

    self.class.credential_encryptor.decrypt_and_verify(encrypted_credential)
  rescue ActiveSupport::MessageEncryptor::InvalidMessage, ActiveSupport::MessageVerifier::InvalidSignature
    nil
  end

  def credential=(value)
    self.encrypted_credential = value.present? ? self.class.credential_encryptor.encrypt_and_sign(value.to_s) : nil
  end

  def credential? = encrypted_credential.present?

  # The headers SPARC sends with each request to this connection.
  def request_headers
    case auth_scheme
    when "bearer" then credential.present? ? { "Authorization" => "Bearer #{credential}" } : {}
    when "header" then credential.present? ? { auth_header_name => credential } : {}
    else {}
    end
  end

  # Hosts SPARC may reach for this connection: those of its registered
  # addresses, never one a fetched document mentions.
  def pinned_hosts
    urls = [ root_url, *document_sources.map(&:url) ].compact_blank
    urls.filter_map { |u| URI(u).host&.downcase rescue nil }.uniq
  end

  # A connection takes pushes only when it is enabled and has a key pinned.
  def push_enabled? = enabled? && push_public_keys.any?

  # The pinned keys as OpenSSL keys, for ExchangePushService.
  def push_keys
    push_public_keys.filter_map { |key| self.class.ed25519_key(key) }
  end

  # A short, stable name for a pinned key, shown and audited instead of the key.
  def self.key_fingerprint(base64_key)
    Digest::SHA256.hexdigest(Base64.strict_decode64(base64_key)).first(16)
  rescue ArgumentError
    nil
  end

  def self.ed25519_key(base64_key)
    OpenSSL::PKey.new_raw_public_key("ED25519", Base64.strict_decode64(base64_key))
  rescue ArgumentError, OpenSSL::PKey::PKeyError
    nil
  end

  # A key as an administrator pastes it: a PEM public key, or the base64 of
  # the raw 32 bytes. Stored as the latter; nil when it is neither.
  def self.normalize_push_key(value)
    text = value.to_s.strip
    return nil if text.empty?

    raw = text.include?("BEGIN PUBLIC KEY") ? raw_key_from_pem(text) : raw_key_from_base64(text)
    raw && Base64.strict_encode64(raw)
  rescue ArgumentError, OpenSSL::PKey::PKeyError
    nil
  end

  def self.raw_key_from_pem(text)
    key = OpenSSL::PKey.read(text)
    key.oid == "ED25519" ? key.raw_public_key : nil
  end

  def self.raw_key_from_base64(text)
    decoded = Base64.strict_decode64(text)
    decoded.bytesize == 32 ? decoded : nil
  end

  def class_a? = certification_class == "A"
  def class_a_recorded? = class_a_framework.present? && class_a_certified_on.present?
  def class_a_framework_label = CLASS_A_FRAMEWORKS[class_a_framework]

  # Expired once its expiry date is reached: FRC-CLA-ASF asks for a
  # certification "within the past 12 months".
  def class_a_expired?(today = Date.current)
    class_a_expires_on.present? && class_a_expires_on <= today
  end

  def class_a_days_left(today = Date.current)
    class_a_expires_on && (class_a_expires_on - today).to_i
  end

  def self.credential_encryptor
    @credential_encryptor ||= FederationPeer.build_encryptor(CREDENTIAL_KEY_PURPOSE)
  end

  def self.reset_encryptors! = (@credential_encryptor = nil)

  private

  def normalize_lists
    self.push_public_keys = Array(push_public_keys).flat_map { |v| split_keys(v) }.map { |v| self.class.normalize_push_key(v) || v.to_s.strip }
                                                   .compact_blank.uniq
    self.spki_sha256 = Array(spki_sha256).flat_map { |v| v.to_s.split(/[\s,]+/) }.map { |v| v.delete(":").downcase }.compact_blank.uniq
    self.allowed_cidrs = Array(allowed_cidrs).flat_map { |v| v.to_s.split(/[\s,]+/) }.compact_blank.uniq
    self.fedramp_id = fedramp_id.to_s.strip.upcase.presence
  end

  # A pasted PEM spans several lines; base64 keys are one token each.
  def split_keys(value)
    text = value.to_s
    return text.scan(/-----BEGIN PUBLIC KEY-----.*?-----END PUBLIC KEY-----/m) if text.include?("BEGIN PUBLIC KEY")

    text.split(/[\s,]+/)
  end

  # Moving a connection off Class A drops its Class A record, unless the same
  # change also sets one (which class_a_is_consistent then refuses).
  def drop_class_a_when_reclassified
    return if class_a? || !will_save_change_to_certification_class?
    return if will_save_change_to_class_a_framework? || will_save_change_to_class_a_certified_on?

    self.class_a_framework = nil
    self.class_a_certified_on = nil
  end

  def set_class_a_expiry
    self.class_a_expires_on = class_a_certified_on && (class_a_certified_on + CLASS_A_VALIDITY)
  end

  def push_keys_are_ed25519
    if push_public_keys.size > MAX_PUSH_KEYS
      errors.add(:push_public_keys, "holds at most #{MAX_PUSH_KEYS} keys (the current one and the next)")
    end
    bad = push_public_keys.reject { |key| self.class.ed25519_key(key) }
    errors.add(:push_public_keys, "must be Ed25519 public keys (PEM, or base64 of the 32 raw bytes)") if bad.any?
  end

  def class_a_is_consistent
    if (class_a_framework.present? || class_a_certified_on.present?) && !class_a?
      errors.add(:class_a_framework, "is recorded only for a Class A certification")
    end
    return if class_a_certified_on.nil? || class_a_certified_on <= Date.current

    errors.add(:class_a_certified_on, "cannot be in the future")
  end

  def root_url_is_https
    return if root_url.blank?

    uri = URI(root_url)
    errors.add(:root_url, "must be an https:// address") unless uri.is_a?(URI::HTTPS) && uri.host.present? && uri.userinfo.nil?
  rescue URI::InvalidURIError
    errors.add(:root_url, "is not a valid address")
  end

  def pins_are_well_formed
    if spki_sha256.size > MAX_SPKI_PINS
      errors.add(:spki_sha256, "holds at most #{MAX_SPKI_PINS} keys (the current one and the next)")
    end
    bad = spki_sha256.reject { |v| v.match?(/\A\h{64}\z/) }
    errors.add(:spki_sha256, "must be SHA-256 values in hex (#{bad.first})") if bad.any?
    allowed_cidrs.each do |cidr|
      IPAddr.new(cidr)
    rescue IPAddr::InvalidAddressError
      errors.add(:allowed_cidrs, "has an invalid range: #{cidr}")
    end
  end
end
