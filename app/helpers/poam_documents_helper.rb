# frozen_string_literal: true

# v1.17.2 — the POA&M page's record sections.
#
# Five kinds of record hang off a POA&M besides its items: risks, remediations,
# observations, findings and local components. Each had "+ Add" and a working
# edit/delete route, and none had a way to reach either from the page. Risks
# were worse: they rendered only inside the items they were linked to, so an
# unlinked risk (257 of 263 on the preserved database, measured 2026-10-22)
# appeared nowhere at all.
#
# One definition for the five: each section is the same shell — heading with a
# count, one row per record, Edit and Delete — described here and rendered by
# poam_documents/_record_sections. Only resolution differs, because only risks
# and remediations carry a status in OSCAL (PoamResolutionService).
module PoamDocumentsHelper
  # Shared with the item cards on the same page.
  LEVEL_VARIANTS = {
    "very-low" => "info", "low" => "info", "moderate" => "warning",
    "high" => "orange", "very-high" => "danger", "medium" => "warning"
  }.freeze
  STATUS_VARIANTS = {
    "open" => "danger", "investigating" => "orange", "remediating" => "warning",
    "deviation-requested" => "orange", "deviation-approved" => "warning", "closed" => "success"
  }.freeze

  RecordSection = Struct.new(:key, :title, :rows, keyword_init: true)
  RecordRow = Struct.new(:record, :kind, :title, :badges, :edit_path, :delete_path,
                         :delete_confirm, keyword_init: true)

  def poam_record_sections(document)
    [
      RecordSection.new(key: "risks", title: "Risks", rows: poam_risk_rows(document)),
      RecordSection.new(key: "remediations", title: "Remediations", rows: poam_remediation_rows(document)),
      RecordSection.new(key: "observations", title: "Observations", rows: poam_simple_rows(
        document, document.poam_observations, :observation, "observation")),
      RecordSection.new(key: "findings", title: "Findings", rows: poam_simple_rows(
        document, document.poam_findings, :finding, "finding")),
      RecordSection.new(key: "components", title: "Components", rows: poam_simple_rows(
        document, document.poam_local_components, :local_component, "component"))
    ]
  end

  private

  def poam_risk_rows(document)
    document.poam_risks.order(:id).includes(:poam_remediations).map do |risk|
      badges = [ [ risk.status, STATUS_VARIANTS[risk.status] || "neutral" ] ]
      badges << [ "Impact: #{risk.impact}", LEVEL_VARIANTS[risk.impact] || "neutral" ] if risk.impact.present?
      badges << [ "Deadline: #{risk.deadline.to_date.iso8601}", "neutral" ] if risk.deadline.present?
      also = risk.poam_remediations.size
      confirm = "Delete the risk \"#{risk.title}\"?"
      confirm += " Its #{also} remediation#{"s" unless also == 1} and their milestones go with it." if also.positive?
      confirm += " To record that it was resolved, Close it instead."

      RecordRow.new(record: risk, kind: :risk, title: risk.title, badges: badges,
                    edit_path: edit_poam_document_poam_risk_path(document, risk),
                    delete_path: poam_document_poam_risk_path(document, risk),
                    delete_confirm: confirm)
    end
  end

  def poam_remediation_rows(document)
    PoamRemediation.joins(:poam_risk).where(poam_risks: { poam_document_id: document.id })
                   .includes(:poam_risk, :poam_milestones).order(:id).map do |rem|
      badges = [ [ rem.lifecycle.presence || "no lifecycle", rem.lifecycle == "completed" ? "success" : "info" ],
                 [ "Risk: #{rem.poam_risk.title}", "neutral" ] ]
      milestones = rem.poam_milestones.size
      confirm = "Delete the remediation \"#{rem.title}\"?"
      confirm += " Its #{milestones} milestone#{"s" unless milestones == 1} go with it." if milestones.positive?
      confirm += " To record that it was carried out, mark it Completed instead."

      RecordRow.new(record: rem, kind: :remediation, title: rem.title, badges: badges,
                    edit_path: edit_poam_document_poam_remediation_path(document, rem),
                    delete_path: poam_document_poam_remediation_path(document, rem),
                    delete_confirm: confirm)
    end
  end

  def poam_simple_rows(document, scope, route, noun)
    scope.order(:id).map do |record|
      RecordRow.new(record: record, kind: route, title: record.title, badges: [],
                    edit_path: public_send(:"edit_poam_document_poam_#{route}_path", document, record),
                    delete_path: public_send(:"poam_document_poam_#{route}_path", document, record),
                    delete_confirm: "Delete the #{noun} \"#{record.title}\"? This cannot be undone.")
    end
  end
end
