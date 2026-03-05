class ProfileJsonParserService
  BATCH_SIZE_CONTROLS = 5_000
  BATCH_SIZE_FIELDS   = 10_000

  def initialize(profile_document, file_path)
    @document  = profile_document
    @file_path = file_path
  end

  def parse
    content = File.read(@file_path).force_encoding("UTF-8")
    data    = JSON.parse(content)

    case detect_json_format(data)
    when :inspec_profile then parse_inspec_profile(data)
    when :stigviewer      then parse_stigviewer(data)
    else                       parse_generic(data)
    end
  end

  private

  def detect_json_format(data)
    return :inspec_profile if data.key?("profiles") || (data.key?("controls") && data.key?("version"))
    return :stigviewer     if data.key?("stigs")
    :generic
  end

  # ── InSpec Profile JSON ──────────────────────────────────────────

  def parse_inspec_profile(data)
    profiles = data["profiles"] || [ data ]
    profile  = profiles.first

    @document.update!(
      profile_type:    "custom",
      profile_version: profile["version"],
      description:     profile["summary"] || profile["title"],
      import_metadata: { "format" => "inspec", "name" => profile["name"] }.compact
    )

    control_attrs = []
    field_entries = []
    row_order     = 0

    (profile["controls"] || data["controls"] || []).each do |ctrl|
      attrs = {
        control_id:     ctrl["id"],
        title:          ctrl["title"],
        severity:       impact_to_severity(ctrl["impact"]),
        control_family: ctrl["id"].to_s.split("-").first.upcase.presence,
        row_order:      row_order
      }

      fields = build_inspec_fields(ctrl)
      idx = control_attrs.size
      control_attrs << attrs
      fields.each { |fname, fval| field_entries << [ idx, fname, fval ] }
      row_order += 1
    end

    batch_insert(control_attrs, field_entries)
  end

  def build_inspec_fields(ctrl)
    fields = {}
    fields["description"]   = ctrl["desc"]                          if ctrl["desc"].present?
    fields["impact"]        = ctrl["impact"].to_s                   if ctrl["impact"].present?
    fields["rationale"]     = ctrl["rationale"]                     if ctrl["rationale"].present?
    fields["check_content"] = Array(ctrl.dig("tags", "check")).join("\n") if ctrl.dig("tags", "check").present?
    fields["fix_text"]      = Array(ctrl.dig("tags", "fix")).join("\n")   if ctrl.dig("tags", "fix").present?
    fields["nist_controls"] = Array(ctrl.dig("tags", "nist")).join(", ") if ctrl.dig("tags", "nist").present?
    fields["cci_refs"]      = Array(ctrl.dig("tags", "cci")).join(", ")  if ctrl.dig("tags", "cci").present?
    fields
  end

  # ── STIG Viewer JSON ─────────────────────────────────────────────

  def parse_stigviewer(data)
    stig = data["stigs"]&.first
    raise "No STIG data found in JSON" unless stig

    @document.update!(
      profile_type:    "disa_stig",
      description:     stig["stig_name"],
      import_metadata: { "format" => "stigviewer" }
    )

    control_attrs = []
    field_entries = []
    row_order     = 0

    (stig["findings"] || []).each do |finding|
      attrs = {
        control_id: finding["vuln_num"],
        title:      finding["rule_title"],
        severity:   finding["severity"],
        group_id:   finding["vuln_num"],
        rule_id:    finding["rule_id"],
        row_order:  row_order
      }

      fields = {}
      fields["description"]   = finding["discussion"]   if finding["discussion"].present?
      fields["fix_text"]      = finding["fix_text"]      if finding["fix_text"].present?
      fields["check_content"] = finding["check_content"] if finding["check_content"].present?
      fields["cci_refs"]      = finding["cci_ref"]       if finding["cci_ref"].present?
      fields["status"]        = finding["status"]        if finding["status"].present?

      idx = control_attrs.size
      control_attrs << attrs
      fields.each { |fname, fval| field_entries << [ idx, fname, fval ] }
      row_order += 1
    end

    batch_insert(control_attrs, field_entries)
  end

  # ── Generic JSON ─────────────────────────────────────────────────

  def parse_generic(data)
    @document.update!(
      profile_type:    "custom",
      description:     data["description"] || data["title"],
      import_metadata: { "format" => "generic" }
    )

    controls_array = data["controls"] || data["rules"] || data["findings"] || []
    return if controls_array.empty?

    control_attrs = []
    field_entries = []
    row_order     = 0

    controls_array.each do |ctrl|
      attrs = {
        control_id: ctrl["id"] || ctrl["control_id"] || ctrl["rule_id"],
        title:      ctrl["title"] || ctrl["name"],
        severity:   ctrl["severity"] || ctrl["impact"],
        row_order:  row_order
      }

      field_data = ctrl.except("id", "control_id", "rule_id", "title", "name", "severity", "impact")
      idx = control_attrs.size
      control_attrs << attrs
      field_data.each do |k, v|
        val = v.is_a?(Hash) || v.is_a?(Array) ? v.to_json : v.to_s
        field_entries << [ idx, k.to_s, val ] if val.present?
      end
      row_order += 1
    end

    batch_insert(control_attrs, field_entries)
  end

  # ── Helpers ──────────────────────────────────────────────────────

  def impact_to_severity(impact)
    return nil if impact.nil?
    case impact.to_f
    when 0.7..1.0  then "high"
    when 0.4..0.69 then "medium"
    when 0.01..0.39 then "low"
    else "info"
    end
  end

  def batch_insert(control_attrs, field_entries)
    ActiveRecord::Base.transaction do
      imported_ids = []

      control_attrs.each_slice(BATCH_SIZE_CONTROLS) do |batch|
        records = batch.map do |attrs|
          ProfileControl.new(
            profile_document_id: @document.id,
            **attrs.compact
          )
        end
        result = ProfileControl.import(records, validate: false, returning: :id)
        imported_ids.concat(result.ids)
      end

      field_records = field_entries.map do |ctrl_idx, fname, fval|
        ProfileControlField.new(
          profile_control_id: imported_ids[ctrl_idx],
          field_name:         fname,
          field_value:        fval,
          editable:           ProfileControlField::EDITABLE_FIELDS.include?(fname)
        )
      end

      field_records.each_slice(BATCH_SIZE_FIELDS) do |batch|
        ProfileControlField.import(batch, validate: false)
      end
    end
  end
end
