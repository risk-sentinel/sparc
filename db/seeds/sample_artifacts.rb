# Sample Artifacts Seed — creates SAP, POA&M, CDEF, Profile, and KSI Validations
# for the ACME Cloud Platform authorization boundary.
#
# Supports selective seeding via SPARC_SEED_MODE env var:
#   SPARC_SEED_MODE=traditional  — SSP, SAP, SAR, POA&M, CDEF, Profile only
#   SPARC_SEED_MODE=20x          — KSI validations and 20x evidence only
#   SPARC_SEED_MODE=full         — both (default)
#
# Run with: bin/rails db:seed
# Or:       SPARC_SEED_MODE=traditional bin/rails db:seed

mode = ENV.fetch("SPARC_SEED_MODE", "full").downcase
puts "\nSeeding sample artifacts (mode: #{mode})..."

auth_boundary = AuthorizationBoundary.find_by(name: "Cloud Web Application ATO")
unless auth_boundary
  puts "  WARNING: No authorization boundary found. Some artifacts will be skipped."
  puts "  Set SPARC_SEED_DEMO=true and re-run seeds to create demo data."
end

nist_catalog = ControlCatalog.find_by(name: "NIST SP 800-53 Rev 5")
acme_ssp = SspDocument.find_by("name LIKE ?", "%ACME Cloud Platform%")

# ── Traditional Artifacts ─────────────────────────────────────────────
if %w[traditional full].include?(mode)
  puts "  Seeding traditional NIST 800-53 artifacts..."

  # ── SAP Document ──────────────────────────────────────────────────
  sap = SapDocument.find_or_create_by!(name: "ACME Cloud Platform — Annual Assessment Plan (Rev 5)") do |d|
    d.status           = "completed"
    d.lifecycle_status  = "in_progress"
    d.assessment_type   = "annual"
    d.assessment_start  = Date.new(2026, 1, 15)
    d.assessment_end    = Date.new(2026, 3, 15)
    d.assessors         = "Dr. Sarah Chen (3PAO Lead), Mike Torres (Technical Assessor)"
    # #946 — the scope has to describe the plan that exists. This said "all 370
    # controls" beside a hand-written list of fourteen, and 370 is not the size
    # of the Rev 5 MODERATE baseline either. The count is read from the SSP so
    # it cannot drift from the document again.
    d.assessment_scope  = "Full assessment of ACME Cloud Platform per NIST SP 800-53 Rev 5 Moderate " \
                          "baseline. Covers #{acme_ssp&.ssp_controls&.count || 0} controls across " \
                          "production and development environments."
    d.sap_version       = "1.0"
    d.description       = "DEMO/SAMPLE — Fictional annual security assessment plan for testing purposes only."
    d.ssp_document      = acme_ssp if acme_ssp
    d.authorization_boundary = auth_boundary
  end

  SAP_CONTROLS = [
    { control_id: "ac-2",  title: "Account Management",                       method: "examine" },
    { control_id: "ac-3",  title: "Access Enforcement",                       method: "test" },
    { control_id: "ac-6",  title: "Least Privilege",                          method: "interview" },
    { control_id: "au-2",  title: "Event Logging",                            method: "examine" },
    { control_id: "au-6",  title: "Audit Record Review, Analysis, Reporting", method: "examine" },
    { control_id: "ca-2",  title: "Control Assessments",                      method: "interview" },
    { control_id: "ca-7",  title: "Continuous Monitoring",                    method: "test" },
    { control_id: "ia-2",  title: "Identification and Authentication",        method: "test" },
    { control_id: "ia-5",  title: "Authenticator Management",                 method: "examine" },
    { control_id: "sc-8",  title: "Transmission Confidentiality",             method: "test" },
    { control_id: "sc-13", title: "Cryptographic Protection",                 method: "test" },
    { control_id: "cm-6",  title: "Configuration Settings",                   method: "examine" },
    { control_id: "ir-4",  title: "Incident Handling",                        method: "interview" },
    { control_id: "ra-5",  title: "Vulnerability Monitoring and Scanning",    method: "test" }
  ].freeze

  # #946 — plan the assessment of the SSP's controls, not a hand-written
  # fourteen. A SAP that covers 14 controls while its SAR assesses 288 is not a
  # plan for that assessment. The curated fourteen keep their chosen method;
  # every other control the SSP documents is added with a derived one.
  curated_ids = SAP_CONTROLS.map { |c| c[:control_id] }
  extra = (acme_ssp&.ssp_controls || [])
            .reject { |c| curated_ids.include?(c.control_id.to_s.downcase) }
            .map.with_index do |c, i|
              { control_id: c.control_id.to_s.downcase, title: c.title.to_s,
                # Deterministic, not `sample`: a seed that produces different
                # data on each run cannot be diffed or reasoned about.
                method: %w[examine interview test][i % 3] }
            end

  (SAP_CONTROLS + extra).each_with_index do |ctrl, idx|
    sap_ctrl = SapControl.find_or_create_by!(sap_document: sap, control_id: ctrl[:control_id]) do |c|
      c.title             = ctrl[:title]
      c.assessment_method  = ctrl[:method]
      c.assessment_status  = "planned"
      c.row_order          = idx
    end

    # Add assessment detail fields
    [
      { field_name: "assessment_objectives", field_value: "Verify #{ctrl[:title].downcase} implementation meets NIST SP 800-53 Rev 5 requirements." },
      # Derived from what is being assessed rather than randomised: a control
      # with a bespoke implementation warrants a deeper look than one inherited
      # wholesale from the platform.
      { field_name: "assessment_depth",
        field_value: curated_ids.include?(ctrl[:control_id]) ? "comprehensive" : "focused" }
    ].each do |field|
      SapControlField.find_or_create_by!(sap_control: sap_ctrl, field_name: field[:field_name]) do |f|
        f.field_value = field[:field_value]
      end
    end
  end

  puts "  Created SAP '#{sap.name}' with #{sap.sap_controls.count} controls"

  # ── POA&M Document ────────────────────────────────────────────────
  poam = PoamDocument.find_or_create_by!(name: "ACME Cloud Platform — Plan of Action & Milestones") do |d|
    d.file_type        = "json"
    d.status           = "completed"
    d.lifecycle_status  = "in_progress"
    d.poam_version     = "1.0"
    d.oscal_version    = "1.1.2"
    d.system_id        = "acme-cloud-platform"
    d.description      = "DEMO/SAMPLE — Fictional POA&M for testing purposes only."
    d.authorization_boundary = auth_boundary
  end

  POAM_DATA = [
    {
      title: "Multifactor Authentication Not Enforced for All Privileged Users",
      description: "Privileged accounts on legacy admin portal do not require MFA. Emergency access accounts bypass MFA controls.",
      risk_statement:
        "Privileged accounts reachable without a second factor allow a single stolen or guessed credential to yield full administrative control of the system, defeating the account-compromise protections IA-2(1) is relied upon to provide.",
      control_ids: %w[ia-2 ia-2.1],
      risk_status: "remediating",
      impact: "high",
      likelihood: "medium",
      milestone: "Deploy Okta MFA for all privileged accounts",
      milestone_date: Date.new(2026, 4, 30),
      finding_desc: "3PAO testing confirmed 3 of 12 admin accounts lack MFA enrollment."
    },
    {
      title: "Incomplete Audit Log Retention Configuration",
      description: "CloudWatch log groups for application tier set to 90-day retention instead of required 365 days.",
      risk_statement:
        "Audit records aged out before the required retention period leave incidents undetectable and unreconstructable after the fact, undermining the accountability AU-11 depends on and removing the evidence an investigation would need.",
      control_ids: %w[au-11],
      risk_status: "open",
      impact: "medium",
      likelihood: "low",
      milestone: "Update CloudWatch retention policies to 365 days",
      milestone_date: Date.new(2026, 3, 31),
      finding_desc: "Automated scan identified 4 log groups with non-compliant retention."
    },
    {
      title: "Missing Vulnerability Scan Coverage for Container Images",
      description: "Container images in ECR are not scanned for vulnerabilities before deployment to production.",
      risk_statement:
        "Images promoted to production without vulnerability scanning may carry known, exploitable CVEs into the authorization boundary, and the absence of scan evidence prevents RA-5 continuous-monitoring reporting from reflecting true system exposure.",
      control_ids: %w[ra-5 si-3],
      risk_status: "investigating",
      impact: "high",
      likelihood: "high",
      milestone: "Integrate Trivy scanning into CI/CD pipeline",
      milestone_date: Date.new(2026, 5, 15),
      finding_desc: "Assessment team confirmed no container scanning is performed pre-deployment."
    },
    {
      title: "Session Timeout Not Configured for Web Application",
      description: "Web application sessions do not expire after the required 15-minute idle timeout.",
      risk_statement:
        "Sessions that persist beyond the 15-minute idle limit leave authenticated browsers open to hijacking on unattended or shared workstations, extending the window in which an unauthorized user can act as a legitimate one.",
      control_ids: %w[ac-11 sc-10],
      risk_status: "closed",
      impact: "medium",
      likelihood: "medium",
      milestone: "Configure session timeout in application settings",
      milestone_date: Date.new(2026, 1, 15),
      finding_desc: "Verified session timeout now enforced at 15 minutes."
    },
    {
      title: "Encryption Key Rotation Not Automated",
      description: "KMS customer-managed keys for database encryption are rotated manually instead of automatically.",
      risk_statement:
        "Manual key rotation exceeding the 12-month requirement prolongs the period a single compromised key can decrypt stored data, and depends on an operator action that has already been shown to slip.",
      control_ids: %w[sc-12 sc-28],
      risk_status: "deviation-requested",
      impact: "low",
      likelihood: "low",
      milestone: "Enable automatic annual key rotation in AWS KMS",
      milestone_date: Date.new(2026, 6, 30),
      finding_desc: "Key rotation history shows manual rotation every 18 months, exceeding 12-month requirement."
    },
    {
      title: "Incident Response Plan Not Tested in 12 Months",
      description: "The IR plan has not been exercised through tabletop or functional testing within the past year.",
      risk_statement:
        "An untested incident response plan is unproven under load: response times, escalation paths, and contact accuracy remain unverified, so the organization cannot demonstrate it can contain an incident within its stated objectives.",
      control_ids: %w[ir-3],
      risk_status: "remediating",
      impact: "medium",
      likelihood: "low",
      milestone: "Conduct tabletop exercise with all stakeholders",
      milestone_date: Date.new(2026, 4, 15),
      finding_desc: "Last IR exercise was conducted 18 months ago."
    }
  ].freeze

  POAM_DATA.each_with_index do |item_data, idx|
    poam_item = PoamItem.find_or_create_by!(poam_document: poam, title: item_data[:title]) do |pi|
      pi.description    = item_data[:description]
      pi.poam_item_uuid = SecureRandom.uuid
      pi.risk_status    = item_data[:risk_status]
      pi.impact         = item_data[:impact]
      pi.likelihood     = item_data[:likelihood]
      pi.row_order      = idx
    end

    # Create risk
    risk = PoamRisk.find_or_create_by!(poam_document: poam, title: "Risk: #{item_data[:title]}") do |r|
      r.uuid        = SecureRandom.uuid
      r.description = "Risk associated with #{item_data[:title].downcase}."
      # OSCAL REQUIRES risk/statement. It is substantive content describing how
      # the risk affects the system, so it is authored per item here — the
      # exporter must never synthesise it from title/description, which would
      # produce a schema-valid POA&M that misrepresents the risk.
      r.statement   = item_data[:risk_statement]
      r.status      = item_data[:risk_status]
      r.likelihood  = item_data[:likelihood]
      r.impact      = item_data[:impact]
      # #832 REQUIRES a deadline: a POA&M with no time commitment is not a plan,
      # and hdf-cli refuses to convert one. Taken from the item's authored
      # milestone date — the real commitment — rather than invented from "today
      # plus a year", which is precisely the hdf-cli 3.3.2 behaviour we called a
      # bug when it did it.
      r.deadline    = item_data[:milestone_date]
    end

    # OSCAL REQUIRES finding/target: what was assessed, and the resulting state.
    # Anchored to the first control the item cites, with the state derived from
    # the item's real risk status rather than a fixed value.
    finding_target = {
      "type"        => "statement-id",
      "target-id"   => "#{item_data[:control_ids].first}_smt",
      "title"       => "Assessment objective for #{item_data[:control_ids].first.upcase}",
      "description" => item_data[:finding_desc],
      "status"      => {
        "state" => item_data[:risk_status] == "closed" ? "satisfied" : "not-satisfied"
      }
    }

    # Create finding
    finding = PoamFinding.find_or_create_by!(poam_document: poam, title: "Finding: #{item_data[:title]}") do |f|
      f.uuid        = SecureRandom.uuid
      f.description = item_data[:finding_desc]
      f.target_data = finding_target
    end

    # Repair rows seeded before these OSCAL-required fields existed. The blocks
    # above only run on CREATE, so without this a database seeded earlier keeps
    # exporting an invalid POA&M even after the section version is bumped.
    risk.update!(statement: item_data[:risk_statement]) if risk.statement.blank?
    finding.update!(target_data: finding_target) if finding.target_data.blank?

    # Link items to risks and findings
    PoamItemRisk.find_or_create_by!(poam_item: poam_item, poam_risk: risk)
    PoamItemFinding.find_or_create_by!(poam_item: poam_item, poam_finding: finding)
  end

  puts "  Created POA&M '#{poam.name}' with #{poam.poam_items.count} items, #{poam.poam_risks.count} risks"

  # ── CDEF Document ─────────────────────────────────────────────────
  cdef = CdefDocument.find_or_create_by!(name: "ACME Web Application Server — Component Definition") do |d|
    d.file_type        = "json"
    d.cdef_type        = "custom"
    d.cdef_version     = "1.0.0"
    d.status           = "completed"
    d.lifecycle_status  = "published"
    d.description      = "DEMO/SAMPLE — Fictional component definition for testing purposes only. " \
                          "Represents a web application server's security control implementations."
  end

  CDEF_CONTROLS = [
    { control_id: "ac-2",  title: "Account Management",         severity: "high",   narrative: "The web application server implements role-based account management through integration with the organization's centralized identity provider. Account provisioning, modification, and deprovisioning follow automated workflows triggered by HR system events." },
    { control_id: "ac-3",  title: "Access Enforcement",         severity: "high",   narrative: "Access enforcement is implemented through a combination of application-level RBAC and infrastructure-level security groups. All API endpoints require Bearer token authentication with boundary-scoped authorization checks." },
    { control_id: "au-2",  title: "Event Logging",              severity: "medium", narrative: "The application logs all authentication events, authorization decisions, data access operations, and administrative actions. Logs are structured as JSON and forwarded to the centralized logging service." },
    { control_id: "au-3",  title: "Content of Audit Records",   severity: "medium", narrative: "Each audit record includes timestamp, user identity, source IP, action performed, resource affected, and outcome (success/failure). Records conform to the organization's logging schema." },
    { control_id: "ia-2",  title: "Identification and Auth",    severity: "high",   narrative: "User identification and authentication is delegated to the OIDC identity provider (Okta) with phishing-resistant MFA enforcement. Service accounts use short-lived API tokens with SHA-256 digest storage." },
    { control_id: "sc-8",  title: "Transmission Confidentiality", severity: "high", narrative: "All data in transit is protected using TLS 1.2+ with strong cipher suites. Internal service-to-service communication uses mTLS. Certificate validation is enforced on all connections." },
    { control_id: "sc-13", title: "Cryptographic Protection",   severity: "high",   narrative: "The application uses FIPS 140-2 validated cryptographic modules for all cryptographic operations. Key management is handled through AWS KMS with automatic annual rotation." },
    { control_id: "cm-6",  title: "Configuration Settings",     severity: "medium", narrative: "Application configuration follows CIS benchmark recommendations. All settings are managed through version-controlled configuration files with automated drift detection." },
    { control_id: "ir-6",  title: "Incident Reporting",         severity: "medium", narrative: "The application integrates with the organization's incident management system (PagerDuty). Security events above defined thresholds trigger automatic incident creation with appropriate severity classification." },
    { control_id: "si-4",  title: "System Monitoring",          severity: "medium", narrative: "Real-time monitoring is implemented through CloudWatch metrics, application performance monitoring (APM), and behavioral anomaly detection. Alert thresholds are configured for all critical system parameters." }
  ].freeze

  CDEF_CONTROLS.each_with_index do |ctrl, idx|
    cdef_ctrl = CdefControl.find_or_create_by!(cdef_document: cdef, control_id: ctrl[:control_id]) do |c|
      c.title     = ctrl[:title]
      c.severity  = ctrl[:severity]
      c.row_order = idx
    end

    [
      { field_name: "implementation_narrative", field_value: ctrl[:narrative] },
      { field_name: "status", field_value: "implemented" },
      { field_name: "notes", field_value: "Verified during annual assessment." }
    ].each do |field|
      CdefControlField.find_or_create_by!(cdef_control: cdef_ctrl, field_name: field[:field_name]) do |f|
        f.field_value = field[:field_value]
      end
    end
  end

  # Link CDEF to boundary
  prod_boundary = auth_boundary.boundaries.find_by(environment: "production")
  if prod_boundary
    BoundaryCdefDocument.find_or_create_by!(boundary: prod_boundary, cdef_document: cdef)
  end

  puts "  Created CDEF '#{cdef.name}' with #{cdef.cdef_controls.count} controls"

  # ── Profile Document ──────────────────────────────────────────────
  if nist_catalog
    profile = ProfileDocument.find_or_create_by!(name: "ACME Cloud Platform — Moderate Baseline Profile") do |d|
      d.status          = "completed"
      d.lifecycle_status = "published"
      d.baseline_level   = "MODERATE"
      d.profile_version  = "1.0.0"
      d.oscal_version    = "1.1.2"
      d.control_catalog  = nist_catalog
      d.description      = "DEMO/SAMPLE — Fictional moderate baseline profile for testing purposes only. " \
                            "Tailored from NIST SP 800-53 Rev 5 Moderate baseline."
    end

    # Select representative controls across key families (uppercase zero-padded IDs)
    PROFILE_CONTROL_IDS = %w[
      AC-01 AC-02 AC-03 AC-05 AC-06 AC-07 AC-11 AC-17
      AT-02 AT-03
      AU-02 AU-03 AU-06 AU-11 AU-12
      CA-02 CA-07 CA-08
      CM-02 CM-03 CM-06 CM-08
      IA-02 IA-05 IA-08
      IR-01 IR-03 IR-04 IR-06 IR-08
      RA-02 RA-05
      SC-07 SC-08 SC-12 SC-13 SC-28
      SI-03 SI-04 SI-07
    ].freeze

    PROFILE_CONTROL_IDS.each_with_index do |cid, idx|
      catalog_ctrl = nist_catalog.catalog_controls.find_by(control_id: cid)
      next unless catalog_ctrl

      profile_ctrl = ProfileControl.find_or_create_by!(profile_document: profile, control_id: cid) do |c|
        c.title    = catalog_ctrl.title || catalog_ctrl.display_id
        c.priority = %w[P1 P2 P3].sample
        c.row_order = idx
      end

      # Add parameter customizations for controls that have params
      if catalog_ctrl.params_present?
        catalog_ctrl.params_list.first(2).each do |param|
          ProfileControlField.find_or_create_by!(
            profile_control: profile_ctrl,
            field_name: "parameter:#{param['id']}"
          ) do |f|
            f.field_value = "Organization-defined value per ACME security policy"
          end
        end
      end
    end

    puts "  Created Profile '#{profile.name}' with #{profile.profile_controls.count} controls"
  else
    puts "  Skipping Profile — NIST catalog not found"
  end

  puts "  Traditional artifacts complete."
end

# ── FedRAMP 20x Artifacts ─────────────────────────────────────────────
if %w[20x full].include?(mode)
  puts "  Seeding FedRAMP 20x artifacts..."

  ksi_catalog = ControlCatalog.find_by(source: "FedRAMP 20x")
  unless ksi_catalog
    puts "  Skipping — KSI catalog not found. Run KSI seed first."
    return if mode == "20x"
  end

  if ksi_catalog
    # Create KSI validations for the ACME boundary
    ksi_controls = ksi_catalog.catalog_controls.order(:sort_id).limit(15)
    evidences = Evidence.where(authorization_boundary: auth_boundary).to_a

    KSI_VALIDATION_DATA = {
      "ksi-iam-01" => { status: "passed",       method: "automated", notes: "Okta MFA enforced for all users via SPARC_OIDC_FORCE_MFA=true" },
      "ksi-iam-02" => { status: "passed",       method: "automated", notes: "RBAC with boundary-scoped permissions verified" },
      "ksi-iam-03" => { status: "passed",       method: "automated", notes: "Okta SSO integrated via OIDC" },
      "ksi-cm-01"  => { status: "passed",       method: "automated", notes: "Infrastructure-as-code baselines in Terraform" },
      "ksi-cm-02"  => { status: "passed",       method: "automated", notes: "All code in GitHub with branch protection" },
      "ksi-cm-04"  => { status: "passed",       method: "automated", notes: "CI/CD pipeline runs automated tests on every PR" },
      "ksi-mla-01" => { status: "partial",      method: "hybrid",    notes: "CloudWatch centralized, but legacy syslog not forwarded" },
      "ksi-mla-03" => { status: "passed",       method: "automated", notes: "Trivy and CodeQL run weekly via GitHub Actions" },
      "ksi-svc-01" => { status: "passed",       method: "automated", notes: "AES-256 encryption at rest via AWS KMS" },
      "ksi-svc-02" => { status: "passed",       method: "automated", notes: "TLS 1.2+ enforced on all endpoints" },
      "ksi-ir-01"  => { status: "partial",      method: "manual",    notes: "IR plan documented but not tested in 12 months" },
      "ksi-scr-02" => { status: "passed",       method: "automated", notes: "CycloneDX SBOM generated on every build" },
      "ksi-rec-01" => { status: "failed",       method: "manual",    notes: "Backup restore test failed — RTO exceeded by 2 hours" },
      "ksi-edu-01" => { status: "not_assessed", method: nil,         notes: "Training records not yet reviewed" },
      "ksi-pol-02" => { status: "passed",       method: "automated", notes: "AWS Config asset inventory with weekly compliance checks" }
    }.freeze

    validation_count = 0
    KSI_VALIDATION_DATA.each do |ksi_id, data|
      control = ksi_controls.find { |c| c.control_id == ksi_id }
      control ||= ksi_catalog.catalog_controls.find_by(control_id: ksi_id)
      next unless control

      KsiValidation.find_or_create_by!(
        authorization_boundary: auth_boundary,
        catalog_control: control
      ) do |v|
        v.status            = data[:status]
        v.validation_method = data[:method]
        v.notes             = data[:notes]
        v.evidence          = evidences.sample if data[:status] == "passed" && evidences.any?
        v.last_validated_at = data[:status] != "not_assessed" ? rand(1..14).days.ago : nil
        v.next_validation_due = case control.guidance_data&.dig("validation_frequency")
        when "weekly" then 7.days.from_now
        when "quarterly" then 90.days.from_now
        else 30.days.from_now
        end
        v.evidence_format    = data[:method] == "automated" ? "json" : "manual_review"
        v.validation_metadata = { tool: "SPARC CI/CD", scan_id: SecureRandom.hex(8) } if data[:method] == "automated"
      end
      validation_count += 1
    end

    puts "  Created #{validation_count} KSI validations for '#{auth_boundary.name}'"
  end

  puts "  FedRAMP 20x artifacts complete."
end

puts "Done! Sample artifacts seeded (mode: #{mode})."
