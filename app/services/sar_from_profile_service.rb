# Creates a SarDocument with controls and fields from a published
# ProfileDocument's resolved_catalog_json.  Each control in the resolved
# catalog becomes a SarControl with pre-populated read-only fields
# (stated_requirement, description) and empty editable placeholder fields
# (result, working_status, notes_weakness, etc.).
#
# A default SarResult and SarFinding per control are scaffolded so the
# SAR is enrichment-ready.
#
# Usage:
#   service = SarFromProfileService.new(profile_document, name: "My SAR")
#   sar = service.create
#
class SarFromProfileService
  include BatchInsertable

  def initialize(profile_document, name: nil, authorization_boundary: nil)
    @profile = profile_document
    # #952 — see SspFromProfileService: a profile belongs to no system.
    @boundary = authorization_boundary
    @name    = name.presence || "SAR from #{profile_document.name}"
  end

  def create
    validate!

    catalog  = @profile.resolved_catalog_json
    metadata = catalog.dig("catalog", "metadata") || {}

    @document = SarDocument.create!(
      name:                @name,
      creation_method:     "profile",
      file_type:           "json",
      status:              "completed",
      lifecycle_status:    "started",
      oscal_version:       metadata["oscal-version"] || "1.1.2",
      description:         "Assessment results for #{@profile.name}",
      profile_document_id: @profile.id,
      authorization_boundary: @boundary,
      import_metadata:     {
        "source_type"         => "profile",
        "source_profile_id"   => @profile.id,
        "source_profile_uuid" => @profile.uuid,
        "source_profile_name" => @profile.name,
        "format"              => "resolved_catalog"
      }
    )

    build_controls_from_catalog(catalog)
    create_default_result
    # No findings: a baseline makes no claim about any system, so nothing is
    # known before the assessment. Every control used to be recorded
    # not-satisfied. An assessor's determinations become findings
    # (SarObjectiveDetermination).
    ControlObjectiveExtractorService.backfill_generated!(@document)

    @document
  end

  private

  def validate!
    raise ArgumentError, "Profile must be published" unless @profile.lifecycle_status == "published"
    raise ArgumentError, "Profile must have a resolved catalog" if @profile.resolved_catalog_json.blank?
  end

  def build_controls_from_catalog(catalog)
    control_attrs = []
    field_entries = []
    row_order = 0

    ResolvedCatalog.wrap(catalog).each_control do |control, _group|
      idx = control_attrs.size

      control_attrs << {
        control_id: control["id"],
        title:      control["title"],
        row_order:  row_order
      }

      # Pre-populated read-only fields. The WHOLE requirement, items included
      # (ControlRequirementText): a statement's own prose is empty for every
      # NIST control written as lettered items.
      statement = requirement_text(catalog)[ControlId.canonical(control["id"])]&.full.presence ||
                  extract_part_prose(control, "statement")
      guidance  = extract_part_prose(control, "guidance")

      field_entries << [ idx, "stated_requirement", statement ] if statement.present?
      field_entries << [ idx, "description", guidance ]         if guidance.present?

      # Editable placeholder fields for assessment
      field_entries << [ idx, "result", "" ]
      field_entries << [ idx, "working_status", "" ]
      field_entries << [ idx, "notes_weakness", "" ]
      field_entries << [ idx, "recommended_fix", "" ]
      field_entries << [ idx, "working_comments", "" ]
      field_entries << [ idx, "date", "" ]

      row_order += 1
    end

    # #957 — derived, not minted (see BatchInsertable).
    batch_insert_records(
      control_class: SarControl,
      field_class:   SarControlField,
      document_fk:   :sar_document_id,
      control_attrs: control_attrs,
      field_entries: field_entries,
      uuid_for:       ->(attrs) {
        OscalUuidService.derived(@document.uuid, "sar-control", attrs[:control_id].to_s)
      }
    )
  end

  # ── Default result ──────────────────────────────────────────────

  def create_default_result
    @result = @document.sar_results.create!(
      # #957 — derived from the document, not minted.
      uuid:        OscalUuidService.derived(@document.uuid, "sar-result", "default"),
      title:       "Assessment Results for #{@document.name}",
      description: "Assessment results generated from profile #{@profile.name}.",
      start_time:  Time.current,
      position:    0
    )
  end

  # ── Helpers ──────────────────────────────────────────────────────

  def requirement_text(catalog)
    @requirement_text ||= begin
      ids = []
      ResolvedCatalog.wrap(catalog).each_control { |control, _group| ids << control["id"] }
      ControlRequirementText.for_profile(@profile).for_controls(ids)
    end
  end

  def extract_part_prose(control, part_name)
    parts = control["parts"]
    return nil unless parts.is_a?(Array)

    part = parts.find { |p| p["name"] == part_name }
    part&.dig("prose")
  end

  # #852 — delegated to the one canonical implementation. This was one of
  # several byte-identical private copies; ControlId.canonical reproduces them
  # exactly (including the OSCAL TokenDatatype conversion of "AC-2 (1)" to
  # "ac-2.1") and additionally removes zero padding, so "AC-02" and "ac-2"
  # finally name the same control.
  def normalize_control_id(raw_id)
    ControlId.canonical(raw_id)
  end
end
