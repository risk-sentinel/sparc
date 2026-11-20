# frozen_string_literal: true

require "ipaddr"

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
#     to.
#
# NIST SP 800-53: CA-3 (information exchange), SA-9 (external system
# services), IA-9 (service identification — key and host pinning), SC-8,
# IA-5 (encrypted credential), AC-3.
class ExchangeConnection < ApplicationRecord
  CREDENTIAL_KEY_PURPOSE = "exchange_connection_credential"
  AUTH_SCHEMES = %w[none bearer header].freeze
  CERTIFICATION_CLASSES = %w[A B C D].freeze
  CERTIFICATION_TYPES = %w[20x Rev5].freeze
  # GSA's form, as the FedRAMP Marketplace records it (ZD_frid_retro): F or FR,
  # ten digits, an optional suffix. Agency-registered IDs are letters.
  FEDRAMP_ID = /\A(?:FR?\d{10}[A-Z]{0,2}|AGENCY[A-Z0-9]+)\z/
  MAX_SPKI_PINS = 2

  belongs_to :authorization_boundary
  belongs_to :created_by, class_name: "User", optional: true
  has_many :document_sources, class_name: "ExchangeDocumentSource", dependent: :destroy, inverse_of: :exchange_connection
  has_many :received_documents, dependent: :nullify

  validates :name, presence: true, uniqueness: true
  validates :auth_scheme, inclusion: { in: AUTH_SCHEMES }
  validates :auth_header_name, presence: true, format: { with: /\A[A-Za-z0-9-]+\z/ }, if: -> { auth_scheme == "header" }
  validates :certification_class, inclusion: { in: CERTIFICATION_CLASSES }, allow_blank: true
  validates :certification_type, inclusion: { in: CERTIFICATION_TYPES }, allow_blank: true
  validates :fedramp_id, format: { with: FEDRAMP_ID, message: "is not a FedRAMP ID (F or FR and ten digits)" }, allow_blank: true
  validate :root_url_is_https
  validate :pins_are_well_formed

  before_validation :normalize_lists

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

  def self.credential_encryptor
    @credential_encryptor ||= FederationPeer.build_encryptor(CREDENTIAL_KEY_PURPOSE)
  end

  def self.reset_encryptors! = (@credential_encryptor = nil)

  private

  def normalize_lists
    self.spki_sha256 = Array(spki_sha256).flat_map { |v| v.to_s.split(/[\s,]+/) }.map { |v| v.delete(":").downcase }.compact_blank.uniq
    self.allowed_cidrs = Array(allowed_cidrs).flat_map { |v| v.to_s.split(/[\s,]+/) }.compact_blank.uniq
    self.fedramp_id = fedramp_id.to_s.strip.upcase.presence
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
