# Idempotent seed for NIST SP 800-53 Rev 5 Control Catalog
# Run with: bin/rails db:seed

puts "Seeding NIST SP 800-53 Rev 5 catalog..."

catalog = ControlCatalog.find_or_create_by!(name: "NIST SP 800-53 Rev 5") do |c|
  c.version     = "5.1.1"
  c.source      = "NIST"
  c.description = "Security and Privacy Controls for Information Systems and Organizations. " \
                  "Published by the National Institute of Standards and Technology."
end

NIST_FAMILIES = [
  { code: "AC", name: "Access Control",                              sort_order: 1 },
  { code: "AT", name: "Awareness and Training",                      sort_order: 2 },
  { code: "AU", name: "Audit and Accountability",                    sort_order: 3 },
  { code: "CA", name: "Assessment, Authorization, and Monitoring",   sort_order: 4 },
  { code: "CM", name: "Configuration Management",                    sort_order: 5 },
  { code: "CP", name: "Contingency Planning",                        sort_order: 6 },
  { code: "IA", name: "Identification and Authentication",           sort_order: 7 },
  { code: "IR", name: "Incident Response",                           sort_order: 8 },
  { code: "MA", name: "Maintenance",                                 sort_order: 9 },
  { code: "MP", name: "Media Protection",                            sort_order: 10 },
  { code: "PE", name: "Physical and Environmental Protection",       sort_order: 11 },
  { code: "PL", name: "Planning",                                    sort_order: 12 },
  { code: "PM", name: "Program Management",                          sort_order: 13 },
  { code: "PS", name: "Personnel Security",                          sort_order: 14 },
  { code: "PT", name: "PII Processing and Transparency",            sort_order: 15 },
  { code: "RA", name: "Risk Assessment",                             sort_order: 16 },
  { code: "SA", name: "System and Services Acquisition",            sort_order: 17 },
  { code: "SC", name: "System and Communications Protection",       sort_order: 18 },
  { code: "SI", name: "System and Information Integrity",           sort_order: 19 },
  { code: "SR", name: "Supply Chain Risk Management",               sort_order: 20 }
].freeze

# Base controls data: { family_code => [ [control_num, title, priority, baseline] ] }
# baseline: L=Low, M=Moderate, H=High  (e.g. "L M H" means included in all three)
NIST_CONTROLS = {
  "AC" => [
    [ 1,  "Policy and Procedures",                                        "P1", "L M H" ],
    [ 2,  "Account Management",                                           "P1", "L M H" ],
    [ 3,  "Access Enforcement",                                           "P1", "L M H" ],
    [ 4,  "Information Flow Enforcement",                                 "P1", "M H" ],
    [ 5,  "Separation of Duties",                                         "P1", "M H" ],
    [ 6,  "Least Privilege",                                              "P1", "M H" ],
    [ 7,  "Unsuccessful Logon Attempts",                                  "P2", "L M H" ],
    [ 8,  "System Use Notification",                                      "P2", "L M H" ],
    [ 9,  "Previous Logon Notification",                                  "P0", "" ],
    [ 10, "Concurrent Session Control",                                   "P2", "M H" ],
    [ 11, "Device Lock",                                                  "P2", "M H" ],
    [ 12, "Session Termination",                                          "P2", "M H" ],
    [ 13, "Withdrawn",                                                    "P0", "" ],
    [ 14, "Permitted Actions Without Identification or Authentication",   "P3", "L M H" ],
    [ 15, "Automated Remote Access Management",                           "P1", "M H" ],
    [ 16, "Security and Privacy Attributes",                              "P2", "M H" ],
    [ 17, "Remote Access",                                                "P1", "L M H" ],
    [ 18, "Wireless Access",                                              "P1", "L M H" ],
    [ 19, "Access Control for Mobile Devices",                           "P1", "M H" ],
    [ 20, "Use of External Systems",                                      "P1", "L M H" ],
    [ 21, "Permitted Actions Without Identification or Authentication",   "P3", "L M H" ],
    [ 22, "Controlled Release",                                           "P1", "M H" ],
    [ 23, "Data Mining Protection",                                       "P0", "" ],
    [ 24, "Access Control Decisions",                                     "P0", "" ],
    [ 25, "Reference Monitor",                                            "P0", "" ]
  ],
  "AT" => [
    [ 1, "Policy and Procedures",                               "P1", "L M H" ],
    [ 2, "Literacy Training and Awareness",                     "P1", "L M H" ],
    [ 3, "Role-Based Training",                                 "P1", "M H" ],
    [ 4, "Training Records",                                    "P3", "M H" ],
    [ 5, "Contacts with Security Groups and Associations",      "P3", "" ],
    [ 6, "Training Feedback",                                   "P2", "M H" ]
  ],
  "AU" => [
    [ 1,  "Policy and Procedures",                          "P1", "L M H" ],
    [ 2,  "Event Logging",                                  "P1", "L M H" ],
    [ 3,  "Content of Audit Records",                       "P1", "L M H" ],
    [ 4,  "Audit Log Storage Capacity",                     "P1", "L M H" ],
    [ 5,  "Response to Audit Logging Process Failures",     "P1", "M H" ],
    [ 6,  "Audit Record Review, Analysis, and Reporting",   "P1", "L M H" ],
    [ 7,  "Audit Record Reduction and Report Generation",   "P2", "M H" ],
    [ 8,  "Time Stamps",                                    "P1", "L M H" ],
    [ 9,  "Protection of Audit Information",                "P1", "L M H" ],
    [ 10, "Audit Record Retention",                         "P3", "L M H" ],
    [ 11, "Audit Record Generation",                        "P1", "L M H" ],
    [ 12, "Audit Record Generation — Protection",           "P1", "H" ],
    [ 13, "Monitoring for Information Disclosure",          "P0", "" ],
    [ 14, "Session Audit",                                  "P0", "" ],
    [ 15, "Non-Repudiation",                                "P0", "" ],
    [ 16, "Protecting Audit Information",                   "P0", "" ]
  ],
  "CA" => [
    [ 1, "Policy and Procedures",                                    "P1", "L M H" ],
    [ 2, "Control Assessments",                                      "P2", "L M H" ],
    [ 3, "Information Exchange",                                     "P1", "L M H" ],
    [ 4, "Withdrawn",                                                "P0", "" ],
    [ 5, "Plan of Action and Milestones",                            "P3", "L M H" ],
    [ 6, "Authorization",                                            "P2", "L M H" ],
    [ 7, "Continuous Monitoring",                                    "P1", "L M H" ],
    [ 8, "Penetration Testing",                                      "P2", "H" ],
    [ 9, "Internal System Connections",                              "P2", "L M H" ]
  ],
  "CM" => [
    [ 1,  "Policy and Procedures",                      "P1", "L M H" ],
    [ 2,  "Baseline Configuration",                     "P1", "L M H" ],
    [ 3,  "Configuration Change Control",               "P1", "M H" ],
    [ 4,  "Security and Privacy Impact Analysis",       "P2", "L M H" ],
    [ 5,  "Access Restrictions for Change",             "P1", "M H" ],
    [ 6,  "Configuration Settings",                     "P1", "L M H" ],
    [ 7,  "Least Functionality",                        "P1", "L M H" ],
    [ 8,  "System Component Inventory",                 "P1", "L M H" ],
    [ 9,  "Configuration Management Plan",              "P1", "M H" ],
    [ 10, "Software Usage Restrictions",                "P2", "L M H" ],
    [ 11, "User-Installed Software",                    "P1", "M H" ],
    [ 12, "Information Location",                       "P1", "L M H" ],
    [ 13, "Data Action Mapping",                        "P0", "" ],
    [ 14, "Signed Components",                          "P0", "" ]
  ],
  "CP" => [
    [ 1,  "Policy and Procedures",                              "P1", "L M H" ],
    [ 2,  "Contingency Plan",                                   "P1", "L M H" ],
    [ 3,  "Contingency Training",                               "P2", "L M H" ],
    [ 4,  "Contingency Plan Testing",                           "P2", "L M H" ],
    [ 5,  "Withdrawn",                                          "P0", "" ],
    [ 6,  "Alternate Storage Site",                             "P1", "M H" ],
    [ 7,  "Alternate Processing Site",                          "P1", "H" ],
    [ 8,  "Telecommunications Services",                        "P1", "M H" ],
    [ 9,  "System Backup",                                      "P1", "L M H" ],
    [ 10, "System Recovery and Reconstitution",                 "P1", "L M H" ],
    [ 11, "Alternate Communications Protocols",                 "P0", "" ],
    [ 12, "Safe Mode",                                          "P0", "" ],
    [ 13, "Data Protection",                                    "P0", "" ]
  ],
  "IA" => [
    [ 1,  "Policy and Procedures",                                        "P1", "L M H" ],
    [ 2,  "Identification and Authentication (Organizational Users)",     "P1", "L M H" ],
    [ 3,  "Device Identification and Authentication",                     "P1", "M H" ],
    [ 4,  "Identifier Management",                                        "P1", "L M H" ],
    [ 5,  "Authenticator Management",                                     "P1", "L M H" ],
    [ 6,  "Authentication Feedback",                                      "P2", "L M H" ],
    [ 7,  "Cryptographic Module Authentication",                          "P1", "L M H" ],
    [ 8,  "Identification and Authentication (Non-Organizational Users)", "P1", "M H" ],
    [ 9,  "Service Identification and Authentication",                    "P1", "H" ],
    [ 10, "Adaptive Authentication",                                      "P0", "" ],
    [ 11, "Re-Authentication",                                            "P2", "M H" ],
    [ 12, "Identity Proofing",                                            "P1", "M H" ],
    [ 13, "Identity Proofing and Re-Authentication",                      "P0", "" ]
  ],
  "IR" => [
    [ 1,  "Policy and Procedures",                  "P1", "L M H" ],
    [ 2,  "Incident Response Training",             "P2", "L M H" ],
    [ 3,  "Incident Response Testing",              "P2", "M H" ],
    [ 4,  "Incident Handling",                      "P1", "L M H" ],
    [ 5,  "Incident Monitoring",                    "P1", "L M H" ],
    [ 6,  "Incident Reporting",                     "P1", "L M H" ],
    [ 7,  "Incident Response Assistance",           "P2", "L M H" ],
    [ 8,  "Incident Response Plan",                 "P1", "L M H" ],
    [ 9,  "Incident Information Sharing",           "P2", "M H" ],
    [ 10, "Supply Chain Coordination",              "P0", "" ]
  ],
  "MA" => [
    [ 1, "Policy and Procedures",                           "P1", "L M H" ],
    [ 2, "Controlled Maintenance",                          "P2", "L M H" ],
    [ 3, "Maintenance Tools",                               "P2", "M H" ],
    [ 4, "Nonlocal Maintenance",                            "P2", "L M H" ],
    [ 5, "Maintenance Personnel",                           "P2", "L M H" ],
    [ 6, "Timely Maintenance",                              "P2", "M H" ],
    [ 7, "Field Maintenance",                               "P0", "" ]
  ],
  "MP" => [
    [ 1, "Policy and Procedures",               "P1", "L M H" ],
    [ 2, "Media Access",                         "P1", "L M H" ],
    [ 3, "Media Marking",                        "P2", "M H" ],
    [ 4, "Media Storage",                        "P1", "M H" ],
    [ 5, "Media Transport",                      "P1", "M H" ],
    [ 6, "Media Sanitization",                   "P1", "L M H" ],
    [ 7, "Media Use",                            "P1", "M H" ],
    [ 8, "Media Downgrading",                    "P0", "" ]
  ],
  "PE" => [
    [ 1,  "Policy and Procedures",                          "P1", "L M H" ],
    [ 2,  "Physical Access Authorizations",                 "P1", "L M H" ],
    [ 3,  "Physical Access Control",                        "P1", "L M H" ],
    [ 4,  "Access Control for Transmission",                "P1", "M H" ],
    [ 5,  "Access Control for Output Devices",              "P2", "M H" ],
    [ 6,  "Monitoring Physical Access",                     "P1", "L M H" ],
    [ 7,  "Visitor Control",                                "P2", "L M H" ],
    [ 8,  "Access Records",                                 "P3", "L M H" ],
    [ 9,  "Power Equipment and Cabling",                    "P1", "H" ],
    [ 10, "Emergency Shutoff",                              "P1", "M H" ],
    [ 11, "Emergency Power",                                "P1", "M H" ],
    [ 12, "Emergency Lighting",                             "P1", "L M H" ],
    [ 13, "Fire Protection",                                "P1", "L M H" ],
    [ 14, "Environmental Controls",                         "P1", "L M H" ],
    [ 15, "Water Damage Protection",                        "P1", "L M H" ],
    [ 16, "Delivery and Removal",                           "P2", "M H" ],
    [ 17, "Alternate Work Site",                            "P2", "M H" ],
    [ 18, "Location of System Components",                  "P2", "H" ],
    [ 19, "Information Leakage",                            "P0", "" ],
    [ 20, "Asset Monitoring and Tracking",                  "P0", "" ],
    [ 21, "Electromagnetic Pulse Protection",               "P0", "" ],
    [ 22, "Component Marking",                              "P0", "" ],
    [ 23, "Facility Location",                              "P0", "" ]
  ],
  "PL" => [
    [ 1,  "Policy and Procedures",                  "P1", "L M H" ],
    [ 2,  "System Security and Privacy Plans",      "P1", "L M H" ],
    [ 3,  "System Security and Privacy Plans — Update", "P2", "L M H" ],
    [ 4,  "Rules of Behavior",                      "P2", "L M H" ],
    [ 5,  "Withdrawn",                              "P0", "" ],
    [ 6,  "Withdrawn",                              "P0", "" ],
    [ 7,  "Concept of Operations",                  "P0", "" ],
    [ 8,  "Security and Privacy Architectures",     "P1", "M H" ],
    [ 9,  "Central Management",                     "P0", "" ],
    [ 10, "Baseline Selection",                     "P0", "" ],
    [ 11, "Baseline Tailoring",                     "P0", "" ]
  ],
  "PM" => [
    [ 1,  "Information Security Program Plan",                          "P1", "" ],
    [ 2,  "Information Security Program Leadership Role",               "P1", "" ],
    [ 3,  "Information Security Resources",                             "P1", "" ],
    [ 4,  "Plan of Action and Milestones Process",                      "P1", "" ],
    [ 5,  "System Inventory",                                           "P1", "" ],
    [ 6,  "Information Security Measures of Performance",               "P1", "" ],
    [ 7,  "Enterprise Architecture",                                    "P1", "" ],
    [ 8,  "Critical Infrastructure Plan",                               "P1", "" ],
    [ 9,  "Risk Management Strategy",                                   "P1", "" ],
    [ 10, "Authorization Process",                                      "P1", "" ],
    [ 11, "Mission and Business Process Definition",                    "P1", "" ],
    [ 12, "Insider Threat Program",                                     "P1", "" ],
    [ 13, "Information Security Workforce",                             "P1", "" ],
    [ 14, "Testing, Training, and Monitoring",                          "P1", "" ],
    [ 15, "Security and Privacy Groups and Associations",               "P2", "" ],
    [ 16, "Threat Awareness Program",                                   "P1", "" ],
    [ 17, "Coordinating with Sanctioning Authority",                    "P0", "" ],
    [ 18, "Privacy Program Plan",                                       "P1", "" ],
    [ 19, "Privacy Program Leadership Role",                            "P1", "" ],
    [ 20, "Dissemination of Privacy Program Information",               "P1", "" ],
    [ 21, "Information Sharing",                                        "P1", "" ],
    [ 22, "Accountability, Audit, and Risk Management",                 "P1", "" ],
    [ 23, "Reporting",                                                  "P1", "" ],
    [ 24, "Data Quality Management",                                    "P1", "" ],
    [ 25, "Data Integrity Board",                                       "P1", "" ],
    [ 26, "Data Management Board",                                      "P0", "" ],
    [ 27, "Event Logging",                                              "P1", "" ],
    [ 28, "System of Records Notice",                                   "P1", "" ],
    [ 29, "Privacy Notice",                                             "P1", "" ],
    [ 30, "Consent",                                                    "P1", "" ],
    [ 31, "Consent Directives",                                         "P0", "" ],
    [ 32, "Computer Matching Requirements",                             "P1", "" ]
  ],
  "PS" => [
    [ 1, "Policy and Procedures",                   "P1", "L M H" ],
    [ 2, "Position Risk Designation",               "P1", "L M H" ],
    [ 3, "Personnel Screening",                     "P1", "L M H" ],
    [ 4, "Personnel Termination",                   "P1", "L M H" ],
    [ 5, "Personnel Transfer",                      "P2", "L M H" ],
    [ 6, "Access Agreements",                       "P3", "L M H" ],
    [ 7, "External Personnel Security",             "P1", "L M H" ],
    [ 8, "Personnel Sanctions",                     "P3", "L M H" ],
    [ 9, "Position Descriptions",                   "P0", "" ]
  ],
  "PT" => [
    [ 1, "Policy and Procedures",                                     "P1", "L M H" ],
    [ 2, "Authority to Process Personally Identifiable Information",  "P1", "L M H" ],
    [ 3, "Personally Identifiable Information Processing Purposes",   "P1", "L M H" ],
    [ 4, "Consent",                                                   "P1", "L M H" ],
    [ 5, "Privacy Notice",                                            "P1", "L M H" ],
    [ 6, "System of Records Notice",                                  "P1", "L M H" ],
    [ 7, "Specific Categories of Personally Identifiable Information", "P1", "L M H" ],
    [ 8, "Computer Matching Requirements",                            "P1", "L M H" ]
  ],
  "RA" => [
    [ 1,  "Policy and Procedures",                  "P1", "L M H" ],
    [ 2,  "Security Categorization",                "P1", "L M H" ],
    [ 3,  "Risk Assessment",                        "P1", "L M H" ],
    [ 4,  "Withdrawn",                              "P0", "" ],
    [ 5,  "Vulnerability Monitoring and Scanning",  "P1", "L M H" ],
    [ 6,  "Technical Surveillance Countermeasures", "P0", "" ],
    [ 7,  "Risk Response",                          "P1", "L M H" ],
    [ 8,  "Privacy Impact Assessment",              "P1", "L M H" ],
    [ 9,  "Criticality Analysis",                   "P0", "" ],
    [ 10, "Supply Chain Risk Assessment",           "P1", "M H" ]
  ],
  "SA" => [
    [ 1,  "Policy and Procedures",                                     "P1", "L M H" ],
    [ 2,  "Allocation of Resources",                                   "P1", "L M H" ],
    [ 3,  "System Development Life Cycle",                             "P1", "L M H" ],
    [ 4,  "Acquisition Process",                                       "P1", "L M H" ],
    [ 5,  "System Documentation",                                      "P2", "L M H" ],
    [ 6,  "Withdrawn",                                                 "P0", "" ],
    [ 7,  "Withdrawn",                                                 "P0", "" ],
    [ 8,  "Security and Privacy Engineering Principles",               "P1", "L M H" ],
    [ 9,  "External System Services",                                  "P1", "L M H" ],
    [ 10, "Developer Configuration Management",                        "P1", "M H" ],
    [ 11, "Developer Testing and Evaluation",                          "P1", "M H" ],
    [ 12, "Developer Implementation, Testing, and Evaluation",         "P0", "" ],
    [ 13, "Supply Chain Protection",                                   "P1", "H" ],
    [ 14, "Trustworthiness",                                           "P0", "" ],
    [ 15, "Development Process, Standards, and Tools",                 "P2", "M H" ],
    [ 16, "Developer-Provided Training",                               "P0", "" ],
    [ 17, "Developer Security and Privacy Architecture and Design",    "P1", "H" ],
    [ 18, "Tamper Resistance and Detection",                           "P0", "" ],
    [ 19, "Component Authenticity",                                    "P1", "M H" ],
    [ 20, "Customized Development of Critical Components",             "P0", "" ],
    [ 21, "Developer Screening",                                       "P0", "" ],
    [ 22, "Unsupported System Components",                             "P1", "L M H" ],
    [ 23, "Controlled Use of Interfaces",                              "P0", "" ]
  ],
  "SC" => [
    [ 1,  "Policy and Procedures",                                "P1", "L M H" ],
    [ 2,  "Separation of System and User Functionality",          "P1", "M H" ],
    [ 3,  "Security Function Isolation",                          "P1", "H" ],
    [ 4,  "Information in Shared System Resources",               "P1", "M H" ],
    [ 5,  "Denial-of-Service Protection",                         "P1", "M H" ],
    [ 6,  "Withdrawn",                                            "P0", "" ],
    [ 7,  "Boundary Protection",                                  "P1", "L M H" ],
    [ 8,  "Transmission Confidentiality and Integrity",           "P1", "M H" ],
    [ 9,  "Withdrawn",                                            "P0", "" ],
    [ 10, "Network Disconnect",                                   "P2", "M H" ],
    [ 11, "Withdrawn",                                            "P0", "" ],
    [ 12, "Cryptographic Key Establishment and Management",       "P1", "M H" ],
    [ 13, "Cryptographic Protection",                             "P1", "M H" ],
    [ 14, "Withdrawn",                                            "P0", "" ],
    [ 15, "Withdrawn",                                            "P0", "" ],
    [ 16, "Secure Name/Address Resolution Service",               "P1", "L M H" ],
    [ 17, "Secure Name/Address Resolution Service (Recursive or Caching Resolver)", "P1", "L M H" ],
    [ 18, "Architecture and Provisioning for Name/Address Resolution Service", "P1", "H" ],
    [ 19, "Session Authenticity",                                 "P1", "M H" ],
    [ 20, "Protection of Information at Rest",                    "P1", "M H" ],
    [ 21, "Withdrawn",                                            "P0", "" ],
    [ 22, "Withdrawn",                                            "P0", "" ],
    [ 23, "Withdrawn",                                            "P0", "" ],
    [ 24, "Withdrawn",                                            "P0", "" ],
    [ 25, "Thin Nodes",                                           "P0", "" ],
    [ 26, "Honeypots",                                            "P0", "" ],
    [ 27, "Platform-Independent Applications",                    "P0", "" ],
    [ 28, "Application Partitioning",                             "P0", "" ],
    [ 29, "Heterogeneity",                                        "P0", "" ],
    [ 30, "Concealment and Misdirection",                         "P0", "" ],
    [ 31, "Covert Channel Analysis",                              "P0", "" ],
    [ 32, "Information System Partitioning",                      "P0", "" ],
    [ 33, "Withdrawn",                                            "P0", "" ],
    [ 34, "Non-Modifiable Executable Programs",                   "P0", "" ],
    [ 35, "Honeyclients",                                         "P0", "" ],
    [ 36, "Distributed Processing and Storage",                   "P0", "" ],
    [ 37, "Out-of-Band Channels",                                 "P0", "" ],
    [ 38, "Operations Security",                                  "P0", "" ],
    [ 39, "Process Isolation",                                    "P1", "H" ],
    [ 40, "Withdrawn",                                            "P0", "" ],
    [ 41, "Withdrawn",                                            "P0", "" ],
    [ 42, "Withdrawn",                                            "P0", "" ],
    [ 43, "Usage Restrictions",                                   "P0", "" ],
    [ 44, "Detonation Chambers",                                  "P0", "" ],
    [ 45, "System Time Synchronization",                          "P0", "" ],
    [ 46, "Cross Domain Policy Enforcement",                      "P0", "" ],
    [ 47, "Redundancy",                                           "P0", "" ],
    [ 48, "Sensors",                                              "P0", "" ],
    [ 49, "Hardware-Based Protection",                            "P0", "" ],
    [ 50, "Software-Enforced Separation and Policy Enforcement",  "P0", "" ],
    [ 51, "Physical Machine Separation",                          "P0", "" ]
  ],
  "SI" => [
    [ 1,  "Policy and Procedures",                              "P1", "L M H" ],
    [ 2,  "Flaw Remediation",                                   "P1", "L M H" ],
    [ 3,  "Malicious Code Protection",                          "P1", "L M H" ],
    [ 4,  "System Monitoring",                                  "P1", "L M H" ],
    [ 5,  "Security Alerts, Advisories, and Directives",        "P1", "L M H" ],
    [ 6,  "Security and Privacy Function Verification",         "P1", "H" ],
    [ 7,  "Software, Firmware, and Information Integrity",      "P1", "M H" ],
    [ 8,  "Spam Protection",                                    "P2", "M H" ],
    [ 9,  "Withdrawn",                                          "P0", "" ],
    [ 10, "Information Input Restrictions",                     "P1", "M H" ],
    [ 11, "Information Management and Retention",               "P2", "L M H" ],
    [ 12, "Memory Protection",                                  "P1", "H" ],
    [ 13, "Withdrawn",                                          "P0", "" ],
    [ 14, "Non-Persistence",                                    "P0", "" ],
    [ 15, "Information Output Filtering",                       "P0", "" ],
    [ 16, "Memory Protection",                                  "P0", "" ],
    [ 17, "Fail-Safe Procedures",                               "P0", "" ],
    [ 18, "Operations Security",                                "P0", "" ],
    [ 19, "De-Identification",                                  "P0", "" ],
    [ 20, "Tainting",                                           "P0", "" ],
    [ 21, "Information Disposal",                               "P0", "" ],
    [ 22, "Concealment",                                        "P0", "" ],
    [ 23, "Sensor Capability and Data",                         "P0", "" ]
  ],
  "SR" => [
    [ 1,  "Policy and Procedures",                              "P1", "L M H" ],
    [ 2,  "Supply Chain Risk Management Plan",                  "P1", "M H" ],
    [ 3,  "Supply Chain Controls and Processes",                "P1", "M H" ],
    [ 4,  "Provenance",                                         "P1", "H" ],
    [ 5,  "Acquisition Strategies, Tools, and Methods",         "P1", "M H" ],
    [ 6,  "Supplier Assessments and Reviews",                   "P1", "M H" ],
    [ 7,  "Supply Chain Operations Security",                   "P1", "M H" ],
    [ 8,  "Notification Agreements",                            "P1", "M H" ],
    [ 9,  "Tamper Resistance and Detection",                    "P1", "H" ],
    [ 10, "Inspection of Systems or Components",                "P1", "H" ],
    [ 11, "Component Authenticity",                             "P1", "M H" ],
    [ 12, "Component Disposal",                                 "P1", "M H" ]
  ]
}.freeze

total_families = 0
total_controls = 0

NIST_FAMILIES.each do |family_attrs|
  family = ControlFamily.find_or_create_by!(
    control_catalog: catalog,
    code: family_attrs[:code]
  ) do |f|
    f.name       = family_attrs[:name]
    f.sort_order = family_attrs[:sort_order]
  end
  # Update name/sort_order in case it changed
  family.update!(name: family_attrs[:name], sort_order: family_attrs[:sort_order])
  total_families += 1

  controls_for_family = NIST_CONTROLS[family_attrs[:code]] || []
  controls_for_family.each do |num, title, priority, baseline|
    control_id = "#{family_attrs[:code]}-#{num.to_s.rjust(2, '0')}"
    entry = CatalogControl.find_or_create_by!(
      control_family: family,
      control_id: control_id
    ) do |c|
      c.title           = title
      c.priority        = priority
      c.baseline_impact = baseline.present? ? baseline : nil
    end
    entry.update!(title: title, priority: priority, baseline_impact: baseline.present? ? baseline : nil)
    total_controls += 1
  end
end

puts "  Created/updated #{total_families} control families"
puts "  Created/updated #{total_controls} catalog controls"
puts "Done! NIST SP 800-53 Rev 5 catalog is ready."

# ---------------------------------------------------------------------------
# NIST SP 800-53 Rev 4
# ---------------------------------------------------------------------------
puts "\nSeeding NIST SP 800-53 Rev 4 catalog..."

catalog_r4 = ControlCatalog.find_or_create_by!(name: "NIST SP 800-53 Rev 4") do |c|
  c.version     = "4.0"
  c.source      = "NIST"
  c.description = "Security and Privacy Controls for Federal Information Systems and Organizations. " \
                  "Published by the National Institute of Standards and Technology (superseded by Rev 5)."
end

NIST_R4_FAMILIES = [
  { code: "AC", name: "Access Control",                          sort_order: 1 },
  { code: "AT", name: "Awareness and Training",                  sort_order: 2 },
  { code: "AU", name: "Audit and Accountability",                sort_order: 3 },
  { code: "CA", name: "Security Assessment and Authorization",   sort_order: 4 },
  { code: "CM", name: "Configuration Management",                sort_order: 5 },
  { code: "CP", name: "Contingency Planning",                    sort_order: 6 },
  { code: "IA", name: "Identification and Authentication",       sort_order: 7 },
  { code: "IR", name: "Incident Response",                       sort_order: 8 },
  { code: "MA", name: "Maintenance",                             sort_order: 9 },
  { code: "MP", name: "Media Protection",                        sort_order: 10 },
  { code: "PE", name: "Physical and Environmental Protection",   sort_order: 11 },
  { code: "PL", name: "Planning",                                sort_order: 12 },
  { code: "PM", name: "Program Management",                      sort_order: 13 },
  { code: "PS", name: "Personnel Security",                      sort_order: 14 },
  { code: "RA", name: "Risk Assessment",                         sort_order: 15 },
  { code: "SA", name: "System and Services Acquisition",        sort_order: 16 },
  { code: "SC", name: "System and Communications Protection",   sort_order: 17 },
  { code: "SI", name: "System and Information Integrity",       sort_order: 18 }
].freeze

NIST_R4_CONTROLS = {
  "AC" => [
    [ 1,  "Access Control Policy and Procedures",                              "P1", "L M H" ],
    [ 2,  "Account Management",                                                "P1", "L M H" ],
    [ 3,  "Access Enforcement",                                                "P1", "L M H" ],
    [ 4,  "Information Flow Enforcement",                                      "P1", "M H" ],
    [ 5,  "Separation of Duties",                                              "P1", "M H" ],
    [ 6,  "Least Privilege",                                                   "P1", "M H" ],
    [ 7,  "Unsuccessful Logon Attempts",                                       "P2", "L M H" ],
    [ 8,  "System Use Notification",                                           "P2", "L M H" ],
    [ 9,  "Previous Logon (Access) Notification",                              "P0", "" ],
    [ 10, "Concurrent Session Control",                                        "P2", "M H" ],
    [ 11, "Session Lock",                                                      "P2", "M H" ],
    [ 12, "Session Termination",                                               "P2", "M H" ],
    [ 13, "Withdrawn",                                                         "P0", "" ],
    [ 14, "Permitted Actions Without Identification or Authentication",        "P3", "L M H" ],
    [ 15, "Withdrawn",                                                         "P0", "" ],
    [ 16, "Security Attributes",                                               "P2", "M H" ],
    [ 17, "Remote Access",                                                     "P1", "L M H" ],
    [ 18, "Wireless Access",                                                   "P1", "L M H" ],
    [ 19, "Access Control for Mobile Devices",                                 "P1", "M H" ],
    [ 20, "Use of External Information Systems",                               "P1", "L M H" ],
    [ 21, "Information Sharing",                                               "P2", "M H" ],
    [ 22, "Publicly Accessible Content",                                       "P3", "L M H" ],
    [ 23, "Data Mining Protection",                                            "P0", "" ],
    [ 24, "Access Control Decisions",                                          "P0", "" ],
    [ 25, "Reference Monitor",                                                 "P0", "" ]
  ],
  "AT" => [
    [ 1, "Security Awareness and Training Policy and Procedures",  "P1", "L M H" ],
    [ 2, "Security Awareness Training",                            "P1", "L M H" ],
    [ 3, "Role-Based Security Training",                           "P1", "M H" ],
    [ 4, "Security Training Records",                              "P3", "M H" ],
    [ 5, "Contacts with Security Groups and Associations",         "P3", "" ]
  ],
  "AU" => [
    [ 1,  "Audit and Accountability Policy and Procedures",    "P1", "L M H" ],
    [ 2,  "Audit Events",                                      "P1", "L M H" ],
    [ 3,  "Content of Audit Records",                          "P1", "L M H" ],
    [ 4,  "Audit Log Storage Capacity",                        "P1", "L M H" ],
    [ 5,  "Response to Audit Processing Failures",             "P1", "M H" ],
    [ 6,  "Audit Review, Analysis, and Reporting",             "P1", "L M H" ],
    [ 7,  "Audit Reduction and Report Generation",             "P2", "M H" ],
    [ 8,  "Time Stamps",                                       "P1", "L M H" ],
    [ 9,  "Protection of Audit Information",                   "P1", "L M H" ],
    [ 10, "Non-Repudiation",                                   "P2", "H" ],
    [ 11, "Audit Record Retention",                            "P3", "L M H" ],
    [ 12, "Audit Generation",                                  "P1", "L M H" ],
    [ 13, "Monitoring for Information Disclosure",             "P0", "" ],
    [ 14, "Session Audit",                                     "P0", "" ],
    [ 15, "Alternate Audit Capability",                        "P0", "" ],
    [ 16, "Cross-Organizational Auditing",                     "P0", "" ]
  ],
  "CA" => [
    [ 1, "Security Assessment and Authorization Policies and Procedures", "P1", "L M H" ],
    [ 2, "Security Assessments",                                          "P2", "L M H" ],
    [ 3, "System Interconnections",                                       "P1", "L M H" ],
    [ 4, "Withdrawn",                                                     "P0", "" ],
    [ 5, "Plan of Action and Milestones",                                 "P3", "L M H" ],
    [ 6, "Security Authorization",                                        "P2", "L M H" ],
    [ 7, "Continuous Monitoring",                                         "P1", "L M H" ],
    [ 8, "Penetration Testing",                                           "P2", "H" ],
    [ 9, "Internal System Connections",                                   "P2", "L M H" ]
  ],
  "CM" => [
    [ 1,  "Configuration Management Policy and Procedures",     "P1", "L M H" ],
    [ 2,  "Baseline Configuration",                             "P1", "L M H" ],
    [ 3,  "Configuration Change Control",                       "P1", "M H" ],
    [ 4,  "Security Impact Analysis",                           "P2", "L M H" ],
    [ 5,  "Access Restrictions for Change",                     "P1", "M H" ],
    [ 6,  "Configuration Settings",                             "P1", "L M H" ],
    [ 7,  "Least Functionality",                                "P1", "L M H" ],
    [ 8,  "Information System Component Inventory",             "P1", "L M H" ],
    [ 9,  "Configuration Management Plan",                      "P1", "M H" ],
    [ 10, "Software Usage Restrictions",                        "P2", "L M H" ],
    [ 11, "User-Installed Software",                            "P1", "M H" ]
  ],
  "CP" => [
    [ 1,  "Contingency Planning Policy and Procedures",         "P1", "L M H" ],
    [ 2,  "Contingency Plan",                                   "P1", "L M H" ],
    [ 3,  "Contingency Training",                               "P2", "L M H" ],
    [ 4,  "Contingency Plan Testing",                           "P2", "L M H" ],
    [ 5,  "Withdrawn",                                          "P0", "" ],
    [ 6,  "Alternate Storage Site",                             "P1", "M H" ],
    [ 7,  "Alternate Processing Site",                          "P1", "H" ],
    [ 8,  "Telecommunications Services",                        "P1", "M H" ],
    [ 9,  "Information System Backup",                          "P1", "L M H" ],
    [ 10, "Information System Recovery and Reconstitution",     "P1", "L M H" ],
    [ 11, "Alternate Communications Protocols",                 "P0", "" ],
    [ 12, "Safe Mode",                                          "P0", "" ],
    [ 13, "Alternative Security Mechanisms",                    "P0", "" ]
  ],
  "IA" => [
    [ 1,  "Identification and Authentication Policy and Procedures",          "P1", "L M H" ],
    [ 2,  "Identification and Authentication (Organizational Users)",          "P1", "L M H" ],
    [ 3,  "Device Identification and Authentication",                          "P1", "M H" ],
    [ 4,  "Identifier Management",                                             "P1", "L M H" ],
    [ 5,  "Authenticator Management",                                          "P1", "L M H" ],
    [ 6,  "Authenticator Feedback",                                            "P2", "L M H" ],
    [ 7,  "Cryptographic Module Authentication",                               "P1", "L M H" ],
    [ 8,  "Identification and Authentication (Non-Organizational Users)",      "P1", "M H" ],
    [ 9,  "Service Identification and Authentication",                         "P1", "H" ],
    [ 10, "Adaptive Identification and Authentication",                        "P0", "" ],
    [ 11, "Re-Authentication",                                                 "P2", "M H" ]
  ],
  "IR" => [
    [ 1,  "Incident Response Policy and Procedures",            "P1", "L M H" ],
    [ 2,  "Incident Response Training",                         "P2", "L M H" ],
    [ 3,  "Incident Response Testing",                          "P2", "M H" ],
    [ 4,  "Incident Handling",                                  "P1", "L M H" ],
    [ 5,  "Incident Monitoring",                                "P1", "L M H" ],
    [ 6,  "Incident Reporting",                                 "P1", "L M H" ],
    [ 7,  "Incident Response Assistance",                       "P2", "L M H" ],
    [ 8,  "Incident Response Plan",                             "P1", "L M H" ],
    [ 9,  "Information Spillage Response",                      "P0", "" ],
    [ 10, "Integrated Information Security Analysis Team",      "P0", "" ]
  ],
  "MA" => [
    [ 1, "System Maintenance Policy and Procedures",    "P1", "L M H" ],
    [ 2, "Controlled Maintenance",                      "P2", "L M H" ],
    [ 3, "Maintenance Tools",                           "P2", "M H" ],
    [ 4, "Nonlocal Maintenance",                        "P2", "L M H" ],
    [ 5, "Maintenance Personnel",                       "P2", "L M H" ],
    [ 6, "Timely Maintenance",                          "P2", "M H" ]
  ],
  "MP" => [
    [ 1, "Media Protection Policy and Procedures",  "P1", "L M H" ],
    [ 2, "Media Access",                             "P1", "L M H" ],
    [ 3, "Media Marking",                            "P2", "M H" ],
    [ 4, "Media Storage",                            "P1", "M H" ],
    [ 5, "Media Transport",                          "P1", "M H" ],
    [ 6, "Media Sanitization",                       "P1", "L M H" ],
    [ 7, "Media Use",                                "P1", "M H" ],
    [ 8, "Media Downgrading",                        "P0", "" ]
  ],
  "PE" => [
    [ 1,  "Physical and Environmental Protection Policy and Procedures", "P1", "L M H" ],
    [ 2,  "Physical Access Authorizations",                              "P1", "L M H" ],
    [ 3,  "Physical Access Control",                                     "P1", "L M H" ],
    [ 4,  "Access Control for Transmission Medium",                      "P1", "M H" ],
    [ 5,  "Access Control for Output Devices",                           "P2", "M H" ],
    [ 6,  "Monitoring Physical Access",                                  "P1", "L M H" ],
    [ 7,  "Withdrawn",                                                   "P0", "" ],
    [ 8,  "Visitor Access Records",                                      "P3", "L M H" ],
    [ 9,  "Power Equipment and Cabling",                                 "P1", "H" ],
    [ 10, "Emergency Shutoff",                                           "P1", "M H" ],
    [ 11, "Emergency Power",                                             "P1", "M H" ],
    [ 12, "Emergency Lighting",                                          "P1", "L M H" ],
    [ 13, "Fire Protection",                                             "P1", "L M H" ],
    [ 14, "Temperature and Humidity Controls",                           "P1", "L M H" ],
    [ 15, "Water Damage Protection",                                     "P1", "L M H" ],
    [ 16, "Delivery and Removal",                                        "P2", "M H" ],
    [ 17, "Alternate Work Site",                                         "P2", "M H" ],
    [ 18, "Location of Information System Components",                   "P2", "H" ],
    [ 19, "Information Leakage",                                         "P0", "" ],
    [ 20, "Asset Monitoring and Tracking",                               "P0", "" ]
  ],
  "PL" => [
    [ 1, "Security Planning Policy and Procedures",         "P1", "L M H" ],
    [ 2, "System Security Plan",                            "P1", "L M H" ],
    [ 3, "Withdrawn",                                       "P0", "" ],
    [ 4, "Rules of Behavior",                               "P2", "L M H" ],
    [ 5, "Withdrawn",                                       "P0", "" ],
    [ 6, "Withdrawn",                                       "P0", "" ],
    [ 7, "Security Concept of Operations",                  "P0", "" ],
    [ 8, "Information Security Architecture",               "P1", "M H" ],
    [ 9, "Central Management",                              "P0", "" ]
  ],
  "PM" => [
    [ 1,  "Information Security Program Plan",                        "P1", "" ],
    [ 2,  "Senior Information Security Officer",                      "P1", "" ],
    [ 3,  "Information Security Resources",                           "P1", "" ],
    [ 4,  "Plan of Action and Milestones Process",                    "P1", "" ],
    [ 5,  "Information System Inventory",                             "P1", "" ],
    [ 6,  "Information Security Measures of Performance",             "P1", "" ],
    [ 7,  "Enterprise Architecture",                                  "P1", "" ],
    [ 8,  "Critical Infrastructure Plan",                             "P1", "" ],
    [ 9,  "Risk Management Strategy",                                 "P1", "" ],
    [ 10, "Security Authorization Process",                           "P1", "" ],
    [ 11, "Mission/Business Process Definition",                      "P1", "" ],
    [ 12, "Insider Threat Program",                                   "P1", "" ],
    [ 13, "Information Security Workforce",                           "P1", "" ],
    [ 14, "Testing, Training, and Monitoring",                        "P1", "" ],
    [ 15, "Contacts with Security Groups and Associations",           "P2", "" ],
    [ 16, "Threat Awareness Program",                                 "P1", "" ]
  ],
  "PS" => [
    [ 1, "Personnel Security Policy and Procedures",    "P1", "L M H" ],
    [ 2, "Position Risk Designation",                   "P1", "L M H" ],
    [ 3, "Personnel Screening",                         "P1", "L M H" ],
    [ 4, "Personnel Termination",                       "P1", "L M H" ],
    [ 5, "Personnel Transfer",                          "P2", "L M H" ],
    [ 6, "Access Agreements",                           "P3", "L M H" ],
    [ 7, "Third-Party Personnel Security",              "P1", "L M H" ],
    [ 8, "Personnel Sanctions",                         "P3", "L M H" ]
  ],
  "RA" => [
    [ 1, "Risk Assessment Policy and Procedures",           "P1", "L M H" ],
    [ 2, "Security Categorization",                         "P1", "L M H" ],
    [ 3, "Risk Assessment",                                 "P1", "L M H" ],
    [ 4, "Withdrawn",                                       "P0", "" ],
    [ 5, "Vulnerability Scanning",                          "P1", "L M H" ],
    [ 6, "Technical Surveillance Countermeasures Survey",   "P0", "" ]
  ],
  "SA" => [
    [ 1,  "System and Services Acquisition Policy and Procedures",          "P1", "L M H" ],
    [ 2,  "Allocation of Resources",                                        "P1", "L M H" ],
    [ 3,  "System Development Life Cycle",                                  "P1", "L M H" ],
    [ 4,  "Acquisition Process",                                            "P1", "L M H" ],
    [ 5,  "Information System Documentation",                               "P2", "L M H" ],
    [ 6,  "Withdrawn",                                                      "P0", "" ],
    [ 7,  "Withdrawn",                                                      "P0", "" ],
    [ 8,  "Security Engineering Principles",                                "P1", "L M H" ],
    [ 9,  "External Information System Services",                           "P1", "L M H" ],
    [ 10, "Developer Configuration Management",                             "P1", "M H" ],
    [ 11, "Developer Security Testing and Evaluation",                      "P1", "M H" ],
    [ 12, "Supply Chain Protection",                                        "P1", "H" ],
    [ 13, "Trustworthiness",                                                "P0", "" ],
    [ 14, "Criticality Analysis",                                           "P0", "" ],
    [ 15, "Development Process, Standards, and Tools",                      "P2", "M H" ],
    [ 16, "Developer-Provided Training",                                    "P0", "" ],
    [ 17, "Developer Security Architecture and Design",                     "P1", "H" ],
    [ 18, "Tamper Resistance and Detection",                                "P0", "" ],
    [ 19, "Component Authenticity",                                         "P1", "M H" ],
    [ 20, "Customized Development of Critical Components",                  "P0", "" ],
    [ 21, "Developer Screening",                                            "P0", "" ],
    [ 22, "Unsupported System Components",                                  "P1", "L M H" ]
  ],
  "SC" => [
    [ 1,  "System and Communications Protection Policy and Procedures",     "P1", "L M H" ],
    [ 2,  "Application Partitioning",                                       "P1", "M H" ],
    [ 3,  "Security Function Isolation",                                    "P1", "H" ],
    [ 4,  "Information in Shared Resources",                                "P1", "M H" ],
    [ 5,  "Denial of Service Protection",                                   "P1", "M H" ],
    [ 6,  "Resource Availability",                                          "P0", "" ],
    [ 7,  "Boundary Protection",                                            "P1", "L M H" ],
    [ 8,  "Transmission Confidentiality and Integrity",                     "P1", "M H" ],
    [ 9,  "Withdrawn",                                                      "P0", "" ],
    [ 10, "Network Disconnect",                                             "P2", "M H" ],
    [ 11, "Trusted Path",                                                   "P0", "" ],
    [ 12, "Cryptographic Key Establishment and Management",                 "P1", "M H" ],
    [ 13, "Cryptographic Protection",                                       "P1", "M H" ],
    [ 14, "Withdrawn",                                                      "P0", "" ],
    [ 15, "Collaborative Computing Devices",                                "P1", "M H" ],
    [ 16, "Transmission of Security Attributes",                            "P0", "" ],
    [ 17, "Public Key Infrastructure Certificates",                         "P1", "M H" ],
    [ 18, "Mobile Code",                                                    "P1", "M H" ],
    [ 19, "Voice Over Internet Protocol",                                   "P1", "M H" ],
    [ 20, "Secure Name/Address Resolution Service (Authoritative Source)",  "P1", "L M H" ],
    [ 21, "Secure Name/Address Resolution Service (Recursive or Caching Resolver)", "P1", "L M H" ],
    [ 22, "Architecture and Provisioning for Name/Address Resolution Service", "P1", "H" ],
    [ 23, "Session Authenticity",                                           "P1", "M H" ],
    [ 24, "Fail in Known State",                                            "P1", "H" ],
    [ 25, "Thin Nodes",                                                     "P0", "" ],
    [ 26, "Honeypots",                                                      "P0", "" ],
    [ 27, "Platform-Independent Applications",                              "P0", "" ],
    [ 28, "Protection of Information at Rest",                              "P1", "M H" ],
    [ 29, "Heterogeneity",                                                  "P0", "" ],
    [ 30, "Concealment and Misdirection",                                   "P0", "" ],
    [ 31, "Covert Channel Analysis",                                        "P0", "" ],
    [ 32, "Information System Partitioning",                                "P0", "" ],
    [ 33, "Withdrawn",                                                      "P0", "" ],
    [ 34, "Non-Modifiable Executable Programs",                             "P0", "" ],
    [ 35, "Honeyclients",                                                   "P0", "" ],
    [ 36, "Distributed Processing and Storage",                             "P0", "" ],
    [ 37, "Out-of-Band Channels",                                           "P0", "" ],
    [ 38, "Operations Security",                                            "P0", "" ],
    [ 39, "Process Isolation",                                              "P1", "H" ],
    [ 40, "Wireless Link Protection",                                       "P0", "" ],
    [ 41, "Port and I/O Device Access",                                     "P0", "" ],
    [ 42, "Sensor Capability and Data",                                     "P0", "" ],
    [ 43, "Usage Restrictions",                                             "P0", "" ],
    [ 44, "Detonation Chambers",                                            "P0", "" ]
  ],
  "SI" => [
    [ 1,  "System and Information Integrity Policy and Procedures",  "P1", "L M H" ],
    [ 2,  "Flaw Remediation",                                        "P1", "L M H" ],
    [ 3,  "Malicious Code Protection",                               "P1", "L M H" ],
    [ 4,  "Information System Monitoring",                           "P1", "L M H" ],
    [ 5,  "Security Alerts, Advisories, and Directives",             "P1", "L M H" ],
    [ 6,  "Security Function Verification",                          "P1", "H" ],
    [ 7,  "Software, Firmware, and Information Integrity",           "P1", "M H" ],
    [ 8,  "Spam Protection",                                         "P2", "M H" ],
    [ 9,  "Withdrawn",                                               "P0", "" ],
    [ 10, "Information Input Validation",                            "P1", "M H" ],
    [ 11, "Error Handling",                                          "P2", "M H" ],
    [ 12, "Information Handling and Retention",                      "P2", "L M H" ],
    [ 13, "Predictable Failure Prevention",                          "P0", "" ],
    [ 14, "Non-Persistence",                                         "P0", "" ],
    [ 15, "Information Output Filtering",                            "P0", "" ],
    [ 16, "Memory Protection",                                       "P1", "H" ],
    [ 17, "Fail-Safe Procedures",                                    "P0", "" ]
  ]
}.freeze

r4_families = 0
r4_controls = 0

NIST_R4_FAMILIES.each do |family_attrs|
  family = ControlFamily.find_or_create_by!(
    control_catalog: catalog_r4,
    code: family_attrs[:code]
  ) do |f|
    f.name       = family_attrs[:name]
    f.sort_order = family_attrs[:sort_order]
  end
  family.update!(name: family_attrs[:name], sort_order: family_attrs[:sort_order])
  r4_families += 1

  controls_for_family = NIST_R4_CONTROLS[family_attrs[:code]] || []
  controls_for_family.each do |num, title, priority, baseline|
    control_id = "#{family_attrs[:code]}-#{num.to_s.rjust(2, '0')}"
    entry = CatalogControl.find_or_create_by!(
      control_family: family,
      control_id: control_id
    ) do |c|
      c.title           = title
      c.priority        = priority
      c.baseline_impact = baseline.present? ? baseline : nil
    end
    entry.update!(title: title, priority: priority, baseline_impact: baseline.present? ? baseline : nil)
    r4_controls += 1
  end
end

puts "  Created/updated #{r4_families} control families"
puts "  Created/updated #{r4_controls} catalog controls"
puts "Done! NIST SP 800-53 Rev 4 catalog is ready."

# ============================================================
# Demo SSP and SAR Documents
# ============================================================
# Generates two demo SSPs and two demo SARs that reference the
# NIST SP 800-53 Rev 5 and Rev 4 catalogs above.  Idempotent.
# ============================================================

puts "\nSeeding demo SSP and SAR documents..."

def seed_ssp_control(doc, ctrl_id, title, fields, inherited_rows: [])
  ctrl = doc.ssp_controls.create!(control_id: ctrl_id, title: title)
  fields.each do |name, val|
    next if val.blank?
    ctrl.ssp_control_fields.create!(field_name: name.to_s, field_value: val.to_s)
  end
  # Provider / inherited statement rows (child SspControls with parent_id set)
  inherited_rows.each do |row|
    child = doc.ssp_controls.create!(
      control_id: nil,
      title:      row[:title],
      parent_id:  ctrl.id
    )
    (row[:fields] || {}).each do |name, val|
      next if val.blank?
      child.ssp_control_fields.create!(field_name: name.to_s, field_value: val.to_s)
    end
  end
end

# Zero-pad single-digit control numbers for consistent alphabetical sorting.
# "AC-1" → "AC-01",  "AC-10" → "AC-10" (unchanged)
def pad_ctrl_id(id)
  id.to_s.sub(/\A([A-Z]+-?)(\d+)\z/) { "#{$1}#{$2.rjust(2, '0')}" }
end

def seed_sar_control(doc, ctrl_id, title, section, subject_asset, subject_env, fields)
  ctrl = doc.sar_controls.create!(
    control_id:          ctrl_id,
    title:               title,
    section:             section,
    subject_asset:       subject_asset.presence,
    subject_environment: subject_env.presence
  )
  fields.each do |name, val|
    next if val.blank?
    ctrl.sar_control_fields.create!(field_name: name.to_s, field_value: val.to_s)
  end
end

# Asset / environment mapping for Rev5 SAR demo.
# Controls not listed here are boundary-level (no specific asset tested).
REV5_SUBJECTS = {
  "AC-2"  => { asset: "IAM-Platform",  env: "Production" },
  "AC-3"  => { asset: "WebApp-Portal", env: "Production" },
  "AC-4"  => { asset: "API-Gateway",   env: "Staging"    },
  "AC-6"  => { asset: "IAM-Platform",  env: "Production" },
  "AC-7"  => { asset: "IAM-Platform",  env: "Production" },
  "AC-8"  => { asset: "WebApp-Portal", env: "Production" },
  "AC-17" => { asset: "VPN-Gateway",   env: "Production" },
  "AT-2"  => { asset: "LMS-System",    env: "Production" },
  "AT-3"  => { asset: "LMS-System",    env: "Staging"    },
  "AU-2"  => { asset: "Cloud-SIEM",    env: "Production" },
  "AU-3"  => { asset: "Cloud-SIEM",    env: "Production" },
  "AU-4"  => { asset: "Log-Storage",   env: "Production" },
  "AU-5"  => { asset: "Cloud-SIEM",    env: "Production" },
  "AU-8"  => { asset: "NTP-Service",   env: "Production" },
  "AU-9"  => { asset: "Log-Storage",   env: "Production" },
  "AU-11" => { asset: "Log-Storage",   env: "Production" },
  "AU-12" => { asset: "Cloud-SIEM",    env: "Production" },
  "CA-3"  => { asset: "API-Gateway",   env: "Production" },
  "CA-7"  => { asset: "Cloud-SIEM",    env: "Production" }
}.freeze

# ------------------------------------------------------------------
# Demo data: Rev 5 controls (used for both SSP 1 and SAR 1)
# Fields: id, title, ssp_status, role, origination,
#         customer_responsibility, guidance,
#         test_status, test_date, tester, test_result, remediation
# ------------------------------------------------------------------

REV5_CONTROLS = [
  # -- ACCESS CONTROL ------------------------------------------------
  { id: "AC-1",  title: "Policy and Procedures",
    ssp_status: "Implemented",          role: "CISO",
    origin: "System Specific",          cust: "None",
    guidance: "Access Control Policy (POL-AC-001) is maintained, approved by the CISO, and reviewed annually. Procedures are documented in PROC-AC-001.",
    test_status: "Pass",  test_date: "2025-10-15", tester: "J. Smith",
    test_result: "Policy and procedure documentation reviewed; current versions on file dated September 2025.",
    remediation: "" },
  { id: "AC-2",  title: "Account Management",
    ssp_status: "Implemented",          role: "System Administrator",
    origin: "System Specific",          cust: "None",
    guidance: "Account provisioning and de-provisioning workflows are enforced via the identity management platform. Quarterly access reviews are conducted.",
    test_status: "Pass",  test_date: "2025-10-16", tester: "J. Smith",
    test_result: "Account management procedures verified through HR termination records, access review logs, and identity management system audit trail.",
    remediation: "" },
  { id: "AC-3",  title: "Access Enforcement",
    ssp_status: "Implemented",          role: "Security Engineer",
    origin: "System Specific",          cust: "None",
    guidance: "Role-based access control (RBAC) is implemented at the application and database layer. Access decisions are enforced by the authorization service.",
    test_status: "Pass",  test_date: "2025-10-16", tester: "A. Patel",
    test_result: "Tested 15 user roles; all access decisions enforced correctly. No unauthorized access paths discovered.",
    remediation: "" },
  { id: "AC-4",  title: "Information Flow Enforcement",
    ssp_status: "Deferred", role: "Security Engineer",
    origin: "Hybrid",                   cust: "Agency responsible for data classification labels",
    guidance: "Network-level information flow controls are in place via firewall rules. Application-level data flow labeling is in progress.",
    test_status: "Failed", test_date: "2025-10-17", tester: "A. Patel",
    test_result: "Network flow controls verified. Application-level DLP controls are incomplete; three data paths lack enforced classification labels.",
    remediation: "Complete application-level data classification labeling by Q1 2026. Track in POA&M item AC-4-001." },
  { id: "AC-5",  title: "Separation of Duties",
    ssp_status: "Implemented",          role: "CISO",
    origin: "System Specific",          cust: "None",
    guidance: "Conflicting roles are separated in the IAM system. Automated controls prevent users from holding incompatible role combinations.",
    test_status: "Pass",  test_date: "2025-10-17", tester: "J. Smith",
    test_result: "Role matrix reviewed; no violations of separation of duties found across all 342 active accounts.",
    remediation: "" },
  { id: "AC-6",  title: "Least Privilege",
    ssp_status: "Deferred", role: "System Administrator",
    origin: "System Specific",          cust: "None",
    guidance: "Least privilege is enforced at the OS and application layer. Admin account review is scheduled quarterly; last review identified 4 accounts requiring privilege reduction.",
    test_status: "Failed", test_date: "2025-10-18", tester: "A. Patel",
    test_result: "OS and application privilege verified. Four service accounts with excessive privilege identified; remediation in progress.",
    remediation: "Reduce privilege on service accounts SA-DB-01, SA-APP-03, SA-NET-02, SA-MON-01 by December 2025." },
  { id: "AC-7",  title: "Unsuccessful Logon Attempts",
    ssp_status: "Implemented",          role: "Security Engineer",
    origin: "Inherited",                cust: "No customer responsibility",
    guidance: "Account lockout after 5 consecutive failed login attempts is enforced by the identity provider. Lockout duration is 30 minutes.",
    test_status: "Pass",  test_date: "2025-10-18", tester: "R. Garcia",
    test_result: "Lockout behavior confirmed via manual testing; account locked at 5th failed attempt and released after 30 minutes.",
    remediation: "" },
  { id: "AC-8",  title: "System Use Notification",
    ssp_status: "Implemented",          role: "System Owner",
    origin: "System Specific",          cust: "None",
    guidance: "A system use notification banner is displayed at login referencing the acceptable use policy (AUP-001). Users must acknowledge before accessing the system.",
    test_status: "Pass",  test_date: "2025-10-19", tester: "R. Garcia",
    test_result: "Banner text verified against legal-approved language. Acknowledgment flow confirmed for web, API, and CLI interfaces.",
    remediation: "" },
  { id: "AC-11", title: "Device Lock",
    ssp_status: "Implemented",          role: "IT Operations",
    origin: "System Specific",          cust: "None",
    guidance: "Session timeout (15 minutes inactivity) and screen lock are enforced via endpoint management policy. Policy applies to all managed workstations.",
    test_status: "Pass",  test_date: "2025-10-19", tester: "J. Smith",
    test_result: "Endpoint management policy verified on sample of 20 managed devices; all comply with 15-minute timeout.",
    remediation: "" },
  { id: "AC-14", title: "Permitted Actions Without Identification or Authentication",
    ssp_status: "Not Applicable",       role: "CISO",
    origin: "System Specific",          cust: "None",
    guidance: "All system functions require authentication. No permitted actions exist without identification and authentication.",
    test_status: "Not Applicable", test_date: "2025-10-20", tester: "J. Smith",
    test_result: "Not applicable — system requires authentication for all functions.",
    remediation: "" },
  { id: "AC-17", title: "Remote Access",
    ssp_status: "Implemented",          role: "Security Engineer",
    origin: "System Specific",          cust: "None",
    guidance: "Remote access is permitted only via encrypted VPN with MFA. Remote access sessions are logged and monitored. Policy documented in POL-AC-017.",
    test_status: "Pass",  test_date: "2025-10-20", tester: "A. Patel",
    test_result: "VPN configuration, MFA enforcement, and session logging verified. All remote sessions encrypted with TLS 1.3.",
    remediation: "" },
  { id: "AC-18", title: "Wireless Access",
    ssp_status: "Not Applicable",       role: "IT Operations",
    origin: "System Specific",          cust: "None",
    guidance: "System is cloud-hosted; no wireless access points are used in scope. All access is over wired or VPN connections.",
    test_status: "Not Applicable", test_date: "2025-10-20", tester: "R. Garcia",
    test_result: "Not applicable — no wireless infrastructure in scope for this system.",
    remediation: "" },
  # -- AWARENESS AND TRAINING -----------------------------------------
  { id: "AT-1",  title: "Policy and Procedures",
    ssp_status: "Implemented",          role: "CISO",
    origin: "System Specific",          cust: "None",
    guidance: "Security Awareness and Training Policy (POL-AT-001) is maintained and reviewed annually. Training schedule is documented in PROC-AT-001.",
    test_status: "Pass",  test_date: "2025-11-05", tester: "J. Smith",
    test_result: "Policy and procedures documentation current; reviewed and approved November 2025.",
    remediation: "" },
  { id: "AT-2",  title: "Literacy Training and Awareness",
    ssp_status: "Implemented",          role: "Human Resources",
    origin: "System Specific",          cust: "None",
    guidance: "Annual security awareness training is mandatory for all staff. Completion is tracked in the LMS. Current cycle shows 97% completion.",
    test_status: "Pass",  test_date: "2025-11-05", tester: "K. Johnson",
    test_result: "LMS records reviewed; 97% completion rate for FY2025 security awareness training. Non-completions tracked via HR escalation process.",
    remediation: "" },
  { id: "AT-3",  title: "Role-Based Training",
    ssp_status: "Deferred", role: "Training Manager",
    origin: "System Specific",          cust: "None",
    guidance: "Role-based training is available for system administrators, security engineers, and developers. Training for data owners is under development.",
    test_status: "Failed", test_date: "2025-11-06", tester: "K. Johnson",
    test_result: "Training records reviewed for privileged roles. Data owner training curriculum not yet finalized; expected Q2 2026.",
    remediation: "Develop and deploy data owner role-based training by March 2026. Track in POA&M AT-3-001." },
  { id: "AT-4",  title: "Training Records",
    ssp_status: "Implemented",          role: "Human Resources",
    origin: "System Specific",          cust: "None",
    guidance: "Training completion records are maintained in the LMS for a minimum of 3 years. Records are accessible to authorized security personnel.",
    test_status: "Pass",  test_date: "2025-11-06", tester: "J. Smith",
    test_result: "LMS training records verified for completeness and retention period compliance.",
    remediation: "" },
  { id: "AT-5",  title: "Contacts with Security Groups and Associations",
    ssp_status: "Not Applicable",       role: "CISO",
    origin: "System Specific",          cust: "None",
    guidance: "N/A for this system boundary; handled at the organizational level.",
    test_status: "Not Applicable", test_date: "2025-11-06", tester: "J. Smith",
    test_result: "Not applicable at system level.",
    remediation: "" },
  # -- AUDIT AND ACCOUNTABILITY ----------------------------------------
  { id: "AU-1",  title: "Policy and Procedures",
    ssp_status: "Implemented",          role: "CISO",
    origin: "System Specific",          cust: "None",
    guidance: "Audit and Accountability Policy (POL-AU-001) defines logging requirements, retention, and review procedures. Reviewed annually.",
    test_status: "Pass",  test_date: "2025-09-22", tester: "R. Garcia",
    test_result: "Policy documentation current and consistent with NIST guidance.",
    remediation: "" },
  { id: "AU-2",  title: "Event Logging",
    ssp_status: "Implemented",          role: "Security Engineer",
    origin: "System Specific",          cust: "None",
    guidance: "Audit-relevant events are defined in the security plan and enabled across all system components. SIEM ingests logs in real time.",
    test_status: "Pass",  test_date: "2025-09-22", tester: "A. Patel",
    test_result: "Audit event categories verified against policy. All 12 required event types confirmed active in SIEM.",
    remediation: "" },
  { id: "AU-3",  title: "Content of Audit Records",
    ssp_status: "Implemented",          role: "Security Engineer",
    origin: "System Specific",          cust: "None",
    guidance: "Audit records include timestamp, source, event type, outcome, and user identity as required by NIST AU-3 requirements.",
    test_status: "Pass",  test_date: "2025-09-23", tester: "A. Patel",
    test_result: "Sample of 50 audit records reviewed; all required fields present in 100% of records.",
    remediation: "" },
  { id: "AU-4",  title: "Audit Log Storage Capacity",
    ssp_status: "Implemented",          role: "IT Operations",
    origin: "Inherited",                cust: "No customer responsibility",
    guidance: "Audit log storage is managed on the cloud provider platform with auto-scaling enabled. Retention is set to 13 months per policy.",
    test_status: "Pass",  test_date: "2025-09-23", tester: "R. Garcia",
    test_result: "Cloud storage auto-scaling confirmed active; no capacity alerts triggered in past 12 months. Retention validated.",
    remediation: "" },
  { id: "AU-5",  title: "Response to Audit Logging Process Failures",
    ssp_status: "Deferred", role: "Security Engineer",
    origin: "System Specific",          cust: "None",
    guidance: "Automated alerts are configured for SIEM pipeline failures. Manual failover to local logging is documented but not fully tested.",
    test_status: "Failed", test_date: "2025-09-24", tester: "A. Patel",
    test_result: "Alert notification verified. Manual failover procedure exists but last tested 18 months ago; exceeds 12-month test cycle requirement.",
    remediation: "Conduct failover test by January 2026. Update PROC-AU-005 with test results." },
  { id: "AU-6",  title: "Audit Record Review, Analysis, and Reporting",
    ssp_status: "Deferred",              role: "ISSO",
    origin: "System Specific",          cust: "None",
    guidance: "SIEM-driven alert triage is operational. Automated weekly audit review reports are under development; target deployment Q1 2026.",
    test_status: "Not Specified", test_date: "", tester: "",
    test_result: "Capability not yet implemented; scheduled for Q1 2026.",
    remediation: "Deploy automated audit review reporting by March 2026. Track in POA&M AU-6-001." },
  { id: "AU-8",  title: "Time Stamps",
    ssp_status: "Implemented",          role: "IT Operations",
    origin: "Inherited",                cust: "No customer responsibility",
    guidance: "System time is synchronized to authoritative NTP sources provided by the cloud provider. All components use UTC.",
    test_status: "Pass",  test_date: "2025-09-24", tester: "R. Garcia",
    test_result: "NTP synchronization verified across all system components. Time drift under 500ms.",
    remediation: "" },
  { id: "AU-9",  title: "Protection of Audit Information",
    ssp_status: "Implemented",          role: "Security Engineer",
    origin: "System Specific",          cust: "None",
    guidance: "Audit logs are write-protected and stored in a separate logging account with access restricted to the security team. Integrity hash verification is enabled.",
    test_status: "Pass",  test_date: "2025-09-25", tester: "A. Patel",
    test_result: "Logging account permissions verified; access limited to 3 authorized security personnel. Hash integrity check active.",
    remediation: "" },
  { id: "AU-11", title: "Audit Record Retention",
    ssp_status: "Implemented",          role: "IT Operations",
    origin: "Inherited",                cust: "No customer responsibility",
    guidance: "Audit records are retained for 13 months in hot storage and 6 years in cold archive per data retention policy.",
    test_status: "Pass",  test_date: "2025-09-25", tester: "J. Smith",
    test_result: "Storage configuration and retention rules verified. Spot-checked records from 13 months ago confirm availability.",
    remediation: "" },
  { id: "AU-12", title: "Audit Record Generation",
    ssp_status: "Implemented",          role: "IT Operations",
    origin: "System Specific",          cust: "None",
    guidance: "All system components are configured to generate audit records. SIEM agent deployment is tracked and managed via configuration management.",
    test_status: "Pass",  test_date: "2025-09-26", tester: "R. Garcia",
    test_result: "Audit record generation verified on 100% of in-scope components. SIEM coverage confirmed.",
    remediation: "" },
  # -- ASSESSMENT, AUTHORIZATION, AND MONITORING ----------------------
  { id: "CA-1",  title: "Policy and Procedures",
    ssp_status: "Implemented",          role: "CISO",
    origin: "System Specific",          cust: "None",
    guidance: "Assessment, Authorization, and Monitoring Policy (POL-CA-001) is current and approved. Reviewed every 3 years per policy.",
    test_status: "Pass",  test_date: "2025-08-11", tester: "K. Johnson",
    test_result: "Policy documentation current and approved by CISO August 2025.",
    remediation: "" },
  { id: "CA-2",  title: "Control Assessments",
    ssp_status: "Implemented",          role: "ISSO",
    origin: "System Specific",          cust: "None",
    guidance: "Annual security control assessments are conducted by an independent assessor. Assessment results are documented in the SAR.",
    test_status: "Pass",  test_date: "2025-08-12", tester: "K. Johnson",
    test_result: "Assessment documentation reviewed; independent assessment conducted in August 2025 by third-party assessor.",
    remediation: "" },
  { id: "CA-3",  title: "Information Exchange",
    ssp_status: "Deferred", role: "System Owner",
    origin: "System Specific",          cust: "Agency responsible for ISA reviews",
    guidance: "ISAs are established with external systems. Annual review process is defined but one ISA (with Partner System B) is overdue for renewal.",
    test_status: "Failed", test_date: "2025-08-12", tester: "J. Smith",
    test_result: "ISA inventory reviewed. ISA with Partner System B expired July 2025; renewal initiated but not complete.",
    remediation: "Renew ISA with Partner System B by November 2025. Track in POA&M CA-3-001." },
  { id: "CA-5",  title: "Plan of Action and Milestones",
    ssp_status: "Implemented",          role: "ISSO",
    origin: "System Specific",          cust: "None",
    guidance: "POA&M is maintained in the GRC tool and updated monthly. All open findings from the last assessment are tracked with milestones.",
    test_status: "Pass",  test_date: "2025-08-13", tester: "K. Johnson",
    test_result: "POA&M reviewed; all open items have assigned owners and milestone dates. Monthly update cadence confirmed.",
    remediation: "" },
  { id: "CA-6",  title: "Authorization",
    ssp_status: "Implemented",          role: "Authorizing Official",
    origin: "System Specific",          cust: "None",
    guidance: "System holds a current ATO valid through December 2027. ATO package on file including SSP, SAR, and POA&M.",
    test_status: "Pass",  test_date: "2025-08-13", tester: "J. Smith",
    test_result: "ATO documentation verified; authorization valid and current.",
    remediation: "" },
  { id: "CA-7",  title: "Continuous Monitoring",
    ssp_status: "Deferred",              role: "ISSO",
    origin: "System Specific",          cust: "None",
    guidance: "Continuous monitoring strategy is documented. Automated vulnerability scanning is operational; configuration drift detection is planned for Q2 2026.",
    test_status: "Not Specified", test_date: "", tester: "",
    test_result: "Continuous monitoring program partially operational. Configuration drift detection not yet implemented.",
    remediation: "Deploy configuration drift detection tooling by June 2026. Track in POA&M CA-7-001." },
  # -- CONFIGURATION MANAGEMENT ----------------------------------------
  { id: "CM-1",  title: "Policy and Procedures",
    ssp_status: "Implemented",          role: "CISO",
    origin: "System Specific",          cust: "None",
    guidance: "Configuration Management Policy (POL-CM-001) is current. CM procedures are documented in PROC-CM-001 and enforced via change control board.",
    test_status: "Pass",  test_date: "2025-11-18", tester: "A. Patel",
    test_result: "CM policy and procedures documentation reviewed and current.",
    remediation: "" },
  { id: "CM-2",  title: "Baseline Configuration",
    ssp_status: "Implemented",          role: "IT Operations",
    origin: "System Specific",          cust: "None",
    guidance: "Baseline configurations for all system components are documented and stored in the configuration management tool. Baselines are reviewed quarterly.",
    test_status: "Pass",  test_date: "2025-11-18", tester: "R. Garcia",
    test_result: "Baseline configuration documentation verified for 100% of in-scope components. Last review completed October 2025.",
    remediation: "" },
  { id: "CM-3",  title: "Configuration Change Control",
    ssp_status: "Implemented",          role: "Change Manager",
    origin: "System Specific",          cust: "None",
    guidance: "All configuration changes are reviewed by the Change Control Board (CCB) before implementation. Change records are maintained in the ITSM system.",
    test_status: "Pass",  test_date: "2025-11-19", tester: "J. Smith",
    test_result: "Sample of 20 change records reviewed; all required approvals present. No unauthorized changes detected.",
    remediation: "" },
  { id: "CM-4",  title: "Impact Analyses",
    ssp_status: "Deferred", role: "Security Engineer",
    origin: "System Specific",          cust: "None",
    guidance: "Security impact analysis is required for all major changes. Minor change impact analysis process is not yet formalized.",
    test_status: "Failed", test_date: "2025-11-19", tester: "A. Patel",
    test_result: "Major change impact analyses reviewed and found complete. Minor change impact analysis not consistently documented.",
    remediation: "Formalize minor change impact analysis process in PROC-CM-004 by January 2026." },
  { id: "CM-6",  title: "Configuration Settings",
    ssp_status: "Implemented",          role: "System Administrator",
    origin: "System Specific",          cust: "None",
    guidance: "DISA STIGs and CIS Benchmarks are applied to all components. Compliance is monitored continuously via automated scanning.",
    test_status: "Pass",  test_date: "2025-11-20", tester: "R. Garcia",
    test_result: "Configuration compliance scan results reviewed. 98.4% compliance rate; 3 open non-critical findings being tracked.",
    remediation: "" },
  { id: "CM-7",  title: "Least Functionality",
    ssp_status: "Implemented",          role: "System Administrator",
    origin: "System Specific",          cust: "None",
    guidance: "Unnecessary services, ports, and protocols are disabled on all system components per the approved configuration baseline.",
    test_status: "Pass",  test_date: "2025-11-20", tester: "A. Patel",
    test_result: "Port and service audit performed; no unauthorized services detected. Firewall rules reviewed and current.",
    remediation: "" },
  { id: "CM-8",  title: "System Component Inventory",
    ssp_status: "Deferred", role: "IT Operations",
    origin: "System Specific",          cust: "None",
    guidance: "System inventory is maintained in the CMDB. Cloud assets are auto-discovered. On-premises components require manual updates; last update 6 months ago.",
    test_status: "Failed", test_date: "2025-11-21", tester: "J. Smith",
    test_result: "Cloud asset inventory verified via automated discovery. On-prem inventory has 12 unreconciled entries dating to last manual update.",
    remediation: "Reconcile on-premises CMDB entries and establish monthly automated reconciliation by February 2026." },
  # -- CONTINGENCY PLANNING --------------------------------------------
  { id: "CP-1",  title: "Policy and Procedures",
    ssp_status: "Implemented",          role: "CISO",
    origin: "System Specific",          cust: "None",
    guidance: "Contingency Planning Policy (POL-CP-001) is current and approved. BCP/DR procedures are documented and distributed to key personnel.",
    test_status: "Pass",  test_date: "2025-07-08", tester: "K. Johnson",
    test_result: "Policy documentation reviewed and current as of July 2025.",
    remediation: "" },
  { id: "CP-2",  title: "Contingency Plan",
    ssp_status: "Implemented",          role: "Business Continuity Manager",
    origin: "System Specific",          cust: "None",
    guidance: "The Contingency Plan (CP-001) documents recovery objectives, roles, and procedures. RTO: 4 hours, RPO: 1 hour. Reviewed and updated annually.",
    test_status: "Pass",  test_date: "2025-07-09", tester: "K. Johnson",
    test_result: "Contingency plan documentation reviewed; current version dated June 2025. RTO/RPO objectives documented and achievable.",
    remediation: "" },
  { id: "CP-4",  title: "Contingency Plan Testing",
    ssp_status: "Deferred",              role: "Business Continuity Manager",
    origin: "System Specific",          cust: "None",
    guidance: "Annual tabletop exercises are conducted. Full failover test is scheduled for Q2 2026 following environment migration.",
    test_status: "Not Specified", test_date: "", tester: "",
    test_result: "Full failover test not yet conducted for current environment version; scheduled for Q2 2026.",
    remediation: "Conduct full failover test by June 2026. Track in POA&M CP-4-001." },
  { id: "CP-9",  title: "System Backup",
    ssp_status: "Implemented",          role: "IT Operations",
    origin: "Inherited",                cust: "No customer responsibility",
    guidance: "System backups are performed daily (incremental) and weekly (full). Backups are encrypted and replicated to a geographically separate region.",
    test_status: "Pass",  test_date: "2025-07-10", tester: "R. Garcia",
    test_result: "Backup job logs reviewed for past 90 days; 100% success rate. Restore test performed; RTO objective met.",
    remediation: "" },
  # -- IDENTIFICATION AND AUTHENTICATION --------------------------------
  { id: "IA-1",  title: "Policy and Procedures",
    ssp_status: "Implemented",          role: "CISO",
    origin: "System Specific",          cust: "None",
    guidance: "I&A Policy (POL-IA-001) defines authentication requirements and is reviewed annually. Password standards are enforced via IAM platform.",
    test_status: "Pass",  test_date: "2025-12-01", tester: "J. Smith",
    test_result: "Policy documentation current and in compliance with NIST SP 800-63B requirements.",
    remediation: "" },
  { id: "IA-2",  title: "Identification and Authentication (Organizational Users)",
    ssp_status: "Implemented",          role: "Security Engineer",
    origin: "System Specific",          cust: "None",
    guidance: "Multi-factor authentication is enforced for all organizational users via the SSO platform. FIDO2 and TOTP are supported.",
    test_status: "Pass",  test_date: "2025-12-01", tester: "A. Patel",
    test_result: "MFA enforcement verified for all 342 active organizational accounts. No accounts with MFA bypass exceptions.",
    remediation: "" },
  { id: "IA-3",  title: "Device Identification and Authentication",
    ssp_status: "Deferred", role: "System Administrator",
    origin: "System Specific",          cust: "None",
    guidance: "Managed devices use certificate-based authentication. BYOD device authentication policy is under review.",
    test_status: "Failed", test_date: "2025-12-02", tester: "R. Garcia",
    test_result: "Certificate-based auth verified for managed fleet. BYOD policy not finalized; 12 unmanaged devices detected accessing the network.",
    remediation: "Finalize BYOD policy and enforce device authentication by February 2026. Track in POA&M IA-3-001." },
  { id: "IA-4",  title: "Identifier Management",
    ssp_status: "Implemented",          role: "System Administrator",
    origin: "System Specific",          cust: "None",
    guidance: "User identifiers are managed via the IAM platform. Reuse of identifiers is prevented. Inactive accounts are disabled after 90 days.",
    test_status: "Pass",  test_date: "2025-12-02", tester: "J. Smith",
    test_result: "Identifier management procedures verified. No reused identifiers found. Inactive account policy confirmed active.",
    remediation: "" },
  { id: "IA-5",  title: "Authenticator Management",
    ssp_status: "Implemented",          role: "Security Engineer",
    origin: "System Specific",          cust: "None",
    guidance: "Passwords meet NIST SP 800-63B requirements (12+ chars, no expiration unless breached). Compromised credentials are checked against HaveIBeenPwned API.",
    test_status: "Pass",  test_date: "2025-12-03", tester: "A. Patel",
    test_result: "Password policy configuration verified. Breach detection API integration confirmed active and operational.",
    remediation: "" },
  { id: "IA-6",  title: "Authentication Feedback",
    ssp_status: "Implemented",          role: "Security Engineer",
    origin: "Inherited",                cust: "No customer responsibility",
    guidance: "Authentication feedback (password masking, generic error messages) is enforced by the IdP platform. Inherited from cloud identity provider.",
    test_status: "Pass",  test_date: "2025-12-03", tester: "R. Garcia",
    test_result: "Authentication feedback behavior verified on login forms; passwords masked and error messages generic.",
    remediation: "" },
  # -- INCIDENT RESPONSE -----------------------------------------------
  { id: "IR-1",  title: "Policy and Procedures",
    ssp_status: "Implemented",          role: "CISO",
    origin: "System Specific",          cust: "None",
    guidance: "Incident Response Policy (POL-IR-001) and procedures (PROC-IR-001) are current. Incident classification levels and escalation paths are defined.",
    test_status: "Pass",  test_date: "2025-10-05", tester: "K. Johnson",
    test_result: "IR policy and procedure documentation reviewed and current.",
    remediation: "" },
  { id: "IR-2",  title: "Incident Response Training",
    ssp_status: "Implemented",          role: "Security Engineer",
    origin: "System Specific",          cust: "None",
    guidance: "Annual IR training is conducted for the security team and system owners. Tabletop exercises are held semi-annually.",
    test_status: "Pass",  test_date: "2025-10-06", tester: "J. Smith",
    test_result: "Training completion records verified for all security team members. Tabletop exercise conducted September 2025.",
    remediation: "" },
  { id: "IR-4",  title: "Incident Handling",
    ssp_status: "Implemented",          role: "ISSO",
    origin: "System Specific",          cust: "None",
    guidance: "Incidents are tracked in the ITSM system with defined severity levels, escalation paths, and communication templates. Average MTTR under 4 hours for P1.",
    test_status: "Pass",  test_date: "2025-10-06", tester: "K. Johnson",
    test_result: "Incident handling procedures and 5 past incident records reviewed. Escalation paths followed correctly in all cases.",
    remediation: "" },
  { id: "IR-5",  title: "Incident Monitoring",
    ssp_status: "Deferred", role: "ISSO",
    origin: "System Specific",          cust: "None",
    guidance: "SIEM-based incident detection is operational. Automated response playbooks are in development for the top 5 incident types.",
    test_status: "Failed", test_date: "2025-10-07", tester: "A. Patel",
    test_result: "SIEM monitoring confirmed active. Only 2 of 5 planned automated playbooks deployed; remaining 3 in development.",
    remediation: "Deploy remaining 3 automated incident response playbooks by January 2026." },
  { id: "IR-6",  title: "Incident Reporting",
    ssp_status: "Implemented",          role: "ISSO",
    origin: "System Specific",          cust: "Agency responsible for US-CERT reporting",
    guidance: "Incident reporting procedures include internal reporting chains and external reporting to US-CERT within required timeframes.",
    test_status: "Pass",  test_date: "2025-10-07", tester: "K. Johnson",
    test_result: "Reporting procedures reviewed. One incident from past year required US-CERT notification; confirmed reported within 1 hour of detection.",
    remediation: "" }
].freeze

# ------------------------------------------------------------------
# Demo data: Rev 4 controls (used for both SSP 2 and TPR 2)
# ------------------------------------------------------------------

REV4_CONTROLS = [
  # -- ACCESS CONTROL ------------------------------------------------
  { id: "AC-1",  title: "Access Control Policy and Procedures",
    ssp_status: "Implemented",          role: "CISO",
    origin: "System Specific",          cust: "None",
    guidance: "Access Control Policy (POL-AC-001) is reviewed annually and approved by the CISO. Procedures are documented and distributed.",
    test_status: "Pass",  test_date: "2025-06-10", tester: "M. Torres",
    test_result: "Policy documentation reviewed and current. Last review completed May 2025.",
    remediation: "" },
  { id: "AC-2",  title: "Account Management",
    ssp_status: "Implemented",          role: "System Administrator",
    origin: "System Specific",          cust: "None",
    guidance: "Accounts are provisioned and de-provisioned via the HR onboarding/offboarding process. Semi-annual access reviews are conducted.",
    test_status: "Pass",  test_date: "2025-06-10", tester: "M. Torres",
    test_result: "Account lifecycle procedures verified through HR records. No orphaned accounts found.",
    remediation: "" },
  { id: "AC-3",  title: "Access Enforcement",
    ssp_status: "Implemented",          role: "Security Engineer",
    origin: "System Specific",          cust: "None",
    guidance: "Role-based access control is implemented at the application level. Permissions are enforced on all API endpoints and UI routes.",
    test_status: "Pass",  test_date: "2025-06-11", tester: "D. Lee",
    test_result: "RBAC enforcement tested across all role types; no unauthorized access pathways found.",
    remediation: "" },
  { id: "AC-6",  title: "Least Privilege",
    ssp_status: "Implemented",          role: "System Administrator",
    origin: "System Specific",          cust: "None",
    guidance: "Users are granted minimum necessary permissions. Privileged accounts are reviewed quarterly.",
    test_status: "Pass",  test_date: "2025-06-11", tester: "D. Lee",
    test_result: "Privilege review records examined; no excessive permissions found.",
    remediation: "" },
  { id: "AC-7",  title: "Unsuccessful Logon Attempts",
    ssp_status: "Implemented",          role: "Security Engineer",
    origin: "Inherited",                cust: "No customer responsibility",
    guidance: "Lockout after 5 failed attempts enforced by IdP. Policy inherited from enterprise SSO.",
    test_status: "Pass",  test_date: "2025-06-12", tester: "M. Torres",
    test_result: "Lockout behavior verified; account locked at 5th failed attempt.",
    remediation: "" },
  { id: "AC-8",  title: "System Use Notification",
    ssp_status: "Implemented",          role: "System Owner",
    origin: "System Specific",          cust: "None",
    guidance: "Login banner displays approved AUP text. Users must acknowledge before accessing the system.",
    test_status: "Pass",  test_date: "2025-06-12", tester: "D. Lee",
    test_result: "Banner text verified against legal-approved language.",
    remediation: "" },
  { id: "AC-17", title: "Remote Access",
    ssp_status: "Deferred",              role: "Security Engineer",
    origin: "System Specific",          cust: "None",
    guidance: "Remote access policy is defined. VPN with MFA deployment is planned for Q3 2025.",
    test_status: "Not Specified", test_date: "", tester: "",
    test_result: "Remote access controls not yet fully implemented.",
    remediation: "Deploy VPN and MFA for remote access by September 2025." },
  { id: "AC-18", title: "Wireless Access",
    ssp_status: "Not Applicable",       role: "IT Operations",
    origin: "System Specific",          cust: "None",
    guidance: "System is hosted on-premises with no wireless connectivity in scope.",
    test_status: "Not Applicable", test_date: "2025-06-13", tester: "M. Torres",
    test_result: "Not applicable — no wireless access in scope.",
    remediation: "" },
  # -- AWARENESS AND TRAINING -----------------------------------------
  { id: "AT-1",  title: "Security Awareness and Training Policy and Procedures",
    ssp_status: "Implemented",          role: "CISO",
    origin: "System Specific",          cust: "None",
    guidance: "Training policy reviewed annually. Training schedule distributed to department heads.",
    test_status: "Pass",  test_date: "2025-07-15", tester: "D. Lee",
    test_result: "Policy documentation current.",
    remediation: "" },
  { id: "AT-2",  title: "Security Awareness Training",
    ssp_status: "Implemented",          role: "Human Resources",
    origin: "System Specific",          cust: "None",
    guidance: "Annual security awareness training is mandatory. Current cycle shows 94% completion.",
    test_status: "Pass",  test_date: "2025-07-15", tester: "M. Torres",
    test_result: "LMS records reviewed; 94% completion for FY2025.",
    remediation: "" },
  { id: "AT-3",  title: "Role-Based Security Training",
    ssp_status: "Deferred", role: "Training Manager",
    origin: "System Specific",          cust: "None",
    guidance: "Role-based training delivered for administrators and developers. End-user advanced training curriculum in development.",
    test_status: "Failed", test_date: "2025-07-16", tester: "D. Lee",
    test_result: "Admin and developer training records reviewed and current. End-user advanced training not yet deployed.",
    remediation: "Deploy end-user advanced training curriculum by November 2025." },
  { id: "AT-4",  title: "Security Training Records",
    ssp_status: "Implemented",          role: "Human Resources",
    origin: "System Specific",          cust: "None",
    guidance: "Training completion records maintained in LMS with 3-year retention.",
    test_status: "Pass",  test_date: "2025-07-16", tester: "M. Torres",
    test_result: "LMS records verified for completeness and retention.",
    remediation: "" },
  # -- AUDIT AND ACCOUNTABILITY ----------------------------------------
  { id: "AU-1",  title: "Audit and Accountability Policy and Procedures",
    ssp_status: "Implemented",          role: "CISO",
    origin: "System Specific",          cust: "None",
    guidance: "Audit policy and procedures are maintained and reviewed annually.",
    test_status: "Pass",  test_date: "2025-08-20", tester: "D. Lee",
    test_result: "Policy documentation current.",
    remediation: "" },
  { id: "AU-2",  title: "Audit Events",
    ssp_status: "Implemented",          role: "Security Engineer",
    origin: "System Specific",          cust: "None",
    guidance: "Audit events are configured per policy. SIEM ingests and stores all required event types.",
    test_status: "Pass",  test_date: "2025-08-20", tester: "M. Torres",
    test_result: "All 10 required audit event types confirmed active.",
    remediation: "" },
  { id: "AU-3",  title: "Content of Audit Records",
    ssp_status: "Implemented",          role: "Security Engineer",
    origin: "System Specific",          cust: "None",
    guidance: "Audit records include required fields: timestamp, event type, source, outcome, user identity.",
    test_status: "Pass",  test_date: "2025-08-21", tester: "D. Lee",
    test_result: "Sample of 30 audit records reviewed; all required fields present.",
    remediation: "" },
  { id: "AU-6",  title: "Audit Review, Analysis, and Reporting",
    ssp_status: "Deferred",              role: "ISSO",
    origin: "System Specific",          cust: "None",
    guidance: "Manual weekly audit review is conducted. Automated reporting tooling is planned for deployment in Q1 2026.",
    test_status: "Not Specified", test_date: "", tester: "",
    test_result: "Automated reporting not yet implemented.",
    remediation: "Implement automated audit review reporting by March 2026." },
  { id: "AU-9",  title: "Protection of Audit Information",
    ssp_status: "Implemented",          role: "Security Engineer",
    origin: "System Specific",          cust: "None",
    guidance: "Audit logs are write-protected and access is restricted to the security team. Integrity verification enabled.",
    test_status: "Pass",  test_date: "2025-08-21", tester: "M. Torres",
    test_result: "Log protection and access controls verified.",
    remediation: "" },
  { id: "AU-12", title: "Audit Generation",
    ssp_status: "Implemented",          role: "IT Operations",
    origin: "System Specific",          cust: "None",
    guidance: "All in-scope system components generate audit records in the required format.",
    test_status: "Pass",  test_date: "2025-08-22", tester: "D. Lee",
    test_result: "Audit generation verified on all in-scope components.",
    remediation: "" },
  # -- CONFIGURATION MANAGEMENT ----------------------------------------
  { id: "CM-1",  title: "Configuration Management Policy and Procedures",
    ssp_status: "Implemented",          role: "CISO",
    origin: "System Specific",          cust: "None",
    guidance: "CM policy and procedures are current and enforced via Change Control Board.",
    test_status: "Pass",  test_date: "2025-09-10", tester: "M. Torres",
    test_result: "Policy documentation current and CCB charter in place.",
    remediation: "" },
  { id: "CM-2",  title: "Baseline Configuration",
    ssp_status: "Implemented",          role: "IT Operations",
    origin: "System Specific",          cust: "None",
    guidance: "Baseline configurations documented in configuration management tool. Reviewed quarterly.",
    test_status: "Pass",  test_date: "2025-09-10", tester: "D. Lee",
    test_result: "Baseline documentation verified for all in-scope components.",
    remediation: "" },
  { id: "CM-6",  title: "Configuration Settings",
    ssp_status: "Deferred", role: "System Administrator",
    origin: "System Specific",          cust: "None",
    guidance: "CIS Benchmark applied to servers. Desktop configuration hardening is in progress.",
    test_status: "Failed", test_date: "2025-09-11", tester: "M. Torres",
    test_result: "Server hardening verified. Desktop hardening incomplete; 15% of workstations below benchmark.",
    remediation: "Complete workstation hardening by December 2025." },
  { id: "CM-7",  title: "Least Functionality",
    ssp_status: "Implemented",          role: "System Administrator",
    origin: "System Specific",          cust: "None",
    guidance: "Unnecessary services and ports are disabled per approved baseline.",
    test_status: "Pass",  test_date: "2025-09-11", tester: "D. Lee",
    test_result: "Port and service audit performed; no unauthorized services found.",
    remediation: "" },
  { id: "CM-8",  title: "Information System Component Inventory",
    ssp_status: "Deferred", role: "IT Operations",
    origin: "System Specific",          cust: "None",
    guidance: "Asset inventory maintained in CMDB. Some legacy systems not yet included.",
    test_status: "Failed", test_date: "2025-09-12", tester: "M. Torres",
    test_result: "CMDB reviewed; 8 legacy components not yet catalogued.",
    remediation: "Add legacy components to CMDB by November 2025." },
  # -- IDENTIFICATION AND AUTHENTICATION --------------------------------
  { id: "IA-1",  title: "Identification and Authentication Policy and Procedures",
    ssp_status: "Implemented",          role: "CISO",
    origin: "System Specific",          cust: "None",
    guidance: "I&A policy is current. Password standards enforced via IAM platform.",
    test_status: "Pass",  test_date: "2025-10-01", tester: "D. Lee",
    test_result: "Policy documentation current and consistent with NIST SP 800-63B.",
    remediation: "" },
  { id: "IA-2",  title: "Identification and Authentication (Organizational Users)",
    ssp_status: "Implemented",          role: "Security Engineer",
    origin: "System Specific",          cust: "None",
    guidance: "MFA is required for all users. SSO with TOTP enforced.",
    test_status: "Pass",  test_date: "2025-10-01", tester: "M. Torres",
    test_result: "MFA enforcement verified for all active accounts.",
    remediation: "" },
  { id: "IA-4",  title: "Identifier Management",
    ssp_status: "Implemented",          role: "System Administrator",
    origin: "System Specific",          cust: "None",
    guidance: "User identifiers managed via IAM. Reuse prevented. Inactive accounts disabled after 90 days.",
    test_status: "Pass",  test_date: "2025-10-02", tester: "D. Lee",
    test_result: "Identifier management verified. No reused IDs found.",
    remediation: "" },
  { id: "IA-5",  title: "Authenticator Management",
    ssp_status: "Implemented",          role: "Security Engineer",
    origin: "System Specific",          cust: "None",
    guidance: "Password policy enforces 12+ character minimum, complexity, and breach checking.",
    test_status: "Pass",  test_date: "2025-10-02", tester: "M. Torres",
    test_result: "Password policy configuration and breach detection verified.",
    remediation: "" }
].freeze

# Demo docs are always destroyed and recreated to keep field names current.
[
  "ACME Cloud Platform — SSP (NIST SP 800-53 Rev 5, Moderate)",
  "ACME HR Portal — SSP (NIST SP 800-53 Rev 4, Low)"
].each { |n| SspDocument.find_by(name: n)&.destroy }

[
  "ACME Cloud Platform — Annual Security Assessment (Rev 5)",
  "ACME HR Portal — Security Assessment (Rev 4)"
].each { |n| SarDocument.find_by(name: n)&.destroy }

# -- SSP 1: Rev 5 Moderate Baseline ----------------------------------
ssp1 = SspDocument.create!(
  name:              "ACME Cloud Platform — SSP (NIST SP 800-53 Rev 5, Moderate)",
  file_type:         "excel",
  original_filename: "demo_acme_cloud_platform_ssp_rev5.xlsx",
  status:            "completed"
)

# Representative stated requirements for key Rev 5 controls.
# Others will be blank (field simply won't display).
SSP1_STATED_REQS = {
  "AC-1"  => "The organization shall develop, document, and disseminate to designated personnel an access control policy and procedures that addresses purpose, scope, roles, responsibilities, and compliance.",
  "AC-2"  => "The organization shall manage information system accounts, including establishing, activating, modifying, reviewing, disabling, and removing accounts.",
  "AC-3"  => "The information system enforces approved authorizations for logical access to information and system resources in accordance with applicable access control policies.",
  "AC-4"  => "The information system enforces approved authorizations for controlling the flow of information within the system and between interconnected systems.",
  "AC-7"  => "The information system shall enforce a limit of consecutive invalid logon attempts by a user during a specified time period.",
  "AU-2"  => "The organization shall determine that the information system is capable of auditing events, coordinate the security audit function with other organizations, and provide a rationale for the auditable events.",
  "AU-3"  => "The information system shall produce audit records that contain sufficient information to establish the type of event, when the event occurred, where the event occurred, the source of the event, and the outcome of the event.",
  "IA-2"  => "The information system uniquely identifies and authenticates organizational users (or processes acting on behalf of organizational users).",
  "IA-5"  => "The organization manages information system authenticators by verifying identity prior to distribution, establishing initial authenticator content, ensuring procedures for replacing lost or compromised authenticators, and changing/refreshing authenticators.",
  "IR-4"  => "The organization shall implement an incident handling capability for security incidents including preparation, detection and analysis, containment, eradication, and recovery.",
  "CA-7"  => "The organization shall develop a continuous monitoring strategy and implement a continuous monitoring program that includes the establishment of metrics, monitoring frequencies, assessment of security controls, and reporting."
}.freeze

# Provider statements (inherited rows) for selected Hybrid controls in SSP 1.
SSP1_INHERITED = {
  "AC-4"  => [
    { title: "Cloud Provider — Network Boundary Controls",
      fields: {
        type_use_as:            "Inherited",
        provided_as:            "Implemented",
        control_origination:    "Inherited from provider",
        private_implementation: "AWS VPC Security Groups and Network ACLs enforce boundary-level information flow controls. Managed by cloud provider and verified via AWS Config rules.",
        responsible_entities:   "Cloud Provider (AWS)"
      }
    }
  ],
  "AU-4"  => [
    { title: "Cloud Provider — Log Storage Capacity",
      fields: {
        type_use_as:            "Inherited",
        provided_as:            "Configured",
        control_origination:    "Inherited from provider",
        private_implementation: "Audit log storage capacity is managed through AWS CloudWatch Logs with auto-scaling enabled. Retention policies are configured at the organization level.",
        responsible_entities:   "Cloud Provider (AWS) / ACME DevOps"
      }
    }
  ],
  "IA-5"  => [
    { title: "Enterprise IdP — Authenticator Lifecycle",
      fields: {
        type_use_as:            "Inherited",
        provided_as:            "Implemented",
        control_origination:    "Inherited from provider",
        private_implementation: "Okta manages the full authenticator lifecycle including provisioning, MFA enforcement, and compromised credential monitoring via HaveIBeenPwned integration.",
        responsible_entities:   "Identity Provider (Okta)"
      }
    }
  ]
}.freeze

REV5_CONTROLS.each do |c|
  # Derive type_use_as and provided_as from existing origin/status fields
  type_use = case c[:origin]
  when "Inherited" then "Inherited"
  when "Hybrid"    then "Hybrid"
  else                  "System Specific"
  end
  prov_as = c[:ssp_status] == "Implemented" ? "Implemented" : "Documented"

  seed_ssp_control(ssp1, pad_ctrl_id(c[:id]), c[:title],
    {
      status:                 c[:ssp_status],
      type_use_as:            type_use,
      provided_as:            prov_as,
      responsible_entities:   c[:role],
      control_origination:    c[:origin],
      private_implementation: c[:guidance],
      stated_requirement:     SSP1_STATED_REQS[c[:id]]
    },
    inherited_rows: SSP1_INHERITED[c[:id]] || [])
end
puts "  SSP 1 '#{ssp1.name}': #{ssp1.ssp_controls.count} controls"

# -- SSP 2: Rev 4 Low Baseline ----------------------------------------
ssp2 = SspDocument.create!(
  name:              "ACME HR Portal — SSP (NIST SP 800-53 Rev 4, Low)",
  file_type:         "excel",
  original_filename: "demo_acme_hr_portal_ssp_rev4.xlsx",
  status:            "completed"
)

REV4_CONTROLS.each do |c|
  type_use = case c[:origin]
  when "Inherited" then "Inherited"
  when "Hybrid"    then "Hybrid"
  else                  "System Specific"
  end
  prov_as = c[:ssp_status] == "Implemented" ? "Implemented" : "Documented"

  seed_ssp_control(ssp2, pad_ctrl_id(c[:id]), c[:title],
    {
      status:                 c[:ssp_status],
      type_use_as:            type_use,
      provided_as:            prov_as,
      responsible_entities:   c[:role],
      control_origination:    c[:origin],
      private_implementation: c[:guidance]
    })
end
puts "  SSP 2 '#{ssp2.name}': #{ssp2.ssp_controls.count} controls"

# -- SAR 1: Rev 5 Annual Assessment (multi-section demo) --------------
sar1 = SarDocument.create!(
  name:              "ACME Cloud Platform — Annual Security Assessment (Rev 5)",
  file_type:         "excel",
  original_filename: "demo_acme_cloud_platform_sar_rev5.xlsx",
  status:            "completed"
)

REV5_CONTROLS.each do |c|
  family = c[:id].split("-").first
  section_name = case family
  when "AC", "AT" then "System Test"
  when "AU", "CA" then "Location Tests"
  else "System Test"
  end
  subj = REV5_SUBJECTS[c[:id]] || {}

  # Derive working_status from result
  working_status = case c[:test_status]
  when "Pass"          then "Final Satisfied"
  when "Failed"        then "Not Satisfied"
  when "Not Specified" then "Not Specified"
  else nil
  end

  # working_comments only for Failed controls
  working_comments = c[:test_status] == "Failed" ? c[:remediation] : nil

  seed_sar_control(sar1, pad_ctrl_id(c[:id]), c[:title], section_name,
    subj[:asset].to_s, subj[:env].to_s,
    result:           c[:test_status],
    date:             c[:test_date],
    tester:           c[:tester],
    notes_weakness:   c[:test_result],
    recommended_fix:  c[:remediation],
    working_status:   working_status,
    working_comments: working_comments)
end
puts "  SAR 1 '#{sar1.name}': #{sar1.sar_controls.count} controls"

# -- SAR 2: Rev 4 HR Assessment ----------------------------------------
sar2 = SarDocument.create!(
  name:              "ACME HR Portal — Security Assessment (Rev 4)",
  file_type:         "excel",
  original_filename: "demo_acme_hr_portal_sar_rev4.xlsx",
  status:            "completed"
)

REV4_CONTROLS.each do |c|
  working_status = case c[:test_status]
  when "Pass"          then "Final Satisfied"
  when "Failed"        then "Not Satisfied"
  when "Not Specified" then "Not Specified"
  else nil
  end

  seed_sar_control(sar2, pad_ctrl_id(c[:id]), c[:title], "System Test",
    nil, nil,
    result:           c[:test_status],
    date:             c[:test_date],
    tester:           c[:tester],
    notes_weakness:   c[:test_result],
    recommended_fix:  c[:remediation],
    working_status:   working_status,
    working_comments: (c[:test_status] == "Failed" ? c[:remediation] : nil))
end
puts "  SAR 2 '#{sar2.name}': #{sar2.sar_controls.count} controls"

# ============================================================
# Catalog Guidance — load from providing-catalog JSON files
# ============================================================
# Files live outside the repo so we load them gracefully.
# Each JSON is an array of { family:, controls: [...] } objects.
# For each control entry we extract extended_description / tags
# and store the result as guidance_data on the CatalogControl row.
# ============================================================
puts "\nLoading catalog guidance from JSON files..."
require "json"

CATALOG_GUIDANCE_SOURCES = [
  {
    path:         "/Users/brandonfield/GitHub/skunkwerks/data/catalogs/r5.json",
    catalog_name: "NIST SP 800-53 Rev 5"
  },
  {
    path:         "/Users/brandonfield/GitHub/skunkwerks/data/catalogs/r4_final.json",
    catalog_name: "NIST SP 800-53 Rev 4"
  }
].freeze

CATALOG_GUIDANCE_SOURCES.each do |source|
  unless File.exist?(source[:path])
    puts "  Skipping #{source[:catalog_name]} — file not found: #{source[:path]}"
    next
  end

  raw   = JSON.parse(File.read(source[:path]))
  count = 0

  raw.each do |family_group|
    (family_group["controls"] || []).each do |ctrl|
      control_id = ctrl["control_id"].to_s.strip
      next if control_id.blank?

      ext  = (ctrl["extended_description"] || []).first || {}
      tags = (ctrl["tags"] || []).first || {}
      refs = (ext["references"] || []).first || {}

      guidance = {
        "supplemental_guidance"   => ext["supplemental_guidance"],
        "implementation_guidance" => ext["implementation_guidance"],
        "check"                   => ext["check"],
        "fix"                     => ext["fix"],
        "related_controls"        => ext["related_controls"],
        "org_ref"                 => refs["org_ref"].presence || tags["org_ref"],
        "nist_references"         => refs["nist"].presence || tags["nist_references"]
      }.reject { |_, v| v.blank? || v == [] }

      next if guidance.empty?

      updated = CatalogControl.where(control_id: control_id).update_all(guidance_data: guidance)
      count  += updated
    end
  end

  puts "  #{source[:catalog_name]}: updated guidance_data for #{count} catalog control(s)"
end

# ── Inline demo guidance (used when JSON catalog files are not present) ──────
# Provides realistic catalog guidance for a handful of controls so the
# "Catalog Guidance" collapsible panel can be demonstrated without external files.
INLINE_CATALOG_GUIDANCE = {
  "AC-02" => {
    "supplemental_guidance"   => "Account management includes the identification of account types (individual, shared, group, system, application, guest), establishing conditions for group and role membership, and assigning account managers. Organizations should identify authorized users and specify access privileges.",
    "implementation_guidance" => "Configure automated lifecycle management: provisioning tied to HR onboarding, deprovisioning within 24 hours of termination, quarterly access reviews with manager attestation. Integrate with SIEM for anomalous account activity alerting.",
    "check"                   => "Review account provisioning/deprovisioning logs; verify quarterly review completion; confirm automated disabling is triggered upon termination HR events.",
    "related_controls"        => "AC-3, AC-5, AC-6, IA-2, IA-4, IA-5, IA-8, MA-5, PE-2, PS-4",
    "nist_references"         => "NIST SP 800-53 Rev 5 AC-2; FIPS 200"
  },
  "AC-03" => {
    "supplemental_guidance"   => "Access enforcement mechanisms are employed at the application and system level. Role-based access control (RBAC) or attribute-based access control (ABAC) are common implementations. Least privilege principles should be applied.",
    "implementation_guidance" => "Implement RBAC at application and database layers. Ensure access decisions are logged. Periodic reviews of role assignments should be conducted to detect privilege creep.",
    "check"                   => "Test with a representative sample of user roles; confirm that users cannot access resources outside their assigned role. Review access control decision logs.",
    "fix"                     => "Remove any overly-permissive roles; implement separation of duty constraints in the role model; add compensating controls for shared accounts.",
    "related_controls"        => "AC-2, AC-4, AC-5, AC-6, AC-16, AC-17, AC-18, AC-19, AC-20, AU-9, CM-5, CM-11, MA-3, MA-4, MA-5, PE-2"
  },
  "AC-07" => {
    "supplemental_guidance"   => "Organizations define the threshold for consecutive invalid logon attempts and the lockout time period. Care should be taken so that the lockout mechanism itself cannot be used to deny service to legitimate users.",
    "implementation_guidance" => "Configure lockout after 5 consecutive failures with a 30-minute automatic unlock or admin-unlock. Ensure lockout events generate audit records and alert the security team.",
    "check"                   => "Test lockout by entering invalid credentials the defined number of times. Verify automatic unlock after the defined period. Confirm audit logs capture the lockout event.",
    "related_controls"        => "AC-2, AU-2, AU-6, IA-5"
  },
  "AU-02" => {
    "supplemental_guidance"   => "Audit record generation is a fundamental security activity. Organizations should coordinate with other entities requiring audit information and determine which events are auditable given the available audit capability.",
    "implementation_guidance" => "Define the minimum set of auditable events in policy. Configure the SIEM to ingest all required event categories. Validate completeness of event coverage quarterly.",
    "check"                   => "Review the list of auditable events against NIST AU-2 requirements. Verify each event type is being captured in the SIEM. Confirm event coverage has been reviewed within the past year.",
    "fix"                     => "Enable missing event source integrations; update the SIEM ingestion configuration to include all required event categories.",
    "org_ref"                 => "POL-AU-001 Section 3.1; PROC-AU-002",
    "related_controls"        => "AC-6, AC-17, AU-3, AU-4, AU-5, AU-6, AU-7, AU-12, MA-4, MP-2, MP-4, SI-4"
  },
  "AU-03" => {
    "supplemental_guidance"   => "Audit record content that may be necessary to satisfy the requirement includes: time stamps, source and destination addresses, user/process identifiers, event descriptions, success/failure indications, filenames involved, and access control or flow control rules invoked.",
    "implementation_guidance" => "Validate that all audit events include: ISO 8601 timestamp (UTC), event type code, source IP, user identifier, outcome (success/failure), and affected resource. Use structured logging (JSON) for all audit events.",
    "check"                   => "Sample a minimum of 50 audit records; verify all required fields are present and populated. Check for any null or placeholder values in required fields.",
    "related_controls"        => "AU-2, AU-7, AU-8, AU-9, AU-12, SI-7"
  },
  "IA-02" => {
    "supplemental_guidance"   => "Multifactor authentication requires two or more different factors to achieve authentication. Individual authenticator types include passwords, hardware tokens, OTP devices, smart cards, biometrics, and cryptographic keys.",
    "implementation_guidance" => "Enforce MFA for all organizational users accessing the system. Phishing-resistant MFA (FIDO2/WebAuthn or PIV/CAC) is required for privileged access. Document exceptions and obtain CISO approval.",
    "check"                   => "Verify MFA is enforced at the IdP level with no bypass paths. Test MFA enforcement for both privileged and non-privileged accounts. Confirm MFA policies cannot be disabled by end users.",
    "fix"                     => "Remove any MFA exception policies; enforce enrollment for all user accounts; disable legacy authentication protocols (Basic Auth, NTLM).",
    "org_ref"                 => "POL-IA-001; Enterprise MFA Standard v2.1",
    "nist_references"         => "NIST SP 800-53 Rev 5 IA-2; NIST SP 800-63B; FIPS 140-3",
    "related_controls"        => "AC-2, AC-3, AC-14, AC-17, AC-18, IA-5, IA-8, MA-4, SA-8, SC-8"
  },
  "CA-07" => {
    "supplemental_guidance"   => "Continuous monitoring is the ongoing observation, assessment, analysis, and diagnosis of the security state of information systems to support risk management decisions. The frequency of assessment is based on the risk tolerance of the organization.",
    "implementation_guidance" => "Implement automated continuous monitoring using a SIEM with real-time alerting. Conduct automated vulnerability scanning weekly. Review monitoring dashboards daily; escalate anomalies per the IR procedure.",
    "check"                   => "Review continuous monitoring strategy documentation; verify automated scanning is active; confirm alerts are being triaged within the defined SLA; check that monitoring results feed into the POA&M process.",
    "related_controls"        => "CA-2, CA-5, CA-6, IA-5, IR-4, IR-5, PL-2, RA-3, RA-5, SA-11, SA-12, SI-2, SI-4"
  }
}.freeze

inline_count = 0
INLINE_CATALOG_GUIDANCE.each do |ctrl_id, guidance|
  updated = CatalogControl.where(control_id: ctrl_id)
                           .update_all(guidance_data: guidance)
  inline_count += updated
end
puts "  Inline demo guidance applied to #{inline_count} catalog control(s)"

puts "Done! Demo SSP and SAR documents seeded."
