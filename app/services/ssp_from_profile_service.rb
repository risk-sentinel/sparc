# Creates an SspDocument with controls and fields from a published
# ProfileDocument's resolved_catalog_json.  Each control in the resolved
# catalog becomes an SspControl with pre-populated read-only fields
# (stated_requirement, description) and empty editable placeholder fields
# (status, control_type, responsible_entities, etc.).
#
# A "this-system" SspComponent, a default SspInformationType, and a
# default SspUser are scaffolded so the SSP is enrichment-ready.
#
# Usage:
#   service = SspFromProfileService.new(profile_document, name: "My SSP")
#   ssp = service.create
#
class SspFromProfileService
  include BatchInsertable

  PRIORITY_TO_SEVERITY = {
    "P1" => "high",
    "P2" => "medium",
    "P3" => "low"
  }.freeze

  def initialize(profile_document, name: nil, authorization_boundary: nil)
    @profile = profile_document
    # #952 — a profile is a baseline and belongs to no system, so the boundary
    # has to be supplied by the caller. Without it the SSP cannot be saved.
    @boundary = authorization_boundary
    @name    = name.presence || "SSP from #{profile_document.name}"
  end

  def create
    validate!

    @document = SspDocument.create!(
      name:                @name,
      creation_method:     "profile",
      file_type:           "json",
      status:              "completed",
      lifecycle_status:    "started",
      oscal_version:       metadata["oscal-version"] || "1.1.2",
      description:         metadata["title"],
      profile_document_id: @profile.id,
      authorization_boundary: @boundary,
      import_metadata:     profile_import_metadata
    )

    @this_system = create_this_system_component
    create_default_information_type
    create_default_user

    imported_ids = build_controls_from_catalog(catalog)
    create_by_component_records(imported_ids)

    @document
  end

  # #628 — populate an EXISTING empty SSP from a published profile, giving a
  # metadata-only shell a control basis instead of a dead end. Preserves the
  # user's name/description; only fills blanks, scaffolds missing OSCAL
  # entities, links the profile, and imports controls.
  def populate(document)
    validate!
    raise ArgumentError, "SSP already has controls" if document.ssp_controls.exists?

    @document = document
    ActiveRecord::Base.transaction do
      document.update!(profile_link_attrs(document))
      @this_system = document.ssp_components.find_by(component_type: "this-system") ||
                     create_this_system_component
      create_default_information_type unless document.ssp_information_types.exists?
      create_default_user unless document.ssp_users.exists?

      imported_ids = build_controls_from_catalog(catalog)
      create_by_component_records(imported_ids)
    end

    @document
  end

  private

  def validate!
    raise ArgumentError, "Profile must be published" unless @profile.lifecycle_status == "published"
    raise ArgumentError, "Profile must have a resolved catalog" if @profile.resolved_catalog_json.blank?
  end

  def catalog
    @catalog ||= @profile.resolved_catalog_json
  end

  def metadata
    @metadata ||= catalog.dig("catalog", "metadata") || {}
  end

  def profile_import_metadata
    {
      "source_type"         => "profile",
      "source_profile_id"   => @profile.id,
      "source_profile_uuid" => @profile.uuid,
      "source_profile_name" => @profile.name,
      "format"              => "resolved_catalog"
    }
  end

  # Attributes applied when linking a profile to an existing SSP. Fills
  # description/oscal_version/creation_method only when blank so a user's
  # edits survive.
  def profile_link_attrs(document)
    attrs = {
      profile_document_id: @profile.id,
      import_metadata:     profile_import_metadata
    }
    attrs[:creation_method] = "profile" if document.creation_method.blank?
    attrs[:description]      = metadata["title"] if document.description.blank?
    attrs[:oscal_version]    = (metadata["oscal-version"] || "1.1.2") if document.oscal_version.blank?
    attrs
  end

  # #957 — these are singletons of the generated SSP, so their identity is
  # seeded from the document plus what they are, not from randomness.
  def create_this_system_component
    @document.ssp_components.create!(
      uuid:           OscalUuidService.derived(@document.uuid, "ssp-component", "this-system"),
      component_type: "this-system",
      title:          @document.name,
      description:    "This system — #{@document.name}",
      status_state:   "under-development"
    )
  end

  def create_default_information_type
    @document.ssp_information_types.create!(
      uuid:        OscalUuidService.derived(@document.uuid, "ssp-information-type", "general"),
      title:       "General Information",
      description: "Default information type — update via enrichment."
    )
  end

  def create_default_user
    @document.ssp_users.create!(
      uuid:        OscalUuidService.derived(@document.uuid, "ssp-user", "system-administrator"),
      title:       "System Administrator",
      description: "Default administrative user — update via enrichment."
    )
  end

  def build_controls_from_catalog(catalog)
    control_attrs = []
    field_entries = []
    statement_entries = []
    row_order = 0

    ResolvedCatalog.wrap(catalog).each_control do |control, _group|
      idx = control_attrs.size

      control_attrs << {
        control_id: control["id"],
        title:      control["title"],
        row_order:  row_order
      }

      # Pre-populated read-only fields
      statement = extract_part_prose(control, "statement")
      guidance  = extract_part_prose(control, "guidance")

      field_entries << [ idx, "stated_requirement", statement ] if statement.present?
      field_entries << [ idx, "description", guidance ]         if guidance.present?

      # #1100 — ONE ENTRY PER STATEMENT PART, not one per control.
      #
      # This used to push a single `<control-id>_smt`, so a control NIST divides
      # into nine addressable statements got exactly one row, and an SSP author
      # had one box in which to answer all of them. OSCAL models this the other
      # way round: `statements` is an array whose members identify WHICH
      # statements within a control are addressed.
      statement_parts_for(control).each do |part_id, parent_part_id, label, order|
        statement_entries << [ idx, part_id, parent_part_id, label, order ]
      end

      # Editable placeholder fields
      field_entries << [ idx, "status", "Deferred" ]
      field_entries << [ idx, "control_type", "" ]
      field_entries << [ idx, "responsible_entities", "" ]
      field_entries << [ idx, "implementation_statement", "" ]
      field_entries << [ idx, "implementation_summary", "" ]
      field_entries << [ idx, "notes", "" ]

      row_order += 1
    end

    # #957 — derived, not minted. Building an SSP twice from the same published
    # profile must yield the same control identifiers, or every OSCAL export
    # diffs completely and the statement UUIDs derived FROM these move too.
    imported_ids = batch_insert_records(
      control_class: SspControl,
      field_class:   SspControlField,
      document_fk:   :ssp_document_id,
      control_attrs: control_attrs,
      field_entries: field_entries,
      uuid_for:       ->(attrs) {
        OscalUuidService.derived(@document.uuid, "ssp-control", attrs[:control_id].to_s)
      }
    )

    create_statements_from_catalog(imported_ids, statement_entries)

    imported_ids
  end

  # #955 — the SSP's statements are what another system can leverage. Without
  # them a profile-generated SSP carried nothing addressable: a field is
  # display text, while only a statement row can hold `set_parameters_data`,
  # be tagged `provided`/`responsibility`, be inherited and be gap-checked. So
  # LeveragedAuthorization#inheritable_statements matched nothing and
  # populate_from_leveraged! resolved zero links no matter how the leveraged
  # authorization was configured.
  #
  # `implementation_prose` is deliberately left blank. It holds the SSP
  # author's response, and a freshly generated SSP has none yet — the same
  # reason `implementation_statement` is scaffolded empty above. The catalog's
  # requirement text is not an implementation of itself.
  #
  # Also deliberately absent: the `provided`/`responsibility` tags. Those are
  # an authoring decision a system owner makes when declaring a customer
  # responsibility matrix, and generating them would fabricate a CRM nobody
  # wrote.
  def create_statements_from_catalog(imported_ids, statement_entries)
    return if statement_entries.empty?

    control_uuids = SspControl.where(id: imported_ids).pluck(:id, :uuid).to_h

    # #1100 — `parent_statement_id` holds the parent's CATALOG STATEMENT ID
    # ("ac-1_smt.a"), not a row FK. That is the existing convention:
    # CatalogPartExtractorService writes `part[:parent_part_id]` into it, the
    # model documents it as a catalog reference, and both
    # CdefToSspInheritanceService and LeveragedAuthorizationService copy the
    # string straight across when they clone statements.
    #
    # So no second pass and no id resolution — the value is already in hand, and
    # writing a numeric id here would have broken every consumer that treats it
    # as the catalog's identifier.
    records = statement_entries.filter_map do |idx, statement_id, parent_id, label, order|
      control_id = imported_ids[idx]
      uuid       = control_uuids[control_id]
      next if uuid.blank?

      SspControlStatement.new(
        ssp_control_id:       control_id,
        statement_id:         statement_id,
        parent_statement_id:  parent_id,
        label:                label,
        # #397 stability invariant, the same derivation the OSCAL importer
        # uses, so the two paths cannot produce different ids for one statement.
        uuid:                 OscalUuidService.derived(uuid, "ssp-statement", statement_id),
        implementation_prose: nil,
        row_order:            order
      )
    end

    records.each_slice(BATCH_SIZE_FIELDS) do |batch|
      SspControlStatement.import(batch, validate: false)
    end
  end

  # OSCAL names a control's statement part "<control-id>_smt", which is what
  # OscalResolvedProfileCatalogService emits. Fall back to that convention
  # when a catalog omits the id, so the statement is still addressable.
  def statement_part_id(control)
    parts = control["parts"]
    part  = parts.is_a?(Array) ? parts.find { |p| p["name"] == "statement" } : nil

    part&.dig("id").presence || "#{control['id']}_smt"
  end

  # Every addressable statement in a control, flattened depth-first with its
  # parent so the SSP mirrors the catalog's structure.
  #
  # Returns [[part_id, parent_part_id, label, row_order], ...].
  #
  # The container part (`name: "statement"`) is INCLUDED: OSCAL lets a response
  # be attached to the whole statement as well as to its items, and dropping it
  # would silently discard implementation prose already recorded against
  # `<control>_smt` by an earlier generation or an OSCAL import.
  #
  # Falls back to the single `_smt` id when the resolved catalog carries no
  # nested parts — a profile resolved before #1100, or one whose catalog has not
  # been re-imported. One statement is wrong, and it is what those documents
  # already have; inventing ids the catalog does not contain would be worse.
  def statement_parts_for(control)
    entries = []
    order   = 0

    walk = lambda do |parts, parent_id|
      Array(parts).each do |part|
        id = part["id"].to_s
        if %w[statement item].include?(part["name"].to_s) && id.present?
          label = Array(part["props"]).find { |pr| pr["name"] == "label" }&.dig("value")
          entries << [ id, parent_id, label, order ]
          order += 1
          walk.call(part["parts"], id)
        else
          walk.call(part["parts"], parent_id)
        end
      end
    end

    statement = Array(control["parts"]).find { |p| p["name"] == "statement" }

    # NO statement part at all -> NO rows. #955: 30 base controls in Rev 5.2.0
    # (ac-2 and au-2 among them) genuinely carry only guidance, and they must
    # yield nothing rather than an empty statement.
    #
    # The test is the PART's existence, not its prose. NIST's container part
    # carries no prose of its own — the text lives in its `item` children — so
    # guarding on prose skips every properly-structured control, which is
    # exactly the mistake an earlier version of this made.
    return [] if statement.blank?

    walk.call([ statement ], nil)

    entries.presence || [ [ statement_part_id(control), nil, nil, 0 ] ]
  end

  def create_by_component_records(imported_control_ids)
    records = imported_control_ids.map do |control_id|
      SspByComponent.new(
        ssp_control_id:        control_id,
        ssp_component_id:      @this_system.id,
        # Seeded from the pair it joins, so the link is stable across
        # regeneration exactly as the two rows it connects are.
        uuid:                  OscalUuidService.derived(
                                 @document.uuid, "ssp-by-component",
                                 control_id.to_s, @this_system.id.to_s
                               ),
        implementation_status: "planned"
      )
    end

    SspByComponent.import(records, validate: false) if records.any?
  end

  def extract_part_prose(control, part_name)
    parts = control["parts"]
    return nil unless parts.is_a?(Array)

    part = parts.find { |p| p["name"] == part_name }
    part&.dig("prose")
  end
end
