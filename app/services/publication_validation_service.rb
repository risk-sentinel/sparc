# Validates that a document's OSCAL metadata is complete enough for publication.
#
# Required metadata for publication:
#   1. At least one role defined (creator or prepared-by)
#   2. At least one party defined (contact/organization)
#   3. At least one responsible-party linking a role to a party
#
# Can auto-populate defaults from the current user's profile and organization.
class PublicationValidationService
  # OSCAL metadata keys reused across the validation checks.
  RESPONSIBLE_PARTIES = "responsible-parties".freeze
  PREPARED_BY         = "prepared-by".freeze

  Result = Struct.new(:valid?, :errors, :missing_fields, keyword_init: true)

  CREATOR_ROLE_IDS = %w[creator prepared-by].freeze

  def initialize(document, current_user: nil)
    @document = document
    @current_user = current_user
  end

  # Validate metadata completeness for publication.
  # Returns a Result with valid?, errors[], and missing_fields[].
  def validate
    errors = []
    missing = []

    unless has_creator_role?
      errors << "A creator or prepared-by role is required"
      missing << :creator_role
    end

    unless has_contact_party?
      errors << "At least one party (contact/organization) is required"
      missing << :contact_party
    end

    unless has_responsible_parties?
      errors << "At least one responsible-party linking a role to a party is required"
      missing << :responsible_parties
    end

    Result.new(valid?: errors.empty?, errors: errors, missing_fields: missing)
  end

  # Returns a hash describing publication readiness for the smart modal.
  def publication_readiness
    result = validate
    {
      ready: result.valid?,
      errors: result.errors,
      missing_fields: result.missing_fields,
      checks: {
        creator_role: has_creator_role?,
        contact_party: has_contact_party?,
        responsible_parties: has_responsible_parties?,
        title: @document.name.present?,
        version: version_present?,
        oscal_version: (@document.oscal_version || OscalMetadata::OSCAL_VERSION).present?
      },
      defaults: build_defaults_from_user,
      current_metadata: {
        roles: metadata["roles"] || [],
        parties: metadata["parties"] || [],
        responsible_parties: metadata[RESPONSIBLE_PARTIES] || []
      }
    }
  end

  # Auto-populate metadata_extra with defaults from current_user and their org.
  # Merges into existing metadata — does NOT overwrite existing entries.
  def auto_populate_defaults!
    return unless @current_user

    extra = @document.metadata_extra || {}
    roles = extra["roles"] || []
    parties = extra["parties"] || []
    resp_parties = extra[RESPONSIBLE_PARTIES] || []

    # Add creator role if missing
    unless roles.any? { |r| CREATOR_ROLE_IDS.include?(r["id"]) }
      roles << { "id" => PREPARED_BY, "title" => "Prepared By" }
    end

    # Add contact party if no parties exist
    if parties.empty?
      party = build_party_from_user
      parties << party if party
    end

    # Add responsible-party if missing
    if resp_parties.empty? && parties.any?
      resp_parties << {
        "role-id" => PREPARED_BY,
        "party-uuids" => [ parties.first["uuid"] ]
      }
    end

    @document.metadata_extra = extra.merge(
      "roles" => roles,
      "parties" => parties,
      RESPONSIBLE_PARTIES => resp_parties
    )
  end

  private

  def metadata
    @document.metadata_extra || {}
  end

  def has_creator_role?
    roles = metadata["roles"] || []
    roles.any? { |r| CREATOR_ROLE_IDS.include?(r["id"]) }
  end

  def has_contact_party?
    parties = metadata["parties"] || []
    parties.any? { |p| p["name"].present? || p["uuid"].present? }
  end

  def has_responsible_parties?
    resp = metadata[RESPONSIBLE_PARTIES] || []
    resp.any? { |rp| rp["role-id"].present? && rp["party-uuids"].present? }
  end

  def version_present?
    @document.respond_to?(:oscal_document_version) && @document.oscal_document_version.present?
  end

  def build_defaults_from_user
    return {} unless @current_user

    org = @current_user.respond_to?(:organizations) ? @current_user.organizations.first : nil

    defaults = {
      creator_name: @current_user.display_name.presence || "#{@current_user.first_name} #{@current_user.last_name}".strip,
      creator_email: @current_user.email
    }

    if org
      defaults[:org_name] = org.name
      defaults[:org_email] = org.contact_email
      defaults[:party_type] = "organization"
    else
      defaults[:party_type] = "person"
    end

    defaults
  end

  def build_party_from_user
    return nil unless @current_user

    org = @current_user.respond_to?(:organizations) ? @current_user.organizations.first : nil

    if org
      party = {
        "uuid" => SecureRandom.uuid,
        "type" => "organization",
        "name" => org.name
      }
      party["email-addresses"] = [ org.contact_email ] if org.contact_email.present?
      party
    else
      party = {
        "uuid" => SecureRandom.uuid,
        "type" => "person",
        "name" => @current_user.display_name.presence || "#{@current_user.first_name} #{@current_user.last_name}".strip
      }
      party["email-addresses"] = [ @current_user.email ] if @current_user.email.present?
      party
    end
  end
end
