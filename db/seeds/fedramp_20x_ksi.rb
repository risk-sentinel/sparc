# FedRAMP 20x Key Security Indicators (KSIs) Catalog Seed
# Source: https://www.fedramp.gov/docs/20x/key-security-indicators/
#
# Stores KSI definitions as CatalogControl records within a ControlCatalog,
# reusing the existing three-level hierarchy: Catalog → Family → Control.
# KSI themes map to ControlFamily, individual KSIs map to CatalogControl.
#
# Run with: bin/rails db:seed

puts "Seeding FedRAMP 20x KSI catalog..."

ksi_catalog = ControlCatalog.find_or_create_by!(name: "FedRAMP 20x Key Security Indicators") do |c|
  c.version     = "1.0.0"
  c.source      = "FedRAMP 20x"
  c.description = "FedRAMP 20x Key Security Indicators (KSIs) — outcome-focused security " \
                  "capabilities replacing traditional control-by-control narrative compliance. " \
                  "Covers Low and Moderate impact levels across 11 security themes."
end

# ── KSI Themes (mapped to ControlFamily) ─────────────────────────────
KSI_THEMES = [
  { code: "AUTH", name: "Authorization by FedRAMP",           sort_order: 1 },
  { code: "CM",   name: "Change Management",                  sort_order: 2 },
  { code: "CNA",  name: "Cloud Native Architecture",          sort_order: 3 },
  { code: "EDU",  name: "Cybersecurity Education",            sort_order: 4 },
  { code: "IAM",  name: "Identity and Access Management",     sort_order: 5 },
  { code: "IR",   name: "Incident Response",                  sort_order: 6 },
  { code: "MLA",  name: "Monitoring, Logging, and Auditing",  sort_order: 7 },
  { code: "POL",  name: "Policy and Inventory",               sort_order: 8 },
  { code: "REC",  name: "Recovery Planning",                  sort_order: 9 },
  { code: "SVC",  name: "Service Configuration",              sort_order: 10 },
  { code: "SCR",  name: "Supply Chain Risk",                  sort_order: 11 }
].freeze

KSI_THEMES.each do |theme|
  ControlFamily.find_or_create_by!(control_catalog: ksi_catalog, code: theme[:code]) do |f|
    f.name       = theme[:name]
    f.sort_order = theme[:sort_order]
  end
end

# ── KSI Indicators (mapped to CatalogControl) ────────────────────────
# Each entry: [theme_code, control_id, title, description, baseline_impact, guidance_data]
#
# baseline_impact: "LOW" = Low only, "LOW, MODERATE" = both
# guidance_data keys: validation_frequency, evidence_type, automation_required

KSI_INDICATORS = [
  # Authorization by FedRAMP (AUTH)
  [ "AUTH", "ksi-auth-01", "Authorization Data Sharing",
    "The CSP shares authorization data with FedRAMP in a structured, machine-readable format.",
    "LOW, MODERATE",
    { validation_frequency: "quarterly", evidence_type: "non-machine", automation_required: false } ],
  [ "AUTH", "ksi-auth-02", "Significant Change Notifications",
    "The CSP notifies FedRAMP of significant changes to the system boundary, architecture, or security posture.",
    "LOW, MODERATE",
    { validation_frequency: "quarterly", evidence_type: "non-machine", automation_required: false } ],
  [ "AUTH", "ksi-auth-03", "Vulnerability Disclosure Program",
    "The CSP maintains a public vulnerability disclosure program for responsible reporting.",
    "LOW, MODERATE",
    { validation_frequency: "quarterly", evidence_type: "non-machine", automation_required: false } ],
  [ "AUTH", "ksi-auth-04", "FedRAMP 20x Compliance Attestation",
    "The CSP attests to ongoing compliance with FedRAMP 20x requirements.",
    "LOW, MODERATE",
    { validation_frequency: "quarterly", evidence_type: "non-machine", automation_required: false } ],

  # Change Management (CM)
  [ "CM", "ksi-cm-01", "Configuration Baseline",
    "The CSP maintains a documented and enforced configuration baseline for all system components.",
    "LOW, MODERATE",
    { validation_frequency: "weekly", evidence_type: "machine", automation_required: true } ],
  [ "CM", "ksi-cm-02", "Version Control",
    "All infrastructure and application code is maintained under version control with audit trails.",
    "LOW, MODERATE",
    { validation_frequency: "weekly", evidence_type: "machine", automation_required: true } ],
  [ "CM", "ksi-cm-03", "Immutable Deployment",
    "System components are deployed using immutable infrastructure patterns where changes require redeployment.",
    "LOW, MODERATE",
    { validation_frequency: "weekly", evidence_type: "machine", automation_required: true } ],
  [ "CM", "ksi-cm-04", "Automated Testing",
    "Changes are validated through automated testing pipelines before deployment to production.",
    "LOW, MODERATE",
    { validation_frequency: "weekly", evidence_type: "machine", automation_required: true } ],
  [ "CM", "ksi-cm-05", "Change Approval Process",
    "A defined change approval process with appropriate separation of duties is enforced.",
    "LOW, MODERATE",
    { validation_frequency: "quarterly", evidence_type: "non-machine", automation_required: false } ],
  [ "CM", "ksi-cm-06", "Rollback Capability",
    "The CSP can roll back to a previous known-good state within a defined recovery time.",
    "LOW, MODERATE",
    { validation_frequency: "quarterly", evidence_type: "non-machine", automation_required: false } ],
  [ "CM", "ksi-cm-07", "Change Impact Analysis",
    "Security impact analysis is performed for all changes before deployment.",
    "LOW, MODERATE",
    { validation_frequency: "quarterly", evidence_type: "non-machine", automation_required: false } ],

  # Cloud Native Architecture (CNA)
  [ "CNA", "ksi-cna-01", "DoS Protection",
    "The system implements denial-of-service protection at network and application layers.",
    "LOW, MODERATE",
    { validation_frequency: "weekly", evidence_type: "machine", automation_required: true } ],
  [ "CNA", "ksi-cna-02", "High Availability",
    "The system is designed for high availability with redundancy across availability zones or regions.",
    "LOW, MODERATE",
    { validation_frequency: "weekly", evidence_type: "machine", automation_required: true } ],
  [ "CNA", "ksi-cna-03", "Container Immutability",
    "Containers are immutable and rebuilt from trusted base images for each deployment.",
    "LOW, MODERATE",
    { validation_frequency: "weekly", evidence_type: "machine", automation_required: true } ],
  [ "CNA", "ksi-cna-04", "Microservices Isolation",
    "Services are isolated with defined network boundaries and least-privilege communication.",
    "LOW, MODERATE",
    { validation_frequency: "weekly", evidence_type: "machine", automation_required: true } ],
  [ "CNA", "ksi-cna-05", "Auto-Scaling",
    "The system automatically scales resources based on demand to maintain availability.",
    "LOW, MODERATE",
    { validation_frequency: "weekly", evidence_type: "machine", automation_required: true } ],

  # Cybersecurity Education (EDU)
  [ "EDU", "ksi-edu-01", "Security Awareness Training",
    "All personnel complete security awareness training upon hire and annually thereafter.",
    "LOW, MODERATE",
    { validation_frequency: "quarterly", evidence_type: "non-machine", automation_required: false } ],
  [ "EDU", "ksi-edu-02", "Role-Based Training",
    "Personnel with security responsibilities receive role-specific training appropriate to their duties.",
    "LOW, MODERATE",
    { validation_frequency: "quarterly", evidence_type: "non-machine", automation_required: false } ],
  [ "EDU", "ksi-edu-03", "Phishing Simulation",
    "The CSP conducts regular phishing simulations and provides remedial training for failures.",
    "LOW, MODERATE",
    { validation_frequency: "quarterly", evidence_type: "non-machine", automation_required: false } ],

  # Identity and Access Management (IAM)
  [ "IAM", "ksi-iam-01", "Phishing-Resistant MFA",
    "All user accounts are protected with phishing-resistant multi-factor authentication.",
    "LOW, MODERATE",
    { validation_frequency: "weekly", evidence_type: "machine", automation_required: true } ],
  [ "IAM", "ksi-iam-02", "Least Privilege Access",
    "Access permissions follow least privilege principles with regular access reviews.",
    "LOW, MODERATE",
    { validation_frequency: "weekly", evidence_type: "machine", automation_required: true } ],
  [ "IAM", "ksi-iam-03", "Centralized Identity",
    "User identities are managed through a centralized identity provider with SSO.",
    "LOW, MODERATE",
    { validation_frequency: "weekly", evidence_type: "machine", automation_required: true } ],
  [ "IAM", "ksi-iam-04", "Privileged Access Management",
    "Privileged accounts use just-in-time access, session recording, and elevated monitoring.",
    "LOW, MODERATE",
    { validation_frequency: "weekly", evidence_type: "machine", automation_required: true } ],
  [ "IAM", "ksi-iam-05", "Service Account Management",
    "Service accounts use short-lived credentials, are inventoried, and have defined owners.",
    "LOW, MODERATE",
    { validation_frequency: "weekly", evidence_type: "machine", automation_required: true } ],

  # Incident Response (IR)
  [ "IR", "ksi-ir-01", "Incident Response Plan",
    "The CSP maintains a tested incident response plan with defined roles, procedures, and communication channels.",
    "LOW, MODERATE",
    { validation_frequency: "quarterly", evidence_type: "non-machine", automation_required: false } ],
  [ "IR", "ksi-ir-02", "Incident Detection and Reporting",
    "Security incidents are detected within defined MTTD targets and reported to FedRAMP within 1 hour.",
    "LOW, MODERATE",
    { validation_frequency: "quarterly", evidence_type: "non-machine", automation_required: false } ],
  [ "IR", "ksi-ir-03", "Incident Recovery",
    "The CSP demonstrates ability to recover from incidents within defined MTTR targets.",
    "LOW, MODERATE",
    { validation_frequency: "quarterly", evidence_type: "non-machine", automation_required: false } ],
  [ "IR", "ksi-ir-04", "Tabletop Exercises",
    "The CSP conducts annual tabletop exercises simulating realistic security incidents.",
    "LOW, MODERATE",
    { validation_frequency: "quarterly", evidence_type: "non-machine", automation_required: false } ],

  # Monitoring, Logging, and Auditing (MLA)
  [ "MLA", "ksi-mla-01", "Centralized Logging",
    "All system components send logs to a centralized, tamper-resistant logging service.",
    "LOW, MODERATE",
    { validation_frequency: "weekly", evidence_type: "machine", automation_required: true } ],
  [ "MLA", "ksi-mla-02", "Log Retention",
    "Logs are retained for a minimum of 12 months with at least 90 days immediately accessible.",
    "LOW, MODERATE",
    { validation_frequency: "weekly", evidence_type: "machine", automation_required: true } ],
  [ "MLA", "ksi-mla-03", "Vulnerability Scanning",
    "Automated vulnerability scanning runs continuously or at least weekly on all components.",
    "LOW, MODERATE",
    { validation_frequency: "weekly", evidence_type: "machine", automation_required: true } ],
  [ "MLA", "ksi-mla-04", "Infrastructure Monitoring",
    "Real-time monitoring of infrastructure health, performance, and security events is operational.",
    "LOW, MODERATE",
    { validation_frequency: "weekly", evidence_type: "machine", automation_required: true } ],
  [ "MLA", "ksi-mla-05", "Alert Response",
    "Security alerts have defined response procedures and SLAs for acknowledgment and resolution.",
    "LOW, MODERATE",
    { validation_frequency: "quarterly", evidence_type: "non-machine", automation_required: false } ],
  [ "MLA", "ksi-mla-06", "Anomaly Detection",
    "Behavioral anomaly detection identifies unusual access patterns and potential threats.",
    "LOW, MODERATE",
    { validation_frequency: "weekly", evidence_type: "machine", automation_required: true } ],
  [ "MLA", "ksi-mla-07", "Penetration Testing",
    "Annual penetration testing is conducted by qualified independent assessors.",
    "LOW, MODERATE",
    { validation_frequency: "quarterly", evidence_type: "non-machine", automation_required: false } ],

  # Policy and Inventory (POL)
  [ "POL", "ksi-pol-01", "Security Policy Documentation",
    "Comprehensive security policies are documented, reviewed annually, and accessible to all personnel.",
    "LOW, MODERATE",
    { validation_frequency: "quarterly", evidence_type: "non-machine", automation_required: false } ],
  [ "POL", "ksi-pol-02", "Asset Inventory",
    "A complete and current inventory of all system assets (hardware, software, data) is maintained.",
    "LOW, MODERATE",
    { validation_frequency: "weekly", evidence_type: "machine", automation_required: true } ],
  [ "POL", "ksi-pol-03", "Data Classification",
    "All data is classified according to sensitivity and handling requirements are enforced.",
    "LOW, MODERATE",
    { validation_frequency: "quarterly", evidence_type: "non-machine", automation_required: false } ],
  [ "POL", "ksi-pol-04", "Acceptable Use Policy",
    "An acceptable use policy is enforced for all users with acknowledgment tracking.",
    "LOW, MODERATE",
    { validation_frequency: "quarterly", evidence_type: "non-machine", automation_required: false } ],

  # Recovery Planning (REC)
  [ "REC", "ksi-rec-01", "Backup Strategy",
    "Critical data and configurations are backed up with defined RPO and verified restore procedures.",
    "LOW, MODERATE",
    { validation_frequency: "weekly", evidence_type: "machine", automation_required: true } ],
  [ "REC", "ksi-rec-02", "Recovery Time Objectives",
    "Defined RTO targets exist for all critical services with demonstrated recovery capability.",
    "LOW, MODERATE",
    { validation_frequency: "quarterly", evidence_type: "non-machine", automation_required: false } ],
  [ "REC", "ksi-rec-03", "Disaster Recovery Testing",
    "DR plans are tested at least annually with documented results and improvement actions.",
    "LOW, MODERATE",
    { validation_frequency: "quarterly", evidence_type: "non-machine", automation_required: false } ],
  [ "REC", "ksi-rec-04", "Business Continuity Plan",
    "A business continuity plan addresses extended outages and is reviewed annually.",
    "LOW, MODERATE",
    { validation_frequency: "quarterly", evidence_type: "non-machine", automation_required: false } ],

  # Service Configuration (SVC)
  [ "SVC", "ksi-svc-01", "Encryption at Rest",
    "All data at rest is encrypted using FIPS 140-validated cryptographic modules.",
    "LOW, MODERATE",
    { validation_frequency: "weekly", evidence_type: "machine", automation_required: true } ],
  [ "SVC", "ksi-svc-02", "Encryption in Transit",
    "All data in transit uses TLS 1.2+ with strong cipher suites and certificate validation.",
    "LOW, MODERATE",
    { validation_frequency: "weekly", evidence_type: "machine", automation_required: true } ],
  [ "SVC", "ksi-svc-03", "Component Integrity",
    "System components are verified for integrity using checksums, signatures, or secure boot.",
    "LOW, MODERATE",
    { validation_frequency: "weekly", evidence_type: "machine", automation_required: true } ],
  [ "SVC", "ksi-svc-04", "Hardened Baselines",
    "All components are deployed from hardened baselines (CIS, DISA STIG, or equivalent).",
    "LOW, MODERATE",
    { validation_frequency: "weekly", evidence_type: "machine", automation_required: true } ],
  [ "SVC", "ksi-svc-05", "Key Management",
    "Cryptographic keys are managed through a dedicated KMS with rotation and access controls.",
    "LOW, MODERATE",
    { validation_frequency: "weekly", evidence_type: "machine", automation_required: true } ],
  [ "SVC", "ksi-svc-06", "Network Segmentation",
    "Network segmentation isolates system components with defined security zones and access rules.",
    "LOW, MODERATE",
    { validation_frequency: "weekly", evidence_type: "machine", automation_required: true } ],
  [ "SVC", "ksi-svc-07", "Endpoint Protection",
    "All endpoints run approved endpoint protection with real-time threat detection.",
    "LOW, MODERATE",
    { validation_frequency: "weekly", evidence_type: "machine", automation_required: true } ],

  # Supply Chain Risk (SCR)
  [ "SCR", "ksi-scr-01", "Third-Party Authorization",
    "Third-party services processing federal data hold current FedRAMP or equivalent authorization.",
    "LOW, MODERATE",
    { validation_frequency: "quarterly", evidence_type: "non-machine", automation_required: false } ],
  [ "SCR", "ksi-scr-02", "Software Bill of Materials",
    "The CSP maintains a current SBOM for all deployed software components.",
    "LOW, MODERATE",
    { validation_frequency: "weekly", evidence_type: "machine", automation_required: true } ],
  [ "SCR", "ksi-scr-03", "Dependency Scanning",
    "Automated dependency scanning identifies known vulnerabilities in third-party libraries.",
    "LOW, MODERATE",
    { validation_frequency: "weekly", evidence_type: "machine", automation_required: true } ],
  [ "SCR", "ksi-scr-04", "Supply Chain Attestation",
    "Key suppliers provide security attestations or evidence of security practices.",
    "LOW, MODERATE",
    { validation_frequency: "quarterly", evidence_type: "non-machine", automation_required: false } ]
].freeze

indicator_count = 0
KSI_INDICATORS.each do |theme_code, control_id, title, description, baseline_impact, guidance|
  family = ControlFamily.find_by!(control_catalog: ksi_catalog, code: theme_code)
  CatalogControl.find_or_create_by!(control_family: family, control_id: control_id) do |cc|
    cc.title           = title
    cc.description     = description
    cc.baseline_impact = baseline_impact
    cc.guidance_data   = guidance
    cc.sort_id         = control_id
    cc.label           = control_id.upcase
  end
  indicator_count += 1
end

puts "  Created #{ksi_catalog.control_families.count} KSI themes"
puts "  Created #{indicator_count} KSI indicators"

# ── KSI-to-NIST 800-53 Rev 5 Mapping ─────────────────────────────────
# Creates a ControlMapping linking KSIs to their corresponding NIST controls.

nist_catalog = ControlCatalog.find_by(name: "NIST SP 800-53 Rev 5")
if nist_catalog
  mapping = ControlMapping.find_or_create_by!(
    name: "FedRAMP 20x KSI to NIST SP 800-53 Rev 5"
  ) do |m|
    m.source_catalog     = ksi_catalog
    m.target_catalog     = nist_catalog
    m.description        = "Maps FedRAMP 20x Key Security Indicators to their corresponding " \
                           "NIST SP 800-53 Rev 5 controls. Relationship type is 'superset' " \
                           "because each KSI encapsulates the intent of multiple NIST controls."
    m.status             = "complete"
    m.method_type        = "human"
    m.matching_rationale = "functional"
    m.mapping_version    = "1.0.0"
  end

  # Representative KSI-to-NIST mappings (each KSI maps to one or more NIST controls)
  KSI_NIST_MAPPINGS = [
    # Change Management
    [ "ksi-cm-01", "cm-2",  "superset" ],
    [ "ksi-cm-01", "cm-6",  "superset" ],
    [ "ksi-cm-02", "cm-3",  "superset" ],
    [ "ksi-cm-03", "cm-3",  "superset" ],
    [ "ksi-cm-03", "sa-10", "intersects" ],
    [ "ksi-cm-04", "sa-11", "superset" ],
    [ "ksi-cm-05", "cm-3",  "superset" ],
    [ "ksi-cm-06", "cp-10", "intersects" ],
    [ "ksi-cm-07", "cm-4",  "superset" ],

    # Cloud Native Architecture
    [ "ksi-cna-01", "sc-5",  "superset" ],
    [ "ksi-cna-02", "cp-6",  "superset" ],
    [ "ksi-cna-02", "cp-7",  "superset" ],
    [ "ksi-cna-03", "cm-2",  "intersects" ],
    [ "ksi-cna-04", "sc-7",  "intersects" ],
    [ "ksi-cna-05", "cp-2",  "intersects" ],

    # Identity and Access Management
    [ "ksi-iam-01", "ia-2",  "superset" ],
    [ "ksi-iam-02", "ac-6",  "superset" ],
    [ "ksi-iam-02", "ac-2",  "intersects" ],
    [ "ksi-iam-03", "ia-2",  "intersects" ],
    [ "ksi-iam-03", "ia-8",  "intersects" ],
    [ "ksi-iam-04", "ac-6",  "intersects" ],
    [ "ksi-iam-05", "ia-5",  "intersects" ],

    # Monitoring, Logging, and Auditing
    [ "ksi-mla-01", "au-6",  "superset" ],
    [ "ksi-mla-01", "au-2",  "intersects" ],
    [ "ksi-mla-02", "au-11", "superset" ],
    [ "ksi-mla-03", "ra-5",  "superset" ],
    [ "ksi-mla-04", "si-4",  "superset" ],
    [ "ksi-mla-05", "ir-6",  "intersects" ],
    [ "ksi-mla-06", "si-4",  "intersects" ],
    [ "ksi-mla-07", "ca-8",  "superset" ],

    # Incident Response
    [ "ksi-ir-01", "ir-1",  "superset" ],
    [ "ksi-ir-01", "ir-8",  "superset" ],
    [ "ksi-ir-02", "ir-6",  "superset" ],
    [ "ksi-ir-03", "ir-4",  "superset" ],
    [ "ksi-ir-04", "ir-3",  "superset" ],

    # Service Configuration
    [ "ksi-svc-01", "sc-28", "superset" ],
    [ "ksi-svc-02", "sc-8",  "superset" ],
    [ "ksi-svc-02", "sc-13", "intersects" ],
    [ "ksi-svc-03", "si-7",  "superset" ],
    [ "ksi-svc-04", "cm-6",  "superset" ],
    [ "ksi-svc-05", "sc-12", "superset" ],
    [ "ksi-svc-06", "sc-7",  "superset" ],
    [ "ksi-svc-07", "si-3",  "superset" ],

    # Supply Chain Risk
    [ "ksi-scr-01", "sa-9",  "superset" ],
    [ "ksi-scr-02", "sr-4",  "superset" ],
    [ "ksi-scr-03", "ra-5",  "intersects" ],
    [ "ksi-scr-04", "sr-6",  "superset" ],

    # Recovery Planning
    [ "ksi-rec-01", "cp-9",  "superset" ],
    [ "ksi-rec-02", "cp-2",  "intersects" ],
    [ "ksi-rec-03", "cp-4",  "superset" ],
    [ "ksi-rec-04", "cp-2",  "superset" ],

    # Policy and Inventory
    [ "ksi-pol-01", "pl-1",  "superset" ],
    [ "ksi-pol-02", "cm-8",  "superset" ],
    [ "ksi-pol-03", "ra-2",  "superset" ],
    [ "ksi-pol-04", "pl-4",  "superset" ],

    # Education
    [ "ksi-edu-01", "at-2",  "superset" ],
    [ "ksi-edu-02", "at-3",  "superset" ],
    [ "ksi-edu-03", "at-2",  "intersects" ],

    # Authorization
    [ "ksi-auth-01", "ca-7", "intersects" ],
    [ "ksi-auth-02", "cm-3", "intersects" ],
    [ "ksi-auth-03", "si-5", "intersects" ],
    [ "ksi-auth-04", "ca-6", "intersects" ]
  ].freeze

  mapping_count = 0
  KSI_NIST_MAPPINGS.each_with_index do |(source_id, target_id, relationship), idx|
    ControlMappingEntry.find_or_create_by!(
      control_mapping: mapping,
      source_control_id: source_id,
      target_control_id: target_id
    ) do |entry|
      entry.relationship = relationship
      entry.source_type  = "control"
      entry.target_type  = "control"
      entry.row_order    = idx
    end
    mapping_count += 1
  end

  puts "  Created KSI-to-NIST mapping with #{mapping_count} entries"
else
  puts "  NIST SP 800-53 Rev 5 catalog not found — skipping KSI-to-NIST mapping"
end

puts "Done! FedRAMP 20x KSI catalog seeded."
