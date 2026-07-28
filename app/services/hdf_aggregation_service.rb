# frozen_string_literal: true

# #809 — aggregate the current scanner findings + dispositions for a boundary into
# its compliance documents. Findings map to NIST controls via their HDF `tags.nist`;
# the matching SSP / SAP / SAR controls get a NON-destructive `hdf_scan_result`
# annotation field (never overwriting authored fields), and failed, non-suppressed
# findings are tracked as POA&M findings. Idempotent — re-running upserts by
# (control, field) and by POA&M title, so it can run on every scan or on demand.
#
# NIST 800-53: CA-7 (continuous monitoring), CA-5 (POA&M), SI-2 (flaw remediation),
# AU-12 (audit — caller).
class HdfAggregationService
  ANNOTATION_FIELD = "hdf_scan_result"

  Result = Struct.new(:ssp, :sar, :sap, :poam, keyword_init: true) do
    def to_h
      { ssp: ssp, sar: sar, sap: sap, poam: poam }
    end
  end

  def initialize(boundary)
    @boundary = boundary
  end

  def aggregate
    findings = @boundary.scanner_findings.current.to_a
    Result.new(
      ssp:  annotate_controls(@boundary.ssp_document, findings, :ssp_controls, :ssp_control_fields),
      sar:  annotate_controls(@boundary.sar_document, findings, :sar_controls, :sar_control_fields),
      sap:  annotate_controls(@boundary.sap_document, findings, :sap_controls, :sap_control_fields),
      poam: aggregate_poam(findings)
    )
  end

  private

  # Non-destructive: writes a dedicated annotation field on each matching control,
  # keyed by the finding's NIST control tags (HDF -> NIST -> document control).
  def annotate_controls(document, findings, controls_assoc, fields_assoc)
    return 0 unless document

    controls = document.public_send(controls_assoc).index_by { |c| c.control_id.to_s.upcase }
    touched = 0
    findings.each do |finding|
      nist_controls_for(finding).each do |cid|
        control = controls[cid.to_s.upcase]
        next unless control

        field = control.public_send(fields_assoc).find_or_initialize_by(field_name: ANNOTATION_FIELD)
        field.field_value = annotation_for(finding)
        field.save!
        touched += 1
      end
    end
    touched
  end

  # Failed findings that aren't suppressed by an applicable false-positive/waiver/
  # inherited disposition become tracked POA&M findings (upserted by control id).
  def aggregate_poam(findings)
    poam = @boundary.poam_documents.first
    return 0 unless poam

    tracked = 0
    findings.each do |finding|
      next unless finding.status == "failed"

      disp = finding.disposition
      next if disp && FindingDisposition::NOT_APPLICABLE_KINDS.include?(disp.kind) && disp.applicable?

      pf = poam.poam_findings.find_or_initialize_by(title: "HDF: #{finding.control_id}")
      pf.uuid ||= SecureRandom.uuid
      pf.description = annotation_for(finding)
      pf.target_data = finding_target_for(finding)
      pf.save!
      tracked += 1
    end
    tracked
  end

  # OSCAL REQUIRES finding/target: what was assessed, and the resulting state
  # (#840). Without it the POA&M this aggregation writes into fails schema
  # validation in EVERY serialization, and the user is bounced back from the
  # export with no indication why — a single aggregation run was enough to make
  # the whole document unexportable.
  #
  # Every value here is DERIVED, not invented. The control is the thing the
  # scanner actually assessed (`ScannerFinding` validates `control_id`
  # presence, so it is always available), and the state is the scan's own
  # verdict. `aggregate_poam` only reaches this for `status == "failed"`, which
  # is precisely "not-satisfied" — an accepted or mitigated risk does not make
  # the control satisfied, so the disposition must not soften it.
  def finding_target_for(finding)
    control_id = finding.control_id.to_s.strip

    # Statement ids in the NIST OSCAL catalogs are lower-case (`ac-2_smt`),
    # while HDF tags the control upper-case (`AC-2`). Downcase so the target
    # actually resolves against the catalog instead of dangling.
    {
      "type"        => "statement-id",
      "target-id"   => "#{control_id.downcase}_smt",
      "title"       => "Assessment objective for #{control_id.upcase}",
      "description" => annotation_for(finding),
      "status"      => { "state" => "not-satisfied" }
    }
  end

  def nist_controls_for(finding)
    tags = finding.raw_hdf.is_a?(Hash) ? finding.raw_hdf["tags"] : nil
    Array(tags.is_a?(Hash) ? tags["nist"] : nil).map(&:to_s).reject(&:blank?)
  end

  def annotation_for(finding)
    disp = finding.disposition
    parts = [ "#{finding.scanner} #{finding.status}", "severity=#{finding.severity}",
              "lifecycle=#{finding.lifecycle_status}" ]
    parts << "disposition=#{disp.kind}(#{disp.approval_status})" if disp
    parts << "component=#{finding.component_ref}" if finding.component_ref.present?
    parts.join("; ")
  end
end
