# frozen_string_literal: true

require "stringio"

# #1179 — mint an HDF `hdf-system` document (schema v3.7.0) for an
# authorization boundary.
#
# hdf-system is the document every other HDF v3 document points at through
# `systemRef` — results, amendments, evidence packages. It states what the
# boundary IS: its identity, owner, categorization, authorization, components
# and control designations. Those are authorization facts and SPARC holds them,
# so SPARC is the writer (risk-sentinel/sparc-validate#441); the evidence
# pipeline consumes this document rather than deriving one from what it scanned.
#
# DETERMINISTIC. No generation timestamp, stable key and array order, so the
# same boundary state exports byte-identically. That is what lets the API hand
# out a strong ETag computed over the bytes themselves.
#
# VALIDATED TWICE, for different reasons:
#   * always, in process, against the vendored schema (Hdf::SystemSchema) —
#     the same bytes the CLI embeds, and the only check that runs on the CI
#     test runner, which has no hdf binary (#835);
#   * with `hdf validate --type system` whenever the binary is present, which
#     it is in the shipped image. The CLI is the authority downstream
#     consumers will run, so its verdict is the one that matters.
#
# WHAT IS NOT EXPORTED, deliberately:
#   * dataFlows — SPARC does not model interconnections between components.
#     Emitting an empty or guessed list would state something untrue.
#   * controlDesignations[].providedBy / inheritedBy / systemRef — the SSP
#     records the ORIGINATION of a control, not which component or which
#     leveraged system provides it.
#
# NIST 800-53: CA-3 (boundary and component inventory), CM-8 (system component
# inventory), PL-2 (system security plan facts), RA-2 (FIPS 199 categorization),
# CA-6 (authorization status and date), AU-10 (deterministic, content-addressed
# export).
class HdfSystemExportService
  SCHEMA_VERSION = Hdf::SystemSchema::VERSION
  GENERATOR_NAME = "sparc"

  # D4 (owner-decided): the boundary uuid IS the system identifier, and it is
  # an RFC 4122 uuid, so the scheme names RFC 4122 rather than a SPARC URL.
  IDENTIFIER_SCHEME = "urn:ietf:rfc:4122"

  # D3 (owner-decided). A SPARC status that has no row here is not exported
  # rather than guessed; the four enum values all have one.
  AUTHORIZATION_STATUS = {
    "authorized"   => "authorized",
    "deauthorized" => "revoked",
    "draft"        => "notYetRequested",
    "active"       => "pendingAuthorization"
  }.freeze

  # OSCAL defined-component type -> HDF component type.
  #
  # HDF components are the TECHNICAL things inside a boundary that evidence can
  # be about — hosts, applications, networks. OSCAL component types also cover
  # documentation (policy, plan, guidance, standard, process-procedure), a
  # validation certificate, and physical protections. None of those is an asset
  # a scan result or a waiver can be scoped to, and HDF has no type that means
  # them, so they are EXCLUDED rather than mislabelled as `application`.
  #
  # `interconnection` is excluded for a different reason: in HDF a connection
  # between systems is a data flow, not a component, and SPARC does not model
  # data flows (see above). Calling it a `network` would claim a network
  # segment inside the boundary that nobody declared.
  #
  # A blank type maps like `software`, because that is what the OSCAL CDEF
  # export already writes for a blank type (OscalComponentDefinitionExportService),
  # and the two exports must not disagree about the same component.
  COMPONENT_TYPES = {
    "software" => "application",
    "service"  => "application",
    "hardware" => "host"
  }.freeze
  BLANK_COMPONENT_TYPE = "software"

  # SSP `control_type` (the control's origination) -> HDF designation.
  # "Not Applicable" is a status, not an origination, and has no designation.
  DESIGNATIONS = {
    "system specific"              => "system-specific",
    "hybrid — partially inherited" => "hybrid",
    "inherited from provider"      => "common"
  }.freeze

  # hdf requires a description on every designation. When the SSP holds no
  # implementation narrative for the control, the designation is still a real,
  # recorded fact — so it is exported, with a description that says exactly
  # where it came from and that no narrative exists, rather than dropped or
  # given invented prose.
  NO_NARRATIVE = "Designation recorded in the SPARC SSP as \"%<origination>s\". " \
                 "No implementation statement has been written for this control."

  # Raised when the document cannot be minted from what the boundary holds.
  # 422: the boundary's data is what has to change, and the message says what.
  class Unexportable < StandardError; end

  # Raised when the minted document fails schema validation. That is SPARC's
  # defect, not the caller's, and it is never returned as a document.
  class InvalidDocument < StandardError
    attr_reader :errors

    def initialize(errors)
      @errors = errors
      super("The generated hdf-system document is not valid against hdf-system v#{SCHEMA_VERSION}: " \
            "#{errors.first(5).join('; ')}")
    end
  end

  attr_reader :excluded_components

  def initialize(boundary, runner: HdfRunner.new, cli: nil)
    @boundary = boundary
    @runner = runner
    @cli = cli
    @excluded_components = []
  end

  # Is the hdf binary on this host? Resolved from HDF_BIN (a path or a name)
  # the same way HdfRunner resolves it.
  def self.cli_available?
    binary = ENV.fetch("HDF_BIN", HdfRunner::DEFAULT_BINARY)
    return File.executable?(binary) if binary.include?(File::SEPARATOR)

    ENV["PATH"].to_s.split(File::PATH_SEPARATOR).any? { |dir| File.executable?(File.join(dir, binary)) }
  end

  # URL of a boundary's hdf-system document — the value other HDF documents
  # carry as `systemRef`. Keyed on the uuid, not the slug: a slug is
  # regenerated when the boundary is renamed, and a reference that moves on
  # rename is not a reference.
  def self.system_ref(boundary)
    path = Rails.application.routes.url_helpers
                .api_v1_authorization_boundary_hdf_system_path(boundary.uuid)
    "#{SparcConfig.app_url.chomp('/')}#{path}"
  end

  # @return [Hash] a validated hdf-system document
  def export
    doc = build
    errors = Hdf::SystemSchema.errors(doc)
    raise InvalidDocument, errors if errors.any?

    validate_with_cli!(doc) if cli?
    doc
  end

  # The document, unvalidated. Public so the validator specs can corrupt a real
  # document and prove it is rejected.
  def build
    components = build_components
    if components.empty?
      raise Unexportable, empty_components_message
    end

    doc = {
      "name"                => @boundary.name,
      "systemId"            => @boundary.uuid,
      "identifier"          => @boundary.uuid,
      "identifierScheme"    => IDENTIFIER_SCHEME,
      "description"         => @boundary.description.presence,
      "boundaryDescription" => @boundary.authorization_boundary_description.presence,
      "owner"               => owner,
      "authorizationStatus" => AUTHORIZATION_STATUS[@boundary.status.to_s],
      "authorizationDate"   => authorization_date,
      "categorizationLevel" => categorization_level,
      "components"          => components,
      "controlDesignations" => control_designations.presence,
      "generator"           => { "name" => GENERATOR_NAME, "version" => SparcConfig.version },
      "labels"              => { "system_id" => @boundary.uuid }
    }
    doc.compact
  end

  private

  def cli?
    @cli.nil? ? self.class.cli_available? : @cli
  end

  # StringIO, not a String: HdfRunner treats a String as a PATH (#1037).
  def validate_with_cli!(doc)
    @runner.validate(StringIO.new(JSON.generate(doc)), type: "system")
  end

  # ── owner ────────────────────────────────────────────────────────────────
  #
  # The system owner on the ROSTER, from either assignment path (legacy
  # memberships, then admin-assigned user_roles — the same two paths
  # AuthorizationBoundary#staffed_roles reads). Only an email is exported as a
  # person's identity: it is the one identifier SPARC holds that means the same
  # thing outside SPARC. With no such person, the owning organization; with
  # neither, no owner at all — the field is optional and a guess is worse.
  def owner
    email = system_owner_email
    return { "identifier" => email, "type" => "email" } if email

    org = @boundary.organization
    return nil unless org

    { "identifier" => org.uuid, "type" => "other", "description" => "SPARC organization: #{org.name}" }
  end

  def system_owner_email
    legacy = @boundary.authorization_boundary_memberships
                      .where(role: "system_owner").order(:id).includes(:user)
                      .filter_map { |m| m.user_email.presence || m.user&.email.presence }
                      .first
    return legacy if legacy

    @boundary.user_roles.joins(:role).where(roles: { name: "system_owner" })
             .order(:id).includes(:user)
             .filter_map { |ur| ur.user&.email.presence }
             .first
  end

  # ── authorization + categorization ───────────────────────────────────────

  # Only a value that parses as ISO 8601. A free-text date would have to be
  # guessed at, and `Date.parse` guesses — "May" parses. Strict ISO or nothing.
  def authorization_date
    raw = (@boundary.boundary_metadata || {})["authorization_date"].to_s.strip
    return nil if raw.empty?

    begin
      Time.iso8601(raw).utc.iso8601
    rescue ArgumentError
      begin
        Date.iso8601(raw).to_time(:utc).iso8601
      rescue ArgumentError, Date::Error
        nil
      end
    end
  end

  # FIPS 199 high-water mark, stored as `fips-199-<level>`.
  def categorization_level
    level = @boundary.security_categorization.to_s.delete_prefix("fips-199-")
    %w[low moderate high].include?(level) ? level : nil
  end

  # ── components ───────────────────────────────────────────────────────────
  #
  # One HDF component per OSCAL defined-component of every CDEF linked to the
  # boundary (through its environments).
  #
  # A CDEF that was imported from OSCAL has its components indexed in
  # `cdef_components`, carrying the upstream component uuids — those are the
  # identities, so they are used. A CDEF with no index (hand-authored, XCCDF,
  # or an index that failed) has exactly one component, the one the OSCAL CDEF
  # export writes from the document's own `component_*` columns, and it gets
  # the same derived uuid that export gives it: one component, one identity,
  # whichever format it is read in.
  #
  # A component that carries an automated check of its own (an AWS Config Rule
  # is modelled as a `software` component) is an assessment PROCEDURE, not an
  # asset in the boundary, and is excluded with the non-technical types.
  def build_components
    seen = {}
    cdef_documents.each do |doc|
      candidates_for(doc).each do |candidate|
        hdf_type = hdf_type_for(candidate[:oscal_type], check: candidate[:check])
        if hdf_type.nil?
          @excluded_components << candidate.slice(:name, :oscal_type).merge(cdef: doc.name)
          next
        end
        next if seen.key?(candidate[:id])

        seen[candidate[:id]] = {
          "type"        => hdf_type,
          "name"        => candidate[:name],
          "componentId" => candidate[:id],
          "description" => candidate[:description].presence
        }.compact
      end
    end
    seen.values
  end

  def cdef_documents
    CdefDocument.where(id: @boundary.cdef_documents.select(:id)).order(:id).includes(:cdef_components)
  end

  def candidates_for(doc)
    indexed = doc.cdef_components.sort_by { |c| [ c.title.to_s, c.component_uuid.to_s ] }
    return [ document_candidate(doc) ] if indexed.empty?

    indexed.map do |c|
      {
        id: indexed_component_id(doc, c.component_uuid),
        name: c.title.presence || doc.name,
        oscal_type: c.component_type.to_s,
        description: c.description,
        check: c.has_checks && c.component_type != "service"
      }
    end
  end

  def document_candidate(doc)
    {
      id: OscalUuidService.derived(doc.uuid, "cdef-component"),
      name: doc.component_title.presence || doc.name,
      oscal_type: doc.component_type.to_s,
      description: doc.component_description.presence || doc.description,
      check: false
    }
  end

  # Same rule as the OSCAL CDEF export: keep an upstream uuid when it is one,
  # derive a stable one when the source supplied something else.
  def indexed_component_id(doc, uuid)
    return uuid if OscalComponentDefinitionExportService::OSCAL_UUID.match?(uuid.to_s)

    OscalUuidService.derived(doc.uuid, "cdef-component-#{uuid}")
  end

  def hdf_type_for(oscal_type, check:)
    return nil if check

    COMPONENT_TYPES[oscal_type.presence || BLANK_COMPONENT_TYPE]
  end

  def empty_components_message
    if @excluded_components.empty?
      "Authorization boundary \"#{@boundary.name}\" has no components. An hdf-system document " \
        "must list at least one — link a component definition (CDEF) to one of the boundary's " \
        "environments, then export again."
    else
      types = @excluded_components.map { |c| c[:oscal_type].presence || "(blank)" }.uniq.sort
      "Authorization boundary \"#{@boundary.name}\" has #{@excluded_components.size} linked " \
        "component(s), and none is a technical component an hdf-system document can list " \
        "(types found: #{types.join(', ')}; automated-check components are also excluded). " \
        "Link a CDEF describing software, a service or hardware, then export again."
    end
  end

  # ── control designations ─────────────────────────────────────────────────
  #
  # From the boundary's SSP: every control whose `control_type` (origination)
  # maps to an HDF designation. The description is the control's own
  # implementation narrative — the statement, then the summary — and when it
  # has neither, NO_NARRATIVE says so plainly.
  def control_designations
    ssp = @boundary.ssp_document
    return [] unless ssp

    seen = {}
    ssp.ssp_controls.includes(:ssp_control_fields).order(:row_order, :id).each do |control|
      fields = control.ssp_control_fields.index_by(&:field_name)
      origination = fields["control_type"]&.field_value.to_s.strip
      designation = DESIGNATIONS[origination.downcase]
      next unless designation

      control_id = ControlId.human(control.control_id)
      next if control.control_id.blank? || seen.key?(control_id)

      seen[control_id] = {
        "controlId"   => control_id,
        "designation" => designation,
        "description" => narrative(fields) || format(NO_NARRATIVE, origination: origination)
      }
    end
    seen.values
  end

  def narrative(fields)
    %w[implementation_statement implementation_summary].each do |name|
      text = fields[name]&.field_value.to_s.strip
      return text if text.present?
    end
    nil
  end
end
