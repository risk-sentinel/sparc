# frozen_string_literal: true

# #843 — build a POA&M from assessment output.
#
# Every other document in the authorization chain has a generator
# (CatalogImportService, ProfileControlSelectionService, SspFromProfileService,
# SapGeneratorService, SarFromSspService). POA&M had only parsers and an
# exporter, so the terminal artifact — the one customers touch monthly rather
# than once at authorization — could enter SPARC only by importing an
# externally-authored OSCAL file or by hand-assembling the
# PoamDocument → items / risks / findings / observations graph record by record.
#
# The natural lifecycle step is "the assessment produced findings, so open a
# POA&M to track their remediation". That is what this does: a SAR's OPEN risks
# become POA&M items, carrying their findings and observations across with the
# relationships intact.
#
# ── Nothing is synthesised ────────────────────────────────────────────────
#
# This is the load-bearing rule, and it is inherited rather than invented:
# #832 made PoamRisk require title/description/statement/status/deadline and
# PoamFinding require title/description/target_data, precisely so invalid OSCAL
# could not be CREATED and then fail much later at export. A generator that
# filled those in with placeholders would reintroduce that bug wholesale, and
# worse — a risk statement, a deadline and a finding target are substantive
# compliance content that an assessor and an AO read. Inventing them is not a
# convenience, it is fabricating an assessment record.
#
# So a source risk that cannot form a VALID POA&M entry is skipped and
# REPORTED, never completed on the author's behalf. The result object carries
# every omission with the reason, so the caller can say "3 risks were not
# converted because they carry no statement" instead of silently producing a
# thinner POA&M than the assessment justified.
#
# The one derived value is `deadline`, and only when the source has none: it
# comes from the admin-provisioned RemediationTimeline SLA table, keyed by the
# boundary's profile baseline and the risk's severity. That is a policy lookup
# the organisation configured, not a number this service made up — and if no
# window resolves, the risk is skipped rather than given an arbitrary date.
#
# NIST 800-53: CA-5 (Plan of Action and Milestones), CA-2 (Control
# Assessments), RA-5 (Vulnerability Monitoring and Scanning).
class PoamGeneratorService
  # Copied verbatim from the SAR when present — the two schemas mirror each
  # other because both derive from the same OSCAL assembly definitions.
  RISK_CARRIED_FIELDS = %i[
    title description statement status impact likelihood
    props_data links_data origins_data characterizations_data
    mitigating_factors_data risk_log_data remarks
  ].freeze

  FINDING_CARRIED_FIELDS = %i[
    title description target_data implementation_statement_uuid
    props_data links_data origins_data remarks
  ].freeze

  OBSERVATION_CARRIED_FIELDS = %i[
    title description collected expires methods_data types_data
    subjects_data relevant_evidence_data props_data links_data origins_data remarks
  ].freeze

  # A source risk is in scope unless the assessment already CLOSED it.
  #
  # A blank status is deliberately still in scope, even though it is then
  # rejected below for missing a required field. Excluding it here instead
  # would drop it silently; letting it reach the required-field check means the
  # author is told "this risk has no status" and can fix the assessment. A
  # reported omission is worth more than a quiet one, which is the same reason
  # skipped entries carry a reason at all.
  CLOSED_STATUSES = %w[closed].freeze

  Result = Struct.new(:poam_document, :skipped, keyword_init: true) do
    def created_items    = poam_document.poam_items.size
    def created_risks    = poam_document.poam_risks.size
    def created_findings = poam_document.poam_findings.size
    def skipped_count    = skipped.size
    def complete?        = skipped.empty?
  end

  def initialize(name:, sar_document: nil, authorization_boundary: nil, description: nil)
    @name = name
    @sar = sar_document
    @boundary = authorization_boundary || sar_document&.authorization_boundary
    @description = description
    @skipped = []
  end

  # Returns a Result. Raises only on a genuine persistence failure — a source
  # record that cannot be converted is reported, not raised.
  def generate
    ActiveRecord::Base.transaction do
      document = create_document
      import_from_sar(document) if @sar
      document.update!(lifecycle_status: "in_progress") if document.poam_items.any?

      Result.new(poam_document: document.reload, skipped: @skipped)
    end
  end

  private

  def create_document
    PoamDocument.create!(
      name: @name,
      description: @description,
      authorization_boundary: @boundary,
      ssp_document: @sar&.ssp_document,
      # `status` tracks the ingest/build pipeline — a generated document is
      # fully built. `lifecycle_status` tracks authoring progress
      # (started → in_progress → published) and is set AFTER import, because
      # which value is truthful depends on whether anything was carried across:
      # an empty scaffold has not been worked yet, a POA&M holding a SAR's
      # risks plainly has.
      status: "completed",
      lifecycle_status: "started"
    )
  end

  def import_from_sar(document)
    source_risks.each_with_index do |sar_risk, index|
      deadline = resolve_deadline(sar_risk)

      if (reason = rejection_reason(sar_risk, deadline))
        @skipped << { type: "risk", uuid: sar_risk.uuid, title: sar_risk.title, reason: reason }
        next
      end

      build_entry(document, sar_risk, deadline, index)
    end
  end

  # Only OPEN risks. A closed risk has no remediation left to track, so
  # carrying it across would misrepresent the POA&M's outstanding workload.
  def source_risks
    SarRisk.where(sar_result_id: @sar.sar_results.select(:id))
           .reject { |risk| CLOSED_STATUSES.include?(risk.status.to_s.strip.downcase) }
  end

  # Checked BEFORE writing anything, so a rejected risk leaves no partial graph
  # behind — the alternative is relying on validation to fail mid-build, which
  # would roll back the whole transaction and lose the convertible risks too.
  def rejection_reason(sar_risk, deadline)
    missing = PoamRisk::OSCAL_REQUIRED_FIELDS.select { |field| sar_risk.public_send(field).blank? }
    return "source risk is missing #{missing.join(', ')}" if missing.any?
    return "no deadline on the source risk and no remediation SLA resolved for this boundary" if deadline.nil?

    nil
  end

  def build_entry(document, sar_risk, deadline, index)
    risk = document.poam_risks.create!(
      **sar_risk.slice(*RISK_CARRIED_FIELDS.map(&:to_s)).symbolize_keys,
      uuid: SecureRandom.uuid,
      deadline: deadline
    )

    item = document.poam_items.create!(
      title: sar_risk.title,
      description: sar_risk.description,
      # Present by construction: a blank status is rejected above, so there is
      # nothing to default here.
      risk_status: sar_risk.status,
      impact: sar_risk.impact,
      likelihood: sar_risk.likelihood,
      deadline: deadline.to_date,
      row_order: index,
      origins_data: sar_risk.origins_data,
      props_data: sar_risk.props_data,
      links_data: sar_risk.links_data
    )
    PoamItemRisk.create!(poam_item: item, poam_risk: risk)

    carry_findings(document, sar_risk, item, risk)
    carry_observations(document, sar_risk, item, risk)
  end

  # Findings reached through the SAR's own finding↔risk join, so the POA&M
  # inherits the assessor's linkage rather than a re-derived guess at it.
  def carry_findings(document, sar_risk, item, risk)
    sar_risk.sar_findings.each do |sar_finding|
      missing = PoamFinding::OSCAL_REQUIRED_FIELDS.select { |f| sar_finding.public_send(f).blank? }
      if missing.any?
        @skipped << { type: "finding", uuid: sar_finding.uuid, title: sar_finding.title,
                      reason: "source finding is missing #{missing.join(', ')}" }
        next
      end

      finding = document.poam_findings.create!(
        **sar_finding.slice(*FINDING_CARRIED_FIELDS.map(&:to_s)).symbolize_keys,
        uuid: SecureRandom.uuid
      )
      PoamItemFinding.create!(poam_item: item, poam_finding: finding)
      PoamFindingRisk.create!(poam_finding: finding, poam_risk: risk)
    end
  end

  # Deduplicated per POA&M: one SAR observation can be evidence for several
  # risks, and copying it once per risk would inflate the POA&M with duplicates
  # of the same evidence record.
  def carry_observations(document, sar_risk, item, risk)
    sar_risk.sar_observations.each do |sar_observation|
      observation = observation_cache[sar_observation.id] ||= document.poam_observations.create!(
        **sar_observation.slice(*OBSERVATION_CARRIED_FIELDS.map(&:to_s)).symbolize_keys,
        uuid: SecureRandom.uuid
      )

      PoamItemObservation.find_or_create_by!(poam_item: item, poam_observation: observation)
      PoamRiskObservation.find_or_create_by!(poam_risk: risk, poam_observation: observation)
    end
  end

  def observation_cache = @observation_cache ||= {}

  # The source's own deadline wins. Otherwise the organisation's SLA decides —
  # a configured policy lookup, not a number invented here. nil when neither
  # resolves, which rejects the risk rather than inventing a date.
  def resolve_deadline(sar_risk)
    return sar_risk.deadline if sar_risk.deadline.present?

    days = RemediationTimeline.window_days(baseline_level, criticality_for(sar_risk))
    days && Time.current + days.days
  end

  def baseline_level
    @baseline_level ||= RemediationTimeline.normalize_baseline(@boundary&.profile_document&.baseline_level)
  end

  # OSCAL risks carry severity as `impact`, but scanner-derived ones often put
  # it in props instead, which is where HDF-sourced risks land.
  def criticality_for(sar_risk)
    raw = sar_risk.impact.presence || severity_prop(sar_risk)
    RemediationTimeline.normalize_criticality(raw)
  end

  def severity_prop(sar_risk)
    Array(sar_risk.props_data)
      .find { |prop| prop.is_a?(Hash) && prop["name"].to_s.downcase.in?(%w[severity criticality impact]) }
      &.dig("value")
  end
end
