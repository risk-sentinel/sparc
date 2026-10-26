#!/usr/bin/env ruby
# frozen_string_literal: true

# Builds spec/fixtures/files/profiles/NIST_SP-800-53_rev5_<BASELINE>-tailored_profile.json:
# NIST's own Rev 5 baseline profile (MODERATE by default) with EVERY organization-defined
# parameter of every selected control set, the way a consumer's profile
# carries their policies.
#
# The end-to-end spec (spec/integration/nist_moderate_end_to_end_spec.rb)
# imports it and follows every value through the baseline, the SSP and the
# OSCAL exports. Profile import used to drop every Rev 5 id (`ac-01_odp.05`),
# and a fixture with no parameters could never have shown it.
#
# Deterministic: the same inputs always give the same file.
#   - a value parameter is set to a plausible organization-defined value,
#     chosen by its label ("frequency" -> "annually", "personnel or roles" ->
#     "the Information System Security Officer (ISSO)"), except
#     ac-01_odp.05 = "365" (the policy review frequency a consumer set). No two
#     parameters of one control share a value, so a value stored against the
#     wrong parameter still fails a spec that follows it. A label with no
#     values below gets a readable phrase from the label and the family.
#     (These were "TAILORED[<param-id>]" markers until 2026-10-26: easy to trace,
#     but a reviewer reading the screens took them for code.)
#   - a selection is set to its first choice;
#   - an aggregate (ac-1_prm_1) is NOT set: NIST sets its parts and the
#     aggregate stands for them.
#
# Usage: bin/generate_tailored_profile_fixture.rb [LOW|MODERATE|HIGH]

require "json"

ROOT = File.expand_path("..", __dir__)
FIXTURES = File.join(ROOT, "spec/fixtures/files")
CATALOG = File.join(FIXTURES, "catalogs/NIST_SP-800-53_rev5_catalog.json")
BASELINE = (ARGV.first || "MODERATE").upcase
abort "baseline must be LOW, MODERATE or HIGH" unless %w[LOW MODERATE HIGH].include?(BASELINE)
PROFILE = File.join(FIXTURES, "profiles/NIST_SP-800-53_rev5_#{BASELINE}-baseline_profile.json")
OUTPUT = File.join(FIXTURES, "profiles/NIST_SP-800-53_rev5_#{BASELINE}-tailored_profile.json")
UUIDS = {
  "LOW" => "2a7c9e14-5b3d-4f6a-8c1e-7d9b0f2a4c61",
  "MODERATE" => "6d1f3c52-8b7e-4a4e-9c1d-3f5a2b7c9e01",
  "HIGH" => "9e4b2d71-3c8f-4a1b-b6d2-5f0e8c7a1d93"
}.freeze

EXPLICIT = { "ac-01_odp.05" => "365" }.freeze

# Plausible values by catalog label. Invented and generic: no real
# organization, system or person.
VALUES = {
  "frequency" => [ "annually", "quarterly", "monthly", "every 30 days", "every 90 days", "weekly",
                   "every 180 days", "every three years", "daily" ],
  "frequencies" => [ "annually", "quarterly", "monthly" ],
  "personnel or roles" => [ "the Information System Security Officer (ISSO)", "the System Owner",
                            "the Chief Information Security Officer (CISO)", "system administrators",
                            "the Authorizing Official", "the Information System Security Manager (ISSM)",
                            "the Privacy Officer", "the Change Control Board", "all system users",
                            "the Incident Response Team lead", "the Security Operations Center (SOC)" ],
  "events" => [ "a significant change to the system, a security incident, or a new federal requirement",
                "a reorganization, an audit finding, or a change in applicable law",
                "an assessment finding or a change in the threat environment",
                "a security incident or a change to the authorization boundary" ],
  "time period" => [ "30 days", "90 days", "24 hours", "15 minutes", "7 days", "1 year", "72 hours", "60 days" ],
  "official" => [ "the Chief Information Security Officer (CISO)", "the Chief Information Officer (CIO)",
                  "the Senior Agency Official for Privacy (SAOP)", "the Information System Security Manager (ISSM)" ],
  "automated mechanisms" => [ "the enterprise configuration management tool", "the SIEM and its alerting rules",
                              "the identity governance platform", "endpoint detection and response (EDR) agents",
                              "the vulnerability scanning service" ],
  "system components" => [ "web servers, database servers and network devices", "all production servers",
                           "boundary firewalls and load balancers", "workstations and laptops" ],
  "controls" => [ "the controls in the system's approved baseline", "the controls inherited from the hosting provider",
                  "compensating controls approved by the Authorizing Official" ],
  "information" => [ "controlled unclassified information (CUI)", "personally identifiable information (PII)",
                     "audit records and security logs", "system configuration information" ],
  "software" => [ "the approved operating system images", "commercial off-the-shelf (COTS) applications",
                  "the system's open-source dependencies" ],
  "organizational elements" => [ "the Office of the CIO and the system program office", "the Security Operations Center",
                                 "the Privacy Office and the Office of General Counsel" ],
  "actions" => [ "disable the account and notify the ISSO", "isolate the affected component and open an incident",
                 "alert the SOC and preserve the logs" ],
  "action" => [ "lock the account", "terminate the session" ],
  "systems or system components" => [ "all production systems", "internet-facing system components",
                                      "systems that process CUI" ],
  "tests" => [ "functional security testing", "penetration testing", "regression testing of security functions" ],
  "types of digital media" => [ "USB flash drives, external hard drives and optical discs", "removable SSDs and SD cards",
                                "backup tapes" ],
  "types of non-digital media" => [ "paper records and printed reports", "microfilm", "printed configuration diagrams" ],
  "controlled areas" => [ "the data center and the network operations center", "secured equipment rooms",
                          "the badge-controlled office suite" ],
  "system media" => [ "hard drives, backup tapes and removable media", "decommissioned storage devices",
                      "printed output containing CUI" ],
  "sanitization techniques and procedures" => [ "NIST SP 800-88 purge or destroy, as the media requires",
                                                "cryptographic erase followed by verification",
                                                "degaussing and physical destruction" ],
  "transitional states or security-relevant events" => [ "system startup, restart and shutdown",
                                                         "a failover or recovery from backup",
                                                         "a change to the security configuration" ],
  "number" => [ "3", "5" ],
  "conditions" => [ "a pending investigation or a change in duties", "an expired agreement or a failed reinvestigation" ],
  "roles and responsibilities" => [ "those in the system's roles and responsibilities matrix",
                                    "those named in the incident response plan" ],
  "circumstances" => [ "a system outage or an emergency change", "a declared contingency event" ],
  "ports" => [ "TCP 443 and TCP 22", "UDP 53 and TCP 853" ],
  "protocols" => [ "HTTPS and SSH", "TLS 1.2 or later" ],
  "services" => [ "the web application and the API service", "DNS and NTP" ],
  "functions" => [ "remote administration and file sharing", "unused network services and legacy protocols" ],
  "key contingency personnel" => [ "the System Owner, the ISSO and the contingency plan coordinator",
                                   "the recovery team leads" ],
  "incident response personnel" => [ "the Incident Response Team", "the SOC analysts and the ISSO" ],
  "personnel" => [ "system administrators and the ISSO", "all personnel with privileged access" ],
  "individuals or roles" => [ "the ISSO and the System Owner", "the Privacy Officer" ],
  "external organizations" => [ "US-CERT (CISA)", "the hosting provider's security team", "law enforcement as required" ],
  "firmware" => [ "BIOS/UEFI and network device firmware", "storage controller firmware" ],
  "techniques and methods" => [ "static and dynamic code analysis", "threat modeling and code review" ],
  "event types" => [ "successful and failed logons, privilege use and account changes",
                     "administrative actions and configuration changes" ],
  "assessment frequency" => [ "annually", "every three years" ],
  "location" => [ "the alternate processing site", "the primary data center" ],
  "software programs" => [ "unauthorized peer-to-peer file sharing software", "unapproved browser extensions" ],
  "mobile devices" => [ "government-furnished smartphones and tablets", "laptops used for remote access" ],
  "terms and conditions" => [ "the interconnection security agreement", "the rules of behavior for external systems" ]
}.freeze

# A label with no entry above but one of these words takes that pool:
# "frequency to conduct" reads as a frequency, "time period by authenticator
# type" as a time period.
KEYWORDS = [
  [ "frequenc", "frequency" ], [ "time period", "time period" ], [ "personnel", "personnel or roles" ],
  [ "roles", "personnel or roles" ], [ "official", "official" ], [ "event", "events" ],
  [ "system components", "system components" ], [ "mechanism", "automated mechanisms" ]
].freeze

FAMILIES = {}

# A plausible value for one value parameter, different from the values its
# control already holds.
def plausible_value(param, control_id, used)
  label = param["label"].to_s.strip
  pool = VALUES.fetch(label.downcase) { VALUES.fetch(KEYWORDS.find { |word, _| label.downcase.include?(word) }&.last, []) }
  # In pool order: each list starts with the most typical answer, so a
  # control's first "personnel or roles" is the ISSO and its first "frequency"
  # is annually; later parameters of the same control take the next one.
  choice = pool.find { |value| !used.include?(value) }
  return choice if choice

  family = FAMILIES.fetch(control_id[/\A[a-z]+/], "system")
  base = "#{label.empty? ? "Values" : label[0].upcase + label[1..]} as defined in the #{family} procedures"
  candidate = base
  candidate = "#{base} (#{param["id"]})" if used.include?(candidate)
  candidate
end

def walk(controls, &block)
  Array(controls).each do |control|
    block.call(control)
    walk(control["controls"], &block)
  end
end

def aggregate?(param) = Array(param["props"]).any? { |prop| prop["name"] == "aggregates" }

catalog = JSON.parse(File.read(CATALOG))
catalog.dig("catalog", "groups").each { |group| FAMILIES[group["id"]] = group["title"] }
profile = JSON.parse(File.read(PROFILE))

selected = profile.dig("profile", "imports").flat_map do |import|
  Array(import["include-controls"]).flat_map { |include| Array(include["with-ids"]) }
end.to_h { |id| [ id, true ] }

set_parameters = []
catalog.dig("catalog", "groups").each do |group|
  walk(group["controls"]) do |control|
    next unless selected[control["id"]]

    used = []
    Array(control["params"]).each do |param|
      next if aggregate?(param)

      id = param["id"]
      values = if EXPLICIT.key?(id)
        [ EXPLICIT[id] ]
      elsif param["select"]
        [ Array(param.dig("select", "choice")).first.to_s.strip ].reject(&:empty?)
      else
        [ plausible_value(param, control["id"], used) ]
      end
      used.concat(values)
      set_parameters << { "param-id" => id, "values" => values } unless values.empty?
    end
  end
end

tailored = profile.dup
tailored["profile"] = profile["profile"].merge(
  "uuid" => UUIDS.fetch(BASELINE),
  "metadata" => profile.dig("profile", "metadata").merge(
    "title" => "NIST Special Publication 800-53 Revision 5 #{BASELINE} IMPACT BASELINE (tailored fixture)",
    "last-modified" => "2026-10-26T00:00:00Z",
    "version" => "5.2.0-tailored",
    "remarks" => "SPARC test fixture: NIST's Rev 5 #{BASELINE} baseline with every organization-defined " \
                 "parameter set. Generated by bin/generate_tailored_profile_fixture.rb."
  ),
  "modify" => { "set-parameters" => set_parameters }
)

File.write(OUTPUT, "#{JSON.pretty_generate(tailored)}\n")
puts "#{OUTPUT.delete_prefix("#{ROOT}/")}: #{selected.size} controls, #{set_parameters.size} parameters set"
