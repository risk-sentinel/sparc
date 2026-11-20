# frozen_string_literal: true

require "json"

# Validates every Certification Package Overview the FedRAMP Marketplace
# publishes (#1354, #1384): a local report, not a CI gate.
#
#   bin/rails "fedramp:marketplace_check[/path/to/marketplace-fedramp-gov-data]"
#
# Reads fedramp-frc-cso-pkg.json from a checkout of
# https://github.com/FedRAMP/marketplace-fedramp-gov-data and puts each record
# of .data["frc-cso-pkg"] through DocumentValidationService, the validator
# every upload and pull uses. It answers "what would SPARC say about the
# packages providers actually publish?" and shows which rules they break most.
#
# NIST SP 800-53: SI-10 (information input validation), CA-7 (continuous
# monitoring: the same checks, run across the whole marketplace).
class FedrampMarketplaceCheck
  class Error < StandardError; end

  FILE = "fedramp-frc-cso-pkg.json"
  DOCUMENT_TYPE = "certification-package-overview"
  TOP = 15
  # A record SPARC could not check at all, the name ReceivedDocumentService
  # stores such a failure under.
  UNREADABLE = "readable"
  CHECKS = [ "schema", "completeness", UNREADABLE ].freeze

  Report = Struct.new(:source, :total, :valid, :invalid, :by_check, :top_errors, :trust_center, keyword_init: true) do
    def to_text
      lines = [ "FedRAMP Marketplace package overviews: #{source}",
                "  total:                    #{total}",
                "  valid:                    #{valid}",
                "  invalid:                  #{invalid}" ]
      CHECKS.each { |check| lines << format("    with a %-21s %d", "#{check} error:", by_check.fetch(check, 0)) }
      lines << "  with a trust-center URL:  #{trust_center}"
      CHECKS.each do |check|
        rows = top_errors.fetch(check, [])
        lines << "" << "Top #{TOP} #{check} errors (occurrences, records, pointer, message):"
        lines << "  (none)" if rows.empty?
        rows.each { |r| lines << format("  %5d %5d  %s  %s", r[:count], r[:records], r[:pointer].presence || "/", r[:message]) }
      end
      lines.join("\n")
    end
  end

  def self.call(dir) = new(dir).call

  def initialize(dir)
    @dir = dir.to_s
  end

  def call
    records = load_records
    tallies = Hash.new { |h, k| h[k] = { count: 0, records: 0 } }
    by_check = Hash.new(0)
    valid = 0

    records.each do |record|
      errors = errors_for(record)
      valid += 1 if errors.empty?
      errors.map { |e| e[:check] }.uniq.each { |check| by_check[check] += 1 }
      errors.group_by { |e| key_for(e) }.each do |key, found|
        tallies[key][:count] += found.size
        tallies[key][:records] += 1
      end
    end

    Report.new(source: File.join(@dir, FILE), total: records.size, valid: valid, invalid: records.size - valid,
               by_check: by_check.sort.to_h, top_errors: top(tallies),
               trust_center: records.count { |r| trust_center?(r) })
  end

  private

  def load_records
    path = File.join(@dir, FILE)
    raise Error, "#{path} not found: name a checkout of FedRAMP/marketplace-fedramp-gov-data" unless File.file?(path)

    records = JSON.parse(File.read(path)).dig("data", "frc-cso-pkg")
    raise Error, "#{path} has no data.frc-cso-pkg list" unless records.is_a?(Array)

    records
  rescue JSON::ParserError => e
    raise Error, "#{path} is not valid JSON: #{e.message.lines.first.to_s.strip}"
  end

  # Every record is a package overview, so the type is named rather than
  # detected; a record whose own $schema says otherwise is reported unreadable.
  def errors_for(record)
    DocumentValidationService.call(JSON.generate(record), format: "fedramp", document_type: DOCUMENT_TYPE).errors
  rescue DocumentValidationService::Error, FedrampPackageSchemas::Error => e
    [ { check: UNREADABLE, pointer: "", message: e.message } ]
  end

  # One row per rule broken, not per array position: /certifiedServices/3/x
  # and /certifiedServices/0/x are the same failure.
  def key_for(error)
    [ error[:check], generalize(error[:pointer]), generalize(error[:message]) ]
  end

  def generalize(text) = text.to_s.gsub(%r{/\d+(?=/|`|\z)}, "/*")

  def top(tallies)
    tallies.group_by { |(check, _, _), _| check }.sort.to_h do |check, rows|
      ranked = rows.sort_by { |(_, pointer, message), t| [ -t[:count], pointer, message ] }.first(TOP)
      [ check, ranked.map { |(_, pointer, message), t| { pointer: pointer, message: message, **t } } ]
    end
  end

  # A record may hold any JSON value, so each level is checked before it is read.
  def trust_center?(record)
    properties = record["serviceProperties"] if record.is_a?(Hash)
    trust_center = properties["trustCenter"] if properties.is_a?(Hash)
    url = trust_center["url"] if trust_center.is_a?(Hash)
    url.is_a?(String) && url.strip.present?
  end
end
