# frozen_string_literal: true

# #1390 — writes a boundary's FedRAMP Security Decision Record (SDR-CSO-FRR,
# SDR-CSO-MTD, SDR-CSX-KSI) from what SPARC records:
#
#   metadata            version: the boundary's fedramp_sdr_version (it counts
#                       each change to its statements; the schema's version is
#                       a free string); lastUpdated: the newest statement or
#                       SSP change; updateSource: this SPARC
#   portsAndProtocols   the SSP components' OSCAL protocols: one entry per
#                       protocol and port range (encryption and purpose from
#                       the component when it records them)
#   securityControls    the SSP's controls: status from their statements,
#                       description from their implementation prose, parameter
#                       values from their set-parameters. For Rev5, FedRAMP's
#                       assigned value fills a parameter the SSP leaves unset
#                       (FRC-CSF-ACP)
#   fedRampRequirements the boundary's answered FedRAMP rules that apply to
#                       its profile (FedrampStatement, kind frr)
#   keySecurityIndicators its answered KSIs (kind ksi)
#
# The record is written from whatever is recorded, and validated against the
# pinned schema and for completeness before it is returned. What FedRAMP still
# requires of it is listed separately (#gaps): unanswered rules, unanswered
# KSIs for 20x, Rev5 baseline controls missing from the SSP (FRC-CSF-BSL), and
# ports and protocols.
#
# NIST SP 800-53: PL-2 (security documentation), CA-2, CM-7 (ports and
# protocols), SI-10 (output validated against the pinned schema).
class FedrampSecurityDecisionRecordService
  DOCUMENT_TYPE = FedrampStatement::DOCUMENT_TYPE
  STATUS = { "implemented" => "Implemented", "alternative" => "Implemented",
             "partial" => "Partially Implemented", "planned" => "Not Implemented" }.freeze
  NOT_APPLICABLE = "not-applicable"
  GAP_SAMPLE = 10

  def self.call(boundary) = new(boundary).call

  def initialize(boundary)
    @boundary = boundary
  end

  def call
    doc = header.merge(
      "metadata" => metadata,
      "portsAndProtocols" => ports_and_protocols,
      "securityControls" => security_controls,
      "fedRampRequirements" => requirements,
      "keySecurityIndicators" => indicators
    )
    validated!(doc.reject { |k, v| v.is_a?(Array) && v.empty? && k != "fedRampRequirements" })
  end

  # What FedRAMP still requires of the record, as sentences; empty when none.
  def gaps
    type, _path, klass = @boundary.fedramp_profile
    list = []
    list << "Set the FedRAMP certification type, path and class" unless @boundary.fedramp_profile_complete?
    list << "Link an SSP to the boundary" if ssp.nil?
    unanswered = @boundary.fedramp_applicable_rules.map(&:id) - answered(FedrampRules::FRR).keys
    list << counted("FedRAMP rule", unanswered, "not answered") if unanswered.any?
    if type == "20x"
      ksis = FedrampRules.ksis.map(&:id) - answered(FedrampRules::KSI).keys
      list << counted("Key Security Indicator", ksis, "not answered (required for 20x)") if ksis.any?
    end
    if type == "Rev5" && klass.present?
      missing = FedrampRules.rev5_baseline(klass) - controls.keys
      list << counted("Rev5 Class #{klass} baseline control", missing, "not in the SSP") if missing.any?
    end
    list << "No ports and protocols recorded on the SSP's components" if ports_and_protocols.empty?
    list
  end

  private

  def header
    FedrampVulnerabilityReportService.new(@boundary).header(DOCUMENT_TYPE)
  end

  def metadata
    times = [ @boundary.fedramp_statements.maximum(:updated_at), ssp&.updated_at, @boundary.updated_at ].compact
    { "version" => @boundary.fedramp_sdr_version.to_s,
      "lastUpdated" => times.max.utc.iso8601,
      "updateSource" => "SPARC #{SparcConfig::VERSION}, boundary #{@boundary.uuid}" }
  end

  def ssp = (@ssp ||= @boundary.ssp_document)

  def ports_and_protocols
    @ports_and_protocols ||= Array(ssp&.ssp_components).flat_map do |component|
      props = Array(component.props_data).to_h { |p| [ p["name"].to_s, p["value"] ] }
      Array(component.protocols_data).flat_map do |protocol|
        ranges = Array(protocol["port-ranges"]).presence || [ {} ]
        ranges.map do |range|
          { "serviceName" => [ component.title, protocol["title"].presence || protocol["name"] ].compact_blank.join(": "),
            "portNumber" => port_number(range), "transportProtocol" => range["transport"],
            "encryption" => props["encryption"], "purpose" => component.purpose.presence || component.description.presence
          }.compact_blank
        end
      end
    end
  end

  def port_number(range)
    return nil if range["start"].blank?

    range["end"].present? && range["end"] != range["start"] ? "#{range['start']}-#{range['end']}" : range["start"].to_s
  end

  # The SSP's controls by catalog id, with their statements.
  def controls
    @controls ||= begin
      return {} if ssp.nil?

      ssp.ssp_controls.includes(:ssp_control_statements).to_h { |c| [ c.control_id.to_s.downcase, c ] }
    end
  end

  def security_controls
    type, _path, klass = @boundary.fedramp_profile
    wanted = type == "Rev5" && klass.present? ? FedrampRules.rev5_baseline(klass) | controls.keys : controls.keys
    wanted.filter_map { |id| controls[id] && control_entry(id, controls[id], fill_parameters: type == "Rev5") }
  end

  def control_entry(id, control, fill_parameters:)
    statements = control.ssp_control_statements.sort_by(&:row_order)
    params = statements.flat_map { |s| Array(s.set_parameters_data) }
                       .select { |p| p.is_a?(Hash) && p["param-id"].present? }
                       .to_h { |p| [ p["param-id"], Array(p["values"]).join(", ") ] }
    params = FedrampRules.control_parameters.fetch(id, {}).merge(params) if fill_parameters
    prose = statements.filter_map { |s| s.implementation_prose.presence }.join("\n\n")
    { "controlId" => fedramp_control_id(id),
      "parameterValues" => params.compact_blank.map { |pid, value| { "parameterId" => pid, "parameterValue" => value } },
      "controlImplementationStatus" => control_status(statements),
      "controlImplementationDescription" => prose.presence }.compact.reject { |_, v| v == [] }
  end

  # implemented / alternative → Implemented; any partial, or a mix of in place
  # and planned → Partially Implemented; only planned → Not Implemented.
  # Not-applicable items do not count; nothing recorded → omitted.
  def control_status(statements)
    states = statements.map(&:implementation_status).compact_blank - [ NOT_APPLICABLE ]
    mapped = states.map { |s| STATUS[s] }.compact.uniq
    return nil if mapped.empty?
    return mapped.first if mapped.size == 1

    "Partially Implemented"
  end

  # "ac-2.1" => "AC-2(1)"
  def fedramp_control_id(id)
    base, enhancement = id.split(".", 2)
    "#{base.upcase}#{"(#{enhancement})" if enhancement}"
  end

  def answered(kind)
    @answered ||= {}
    @answered[kind] ||= @boundary.fedramp_statements.where(kind: kind).reject(&:blank_statement?).index_by(&:rule_id)
  end

  def requirements
    applicable = @boundary.fedramp_applicable_rules.map(&:id)
    answered(FedrampRules::FRR).values_at(*applicable).compact.map do |s|
      { "frrID" => s.rule_id, "frrImplementationStatus" => s.status,
        "frrImplementation" => lines(s.implementation), "frrValidation" => lines(s.validation),
        "frrAssessment" => lines(s.assessment) }.compact.reject { |k, v| v == [] && k != "frrImplementation" }
    end
  end

  def indicators
    ids = FedrampRules.ksis.map(&:id)
    answered(FedrampRules::KSI).values_at(*ids).compact.map do |s|
      { "ksiId" => s.rule_id, "ksiImplementationStatus" => s.status,
        "ksiImplementation" => lines(s.implementation), "ksiValidation" => lines(s.validation),
        "ksiAssessment" => lines(s.assessment), "ksiTests" => Array(s.tests),
        "ksiEvidence" => Array(s.evidence).map { |e| evidence(e) } }.compact
    end
  end

  def evidence(entry)
    { "evidenceType" => entry["evidence_type"], "evidenceDescription" => entry["description"],
      "evidenceLocation" => entry["location"], "evidenceText" => entry["text"],
      "lastUpdated" => entry["last_updated"] }.compact_blank
  end

  # One statement per paragraph, as the schema's arrays of statements.
  def lines(text) = text.to_s.split(/\n\s*\n/).map(&:strip).compact_blank

  def counted(noun, ids, what)
    sample = ids.first(GAP_SAMPLE).join(", ")
    more = ids.size > GAP_SAMPLE ? ", and #{ids.size - GAP_SAMPLE} more" : ""
    "#{ids.size} #{noun}#{'s' unless ids.size == 1} #{what}: #{sample}#{more}"
  end

  def validated!(doc) = FedrampVulnerabilityReportService.validated!(DOCUMENT_TYPE, doc)
end
