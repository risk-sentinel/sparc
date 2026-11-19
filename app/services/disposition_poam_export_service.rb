# frozen_string_literal: true

# #1368 — an OSCAL POA&M for a boundary's finding dispositions, in NIST's
# vocabulary.
#
# The dispositions go out as HDF amendments (HdfAmendmentExportService), hdf
# converts those to an OSCAL POA&M (`--from hdf-amendments --to oscal-poam`),
# and this completes each risk before the POA&M is validated. Measured on
# hdf-cli 3.8.0: hdf writes a risk's status only as open or closed, records the
# override type in its own props, and writes no NIST risk prop, no response and
# no typed risk-log entry. From the disposition, each risk gets:
#
#   * `status` — the NIST risk status the user picked;
#   * a NIST risk prop (false-positive | accepted | risk-adjusted) valued
#     DispositionVocabulary::RISK_PROP_VALUE;
#   * a characterization with NIST likelihood, impact and risk facets on
#     SP 800-30 Rev. 1's scale (risk derived from Table I-2), each carrying the
#     picked `state` (initial | adjusted);
#   * a response with the picked lifecycle and the kind's NIST response `type`;
#   * risk-log entries typed by the kind (DispositionVocabulary.risk_log_types).
#
# A disposition decided before these fields existed is refused, by name: the
# export never writes a POA&M that claims a NIST state nobody chose.
#
# NIST 800-53: CA-5 (plan of action and milestones), RA-3 (risk assessment),
# AU-10 (who decided, in the risk log).
class DispositionPoamExportService
  # Dispositions the export cannot express, with what each lacks.
  class MissingNistFields < StandardError
    attr_reader :missing

    # @param missing [Hash{String => Array<Symbol>}] control_id => fields
    def initialize(missing)
      @missing = missing
      super("#{missing.size} #{missing.size == 1 ? 'disposition lacks' : 'dispositions lack'} the NIST " \
            "POA&M fields an OSCAL POA&M needs: " +
            missing.map { |control_id, fields| "#{control_id} (#{fields.join(', ')})" }.join("; ") +
            ". Edit each disposition on the triage screen and choose them.")
    end
  end

  HDF_NS = "https://mitre.github.io/hdf-libs/ns/oscal"

  def initialize(boundary, runner: HdfRunner.new)
    @boundary = boundary
    @runner = runner
  end

  # @return [Hash] a validated OSCAL POA&M
  # @raise [MissingNistFields] when an exported disposition lacks its NIST fields
  def export
    amendments = HdfAmendmentExportService.new(@boundary, runner: @runner).export
    by_control = dispositions_for(amendments)
    refuse_incomplete!(by_control.values)

    HdfOscalTranslationService.new(runner: @runner)
                              .oscal_poam_from_hdf_amendments(StringIO.new(JSON.generate(amendments)),
                                                              boundary: @boundary) do |oscal|
      complete(oscal, by_control)
    end
  end

  private

  def dispositions_for(amendments)
    ids = Array(amendments["overrides"]).map { |o| o["requirementId"] }
    @boundary.finding_dispositions.where(control_id: ids).index_by(&:control_id)
  end

  def refuse_incomplete!(dispositions)
    missing = dispositions.sort_by(&:control_id).each_with_object({}) do |d, acc|
      fields = d.missing_nist_fields
      acc[d.control_id] = fields if fields.any?
    end
    raise MissingNistFields, missing if missing.any?
  end

  def complete(oscal, by_control)
    poam = oscal.fetch("plan-of-action-and-milestones")
    Array(poam["risks"]).each do |risk|
      disposition = by_control[requirement_id(risk)]
      complete_risk(risk, disposition) if disposition
    end
    oscal
  end

  def requirement_id(risk)
    Array(risk["props"]).find { |p| p["name"] == "hdf-requirement-id" && p["ns"] == HDF_NS }&.dig("value")
  end

  def complete_risk(risk, disposition)
    mapping = DispositionVocabulary.for(disposition.kind)
    party = Array(risk.dig("risk-log", "entries")).flat_map { |e| Array(e["logged-by"]) }.first&.dig("party-uuid")

    risk["status"] = disposition.nist_risk_status
    risk["props"] = Array(risk["props"]) + [
      { "name" => disposition.nist_risk_prop, "value" => DispositionVocabulary::RISK_PROP_VALUE }
    ]
    risk["characterizations"] = [ characterization(disposition, party) ]
    risk["remediations"] = [ response(disposition, mapping) ]
    log = risk["risk-log"] ||= {}
    log["entries"] = Array(log["entries"]) + log_entries(disposition, party)
  end

  # The person who decided is the actor when hdf recorded one (appliedBy);
  # otherwise SPARC, as the tool, as RiskRating does.
  def characterization(disposition, party)
    actor = party ? { "type" => "party", "actor-uuid" => party } : RiskRating.sparc_tool_actor
    levels = { "likelihood" => disposition.nist_likelihood, "impact" => disposition.nist_impact,
               "risk" => disposition.nist_risk_level }
    {
      "origin" => { "actors" => [ actor ] },
      "facets" => levels.map do |name, value|
        { "name" => name, "system" => DispositionVocabulary::NIST_FACET_SYSTEM, "value" => value,
          "props" => [ { "name" => "state", "value" => disposition.nist_facet_state } ] }
      end
    }
  end

  def response(disposition, mapping)
    {
      "uuid" => OscalUuidService.derived(disposition.uuid, "poam-response"),
      "lifecycle" => disposition.nist_response_lifecycle,
      "title" => "#{disposition.kind} response",
      "description" => disposition.reason,
      "props" => [ { "name" => "type", "value" => mapping.response_type } ]
    }
  end

  def log_entries(disposition, party)
    DispositionVocabulary.risk_log_types(disposition.kind, disposition.approval_status).map do |type|
      approval = type.in?(%w[dr-approved dr-rejected])
      entry = {
        "uuid" => OscalUuidService.derived(disposition.uuid, "poam-risk-log", type),
        "title" => type,
        "description" => approval ? "#{type} by #{disposition.approved_by}" : disposition.reason,
        "start" => ((approval ? disposition.approved_at : disposition.decided_at) || disposition.created_at).utc.iso8601,
        "props" => [ { "name" => "type", "value" => type } ],
        "status-change" => disposition.nist_risk_status
      }
      entry["logged-by"] = [ { "party-uuid" => party } ] if party
      entry
    end
  end
end
