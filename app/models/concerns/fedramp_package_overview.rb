# frozen_string_literal: true

require "uri"

# #1390 — what a boundary records so SPARC can write its FedRAMP Certification
# Package Overview (FRC-CSO-PKG; CPO-CSO-OVR, CDS-CSO-PUB), and the address
# FedRAMP's reports name for it (certificationPackageOverviewUri).
#
#   fedramp_package    service identification and properties, keyed by
#                      FIELDS below. Assigning MERGES: a key sent blank is
#                      removed, a key not sent is kept, so a partial API
#                      update never erases the rest.
#   fedramp_contacts   the provider's contacts: a list on the boundary,
#                      separate from SPARC users (a contact may hold no SPARC
#                      account). Assigning replaces the list.
#
# The overview address is either the one set on the boundary (normally the
# provider's trust center, which FedRAMP requires: CDS-CSO-UTC) or, when
# fedramp_overview_from_sparc is set, SPARC's own overview endpoint under
# SPARC_APP_URL. That endpoint needs a SPARC token, so SPARC does not by
# itself meet the trust-center rules (CDS-TRC).
#
# Enumerations and the phone pattern are read from the vendored FedRAMP
# schema, so SPARC never keeps a second copy of them.
#
# NIST SP 800-53: CA-3 (information exchange), PL-2 (system description),
# SI-10 (information input validation).
module FedrampPackageOverview
  extend ActiveSupport::Concern

  DOCUMENT_TYPE = "certification-package-overview"
  OVERVIEW_PATH = "/api/v1/authorization_boundaries/%s/fedramp/certification_package_overview"
  CONTACT_TYPES = %w[Security Sales Primary].freeze
  REQUIRED_CONTACT_TYPES = %w[Security Sales].freeze
  MAX_CONTACTS = 20
  CONTACT_KEYS = %w[contact_type name email phone].freeze
  EMAIL_FORMAT = URI::MailTo::EMAIL_REGEXP
  URL_FORMAT = %r{\Ahttps?://[^\s/$.?#][^\s]*\z}i

  # key => [schema section, schema property, label, required?, kind]
  FIELDS = {
    "package_id" => [ "serviceIdentification", "fedRampPackageId", "FedRAMP ID", true, :string ],
    "uei_number" => [ "serviceIdentification", "ueiNumber", "UEI number", false, :string ],
    "provider_name" => [ "serviceIdentification", "providerName", "Provider name", true, :string ],
    "service_name" => [ "serviceIdentification", "serviceName", "Service name", true, :string ],
    "service_acronym" => [ "serviceIdentification", "serviceAcronym", "Service acronym", true, :string ],
    "service_description" => [ "serviceIdentification", "serviceDescription", "Service description", true, :text ],
    "certification_type" => [ "serviceIdentification", "certificationType", "Certification type", true, :enum ],
    "website" => [ "serviceIdentification", "website", "Website", true, :url ],
    "logo" => [ "serviceIdentification", "logo", "Logo address", true, :logo ],
    "service_types" => [ "serviceProperties", "serviceType", "Service model", true, :enum_list ],
    "deployment_model" => [ "serviceProperties", "deploymentModel", "Deployment model", true, :enum ],
    "business_categories" => [ "serviceProperties", "businessCategory", "Business categories", false, :enum_list ],
    "next_ocr_date" => [ "serviceProperties", "nextOngoingCertificationReportDate",
                         "Next ongoing certification report date", false, :date ]
  }.freeze

  # The trust center (serviceProperties.trustCenter, a FedRAMP repository).
  TRUST_CENTER_KEYS = %w[trust_center_url trust_center_description
                         trust_center_authentication_required trust_center_access_instructions].freeze
  # The certification profile beside the type (certification_type above):
  # path and class. Not part of the overview, whose schema has no field for
  # them; they decide which FedRAMP rules apply (FedrampRules).
  PROFILE_KEYS = %w[certification_path certification_class].freeze
  PACKAGE_KEYS = (FIELDS.keys + TRUST_CENTER_KEYS + PROFILE_KEYS).freeze
  BUSINESS_CATEGORY_MAX = 10
  LIST_KEYS = FIELDS.select { |_, f| f[4] == :enum_list }.keys.freeze

  # The strong-parameters filter for these fields, for the web form and the
  # API alike.
  PERMITTED_PARAMS = {
    fedramp_package: (PACKAGE_KEYS - LIST_KEYS) + [ LIST_KEYS.to_h { |k| [ k, [] ] } ],
    fedramp_contacts: CONTACT_KEYS
  }.freeze

  # How the attributes read in an error message ("FedRAMP package overview:
  # Logo address must be ...").
  HUMAN_NAMES = {
    "fedramp_package" => "FedRAMP package overview:",
    "fedramp_contacts" => "FedRAMP contacts:",
    "fedramp_overview_from_sparc" => "SPARC's own overview endpoint"
  }.freeze

  class_methods do
    def human_attribute_name(attribute, options = {})
      HUMAN_NAMES[attribute.to_s] || super
    end

    # The values the vendored schema allows for an :enum / :enum_list field.
    def fedramp_choices(key)
      section, property, = FIELDS.fetch(key)
      schema = FedrampPackageSchemas.fetch(DOCUMENT_TYPE).document.dig("properties", section, "properties", property)
      Array(schema["enum"] || schema.dig("items", "enum"))
    end

    def fedramp_logo_format
      @fedramp_logo_format ||= anchored(common_definition("logoUri")["pattern"])
    end

    def fedramp_phone_format
      @fedramp_phone_format ||= anchored(FedrampPackageSchemas.fetch(DOCUMENT_TYPE).document
                                           .dig("$defs", "contactInfo", "properties", "contactPhone", "pattern"))
    end

    # SPARC_APP_URL as an https base (scheme, host, port, path), or nil. Only
    # the operator's setting, never a request's Host header.
    def sparc_https_base_url
      raw = ENV.fetch("SPARC_APP_URL", "").strip
      uri = URI.parse(raw)
      return nil unless uri.is_a?(URI::HTTPS) && uri.host.present?

      port = uri.port == uri.default_port ? "" : ":#{uri.port}"
      "https://#{uri.host}#{port}#{uri.path.chomp('/')}"
    rescue URI::InvalidURIError
      nil
    end

    private

    def common_definition(name)
      FedrampPackageSchemas.fetch(FedrampPackageSchemas::COMMON).document.dig("$defs", name)
    end

    # The schemas' patterns are ECMA-262, where ^ and $ anchor the whole
    # string; in Ruby they anchor a line.
    def anchored(pattern)
      Regexp.new(pattern.sub(/\A\^/, "\\A").sub(/\$\z/, "\\z"))
    end
  end

  included do
    validate :fedramp_package_is_valid, if: :fedramp_package_changed?
    validates :fedramp_active_agencies, length: { maximum: 500, message: "may list at most 500 agencies" }
    validate :fedramp_profile_is_offered, if: -> { fedramp_package_changed? || fedramp_enabled_changed? }
    validate :fedramp_contacts_are_valid, if: :fedramp_contacts_changed?
    validate :fedramp_overview_from_sparc_is_usable, if: -> { fedramp_overview_from_sparc_changed? && fedramp_overview_from_sparc? }
  end

  def fedramp_package=(attrs)
    attrs = attrs.to_unsafe_h if attrs.respond_to?(:to_unsafe_h)
    merged = (self[:fedramp_package] || {}).dup
    (attrs || {}).each do |key, value|
      key = key.to_s
      next unless PACKAGE_KEYS.include?(key)

      value = normalize_fedramp_value(key, value)
      if value.nil?
        merged.delete(key)
      else
        merged[key] = value
      end
    end
    super(merged)
  end

  # #1390 — the agencies directly using the service (the Ongoing
  # Certification Report's activeAgencies): a list, or text one per line.
  def fedramp_active_agencies=(value)
    list = value.is_a?(String) ? value.lines : Array(value)
    super(list.map { |v| v.to_s.strip }.compact_blank.uniq)
  end

  # Accepts an array of hashes, or the index-keyed hash a form posts.
  def fedramp_contacts=(rows)
    super(FormRows.normalize(rows, CONTACT_KEYS))
  end

  def fedramp_value(key) = (fedramp_package || {})[key.to_s]

  # [type, path, class], each nil until recorded.
  def fedramp_profile = %w[certification_type certification_path certification_class].map { |k| fedramp_value(k) }

  def fedramp_profile_complete? = fedramp_profile.all?(&:present?)

  # The FedRAMP rules that apply to this boundary's profile; none until it is
  # complete.
  def fedramp_applicable_rules
    type, path, klass = fedramp_profile
    FedrampRules.applicable(type: type, path: path, klass: klass)
  end

  # The address FedRAMP's reports name, or nil when there is none.
  def fedramp_overview_address
    return fedramp_package_overview_uri.to_s.strip.presence unless fedramp_overview_from_sparc?

    base = self.class.sparc_https_base_url
    base && "#{base}#{format(OVERVIEW_PATH, uuid)}"
  end

  # What the overview still needs before SPARC can write it, by label.
  def fedramp_overview_missing
    missing = FIELDS.select { |key, (*, required, _)| required && fedramp_value(key).blank? }.map { |_, f| f[2] }
    types = Array(fedramp_contacts).map { |c| c["contact_type"] }
    missing + (REQUIRED_CONTACT_TYPES - types).map { |t| "a #{t} contact" }
  end

  def fedramp_overview_ready? = fedramp_overview_missing.empty?

  # The FedRAMP Certification Package Overview document (unvalidated; the
  # writer validates it). Fields not recorded are omitted, never empty.
  def fedramp_overview_document
    doc = { "$schema" => FedrampPackageSchemas.fetch(DOCUMENT_TYPE).id,
            "serviceIdentification" => {}, "serviceProperties" => {} }
    FIELDS.each do |key, (section, property, *)|
      value = fedramp_value(key)
      doc[section][property] = value if value.present?
    end
    trust_center = fedramp_trust_center
    doc["serviceProperties"]["trustCenter"] = trust_center if trust_center
    doc["contactInformation"] = Array(fedramp_contacts).map do |c|
      { "contactType" => c["contact_type"], "contactName" => c["name"],
        "contactEmail" => c["email"], "contactPhone" => c["phone"] }.compact
    end
    doc
  end

  private

  def fedramp_trust_center
    url = fedramp_value("trust_center_url")
    return nil if url.blank?

    auth = fedramp_value("trust_center_authentication_required") == true
    { "repositoryType" => [ "Trust Center" ], "url" => url,
      "repositoryDescription" => fedramp_value("trust_center_description"),
      "authenticationRequired" => auth,
      "accessRequestInstructions" => fedramp_value("trust_center_access_instructions") }.compact
  end

  def normalize_fedramp_value(key, value)
    if key == "trust_center_authentication_required"
      return ActiveModel::Type::Boolean.new.cast(value.presence)
    end

    kind = FIELDS.dig(key, 4)
    return Array(value).map { |v| v.to_s.strip }.compact_blank.uniq.presence if kind == :enum_list

    value.to_s.strip.presence
  end

  def fedramp_package_is_valid
    pkg = fedramp_package || {}
    FIELDS.each do |key, (_, _, label, _, kind)|
      value = pkg[key]
      next if value.blank?

      error = fedramp_field_error(key, kind, value)
      errors.add(:fedramp_package, "#{label} #{error}") if error
    end
    validate_fedramp_trust_center(pkg)
  end

  def fedramp_field_error(key, kind, value)
    case kind
    when :enum
      "must be one of: #{self.class.fedramp_choices(key).join(', ')}" unless self.class.fedramp_choices(key).include?(value)
    when :enum_list
      unknown = Array(value) - self.class.fedramp_choices(key)
      return "has unknown values: #{unknown.join(', ')}" if unknown.any?

      "may list at most #{BUSINESS_CATEGORY_MAX}" if key == "business_categories" && value.size > BUSINESS_CATEGORY_MAX
    when :url
      "must be an http(s) address" unless value.match?(URL_FORMAT)
    when :logo
      unless value.match?(URL_FORMAT) && value.match?(self.class.fedramp_logo_format)
        "must be an http(s) address of a PNG, JPEG, GIF, SVG, WebP, ICO, BMP or TIFF image"
      end
    when :date
      "must be a date in the form YYYY-MM-DD" unless SparcNamespaceProps.iso_date(value)
    else nil # free text: any value is accepted
    end
  end

  def validate_fedramp_trust_center(pkg)
    url = pkg["trust_center_url"]
    if url.blank?
      others = TRUST_CENTER_KEYS.drop(1).any? { |k| !pkg[k].nil? && pkg[k] != false }
      errors.add(:fedramp_package, "Trust center address is needed for the other trust center fields") if others
      return
    end
    errors.add(:fedramp_package, "Trust center address must be an http(s) address") unless url.match?(URL_FORMAT)
    errors.add(:fedramp_package, "Trust center description can't be blank") if pkg["trust_center_description"].blank?
    if pkg["trust_center_authentication_required"] == true && pkg["trust_center_access_instructions"].blank?
      errors.add(:fedramp_package, "Trust center access instructions are needed when it requires sign-in")
    end
  end

  # FedRAMP offers Class A only as a 20x Program certification, the Agency
  # path only for Rev5, and Rev5 in Classes B–D (FRC-CLA, FRC-APS, FRC-CSF).
  def fedramp_profile_is_offered
    type, path, klass = fedramp_profile
    choices = FedrampRules.profile_choices
    { "Certification path" => [ path, choices[:paths] ], "Certification class" => [ klass, choices[:classes] ] }
      .each do |label, (value, allowed)|
        errors.add(:fedramp_package, "#{label} must be one of: #{allowed.join(', ')}") if value.present? && !allowed.include?(value)
      end
    return if errors.any?

    errors.add(:fedramp_package, "Class A is offered only as a 20x Program certification") if klass == "A" && (type == "Rev5" || path == "Agency")
    errors.add(:fedramp_package, "The Agency path is offered only for Rev5") if path == "Agency" && type == "20x"
  end

  def fedramp_contacts_are_valid
    list = Array(fedramp_contacts)
    errors.add(:fedramp_contacts, "may list at most #{MAX_CONTACTS}") if list.size > MAX_CONTACTS
    list.each_with_index do |c, i|
      row = "contact #{i + 1}"
      errors.add(:fedramp_contacts, "#{row}: type must be one of #{CONTACT_TYPES.join(', ')}") unless CONTACT_TYPES.include?(c["contact_type"])
      errors.add(:fedramp_contacts, "#{row}: email is not an email address") if c["email"].present? && !c["email"].match?(EMAIL_FORMAT)
      if c["phone"].present? && !c["phone"].match?(self.class.fedramp_phone_format)
        errors.add(:fedramp_contacts, "#{row}: phone must be a US number, e.g. 202-555-0123")
      end
    end
  end

  def fedramp_overview_from_sparc_is_usable
    return if self.class.sparc_https_base_url

    errors.add(:fedramp_overview_from_sparc, "needs SPARC_APP_URL to be an https:// address")
  end
end
