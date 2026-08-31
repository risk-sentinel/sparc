#!/usr/bin/env ruby
# frozen_string_literal: true

# Evaluate a threshold band against an HDF **v3** document (#1067).
#
# WHY THIS EXISTS
#
# Amendments and thresholds could not both work. Measured on hdf-libs 3.5.1:
#
#   * `hdf amend apply` needs **v3** (`baselines[].requirements[]`). Given v3 it
#     works correctly — a dispositioned finding becomes `notApplicable` with
#     `statusOverrides` populated.
#   * `saf validate threshold` reads only **v2** (`profiles[].controls[]`).
#   * The bridge between them — `hdf convert --from hdf --to hdf@2` — is LOSSY
#     and drops `effectiveStatus`. Measured: an amended v3 carrying
#     `notApplicable: 2` returns as `failed: 4`, identical to no amendment.
#
# So every band was applied to a RAW count, and no band could be justified by
# "these findings are dispositioned" — which is the whole point of having a
# disposition register.
#
# This evaluates the same band grammar directly on v3, so the amended document
# is the one that gets gated. It is deliberately a small surface: the bands we
# actually use are counts.
#
# NOT A GENERAL saf REPLACEMENT. It implements `failed.<severity>.{max,min}`,
# `error.total.max` and `passed.total.min` — the subset our threshold files use.
# An unrecognised key is a hard ERROR rather than a silent skip: a band nobody
# evaluates is exactly the defect this milestone exists to remove, and quietly
# ignoring `compliance.min` would recreate it.
#
# Usage:
#   hdf_threshold_v3.rb --input amended.json --threshold thresholds/x.yml

require "json"
require "optparse"
require "yaml"

options = {}
parser = OptionParser.new do |opts|
  opts.banner = "Usage: hdf_threshold_v3.rb --input FILE --threshold FILE"
  opts.on("--input FILE", "HDF v3 document (baselines[])") { |v| options[:input] = v }
  opts.on("--threshold FILE", "Threshold YAML") { |v| options[:threshold] = v }
  opts.on("-h", "--help") { puts opts; exit 0 }
end
parser.parse!

%i[input threshold].each do |required|
  next if options[required]

  warn "hdf_threshold_v3: --#{required} is required"
  warn parser
  exit 2
end

[ options[:input], options[:threshold] ].each do |path|
  next if File.file?(path)

  warn "hdf_threshold_v3: #{path} does not exist"
  exit 2
end

begin
  doc = JSON.parse(File.read(options[:input]))
rescue JSON::ParserError => e
  # Fatal, and deliberately so. `saf validate threshold` EXITS 0 on input it
  # cannot parse — the defect CI-1 found — so a document we cannot read must
  # never be scored as a pass.
  warn "hdf_threshold_v3: #{options[:input]} is not valid JSON: #{e.message}"
  exit 1
end

baselines = doc["baselines"]
unless baselines.is_a?(Array) && !baselines.empty?
  warn "hdf_threshold_v3: #{options[:input]} has no baselines[] — expected HDF v3. " \
       "A v2 document (profiles[]) cannot carry effectiveStatus and must not be " \
       "gated here."
  exit 1
end

# Severity bands follow impact, matching how saf buckets them, so a band written
# for saf means the same thing here.
def severity_for(impact)
  case impact.to_f
  when 0.9..1.0 then "critical"
  when 0.7...0.9 then "high"
  when 0.4...0.7 then "medium"
  when 0.01...0.4 then "low"
  else "none"
  end
end

# effectiveStatus is what amendment sets; fall back to the requirement's own
# status, then to its results. Reading effectiveStatus FIRST is the entire point
# of this script — it is the field the v2 downgrade destroys.
def status_for(requirement)
  effective = requirement["effectiveStatus"].to_s
  return effective unless effective.empty?

  own = requirement["status"].to_s
  return own unless own.empty?

  statuses = Array(requirement["results"]).map { |r| r["status"].to_s }
  return "error"    if statuses.include?("error")
  return "failed"   if statuses.include?("failed")
  return "passed"   if statuses.include?("passed")
  return "skipped"  if statuses.include?("skipped")

  "none"
end

counts = Hash.new(0)
total_requirements = 0
baselines.each do |baseline|
  Array(baseline["requirements"]).each do |requirement|
    total_requirements += 1
    status = status_for(requirement)
    severity = severity_for(requirement["impact"])
    counts["#{status}.#{severity}"] += 1
    counts["#{status}.total"] += 1
  end
end

threshold = YAML.safe_load_file(options[:threshold]) || {}

SUPPORTED_STATUSES = %w[failed error passed skipped].freeze
SUPPORTED_BOUNDS   = %w[max min].freeze

violations = []
threshold.each do |status, severities|
  unless SUPPORTED_STATUSES.include?(status)
    warn "hdf_threshold_v3: unsupported threshold key #{status.inspect} in " \
         "#{options[:threshold]} — refusing to evaluate a band this tool does " \
         "not implement rather than skipping it silently"
    exit 1
  end
  unless severities.is_a?(Hash)
    warn "hdf_threshold_v3: #{status.inspect} must map severities to bounds"
    exit 1
  end

  severities.each do |severity, bounds|
    unless bounds.is_a?(Hash)
      warn "hdf_threshold_v3: #{status}.#{severity} must map max/min to a number"
      exit 1
    end

    actual = counts["#{status}.#{severity}"]
    bounds.each do |bound, limit|
      unless SUPPORTED_BOUNDS.include?(bound)
        warn "hdf_threshold_v3: unsupported bound #{bound.inspect} under #{status}.#{severity}"
        exit 1
      end

      if bound == "max" && actual > limit
        violations << "#{status}.#{severity}.max: received #{actual}, allowed #{limit}"
      elsif bound == "min" && actual < limit
        violations << "#{status}.#{severity}.min: received #{actual}, required #{limit}"
      end
    end
  end
end

summary = %w[failed error passed skipped]
          .map { |s| "#{s}=#{counts["#{s}.total"]}" }.join(" ")
suppressed = counts["notApplicable.total"]

puts "hdf_threshold_v3: #{File.basename(options[:input])} — #{total_requirements} requirement(s): #{summary}" \
     "#{suppressed.positive? ? " notApplicable=#{suppressed} (amended)" : ''}"

if violations.empty?
  # The positive assertion. CI-1 found that a rc-only check scores an
  # unparseable document as a pass, so callers should grep for this line rather
  # than trust the exit code alone.
  puts "All validation tests passed"
  exit 0
end

violations.each { |v| warn "::error::#{File.basename(options[:threshold])} #{v}" }
warn "hdf_threshold_v3: #{violations.length} band(s) breached"
exit 1
