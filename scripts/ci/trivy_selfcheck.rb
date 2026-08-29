#!/usr/bin/env ruby
# frozen_string_literal: true

# Assert that a Trivy report describes the artifact that was actually scanned
# (#1080).
#
# WHY THIS EXISTS
#
# Trivy reported 68 CRITICAL/HIGH against a UBI9 image where CI reported 0, and
# every one of the 33 gemspec findings named a package version that is NOT in
# the image:
#
#   trivy said                       on disk
#   activestorage-8.1.2.gemspec      activestorage-8.1.3.1.gemspec
#   rack-3.2.5.gemspec               rack-3.2.7.gemspec
#   net-imap 0.5.8 and 0.6.3         net-imap-0.6.6 only
#   35 Go CVEs in thruster/thrust    no thruster anywhere (removed in #639)
#
# Root cause is NOT established. Reproduced on trivy 0.69.3 AND 0.74.0, with a
# fresh cache dir, a --no-cache image rebuild, an explicit --platform, a
# `docker save` tarball, and a flattened `docker export` rootfs. An empty
# directory correctly returns 0, so the target IS read — and then findings are
# reported that are not in it.
#
# THE POINT: this check does not need the cause. It asserts the one invariant
# that the defect violates, so the failure is immediate and legible instead of
# costing a session to chase.
#
#   every reported PkgPath must EXIST, and the version encoded in that path
#   must EQUAL the reported InstalledVersion
#
# This is the CI-2 canary idea (#1048) applied to the scanner's own output: a
# scan must positively demonstrate that it examined what it claims to have
# examined. A finding is evidence only if the thing it describes is really
# there.
#
# Usage:
#   trivy_selfcheck.rb --report trivy.json --root /path/to/scanned/rootfs
#   trivy_selfcheck.rb --report trivy.json --root rootfs --warn-only

require "json"
require "optparse"

options = { warn_only: false }
parser = OptionParser.new do |opts|
  opts.banner = "Usage: trivy_selfcheck.rb --report FILE --root DIR [--warn-only]"
  opts.on("--report FILE", "Trivy JSON report") { |v| options[:report] = v }
  opts.on("--root DIR", "Filesystem root the report describes") { |v| options[:root] = v }
  opts.on("--warn-only", "Report without failing (adoption ramp)") { options[:warn_only] = true }
  opts.on("-h", "--help") { puts opts; exit 0 }
end
parser.parse!

%i[report root].each do |required|
  next if options[required]

  warn "trivy_selfcheck: --#{required} is required"
  warn parser
  exit 2
end

unless File.file?(options[:report])
  warn "trivy_selfcheck: #{options[:report]} does not exist"
  exit 2
end
unless File.directory?(options[:root])
  warn "trivy_selfcheck: #{options[:root]} is not a directory"
  exit 2
end

begin
  report = JSON.parse(File.read(options[:report]))
rescue JSON::ParserError => e
  # Fatal by design. An unreadable report must never score as "nothing wrong" —
  # that is the CI-1 defect (saf exiting 0 on input it could not parse).
  warn "trivy_selfcheck: #{options[:report]} is not valid JSON: #{e.message}"
  exit 1
end

root = options[:root].chomp("/")

# name-version from a gemspec basename. Gem versions may carry more than three
# segments (erb-4.0.4.1) and platform suffixes (nokogiri-1.19.1-aarch64-linux),
# so split on the LAST hyphen that begins a digit and keep the remainder.
def parse_gemspec_basename(base)
  stem = base.sub(/\.gemspec\z/, "")
  m = stem.match(/\A(?<name>.+?)-(?<version>\d[^-]*(?:-.+)?)\z/)
  return nil unless m

  [ m[:name], m[:version] ]
end

phantom_paths = []
version_mismatches = []
checked = 0
pathless = Hash.new(0)

Array(report["Results"]).each do |result|
  type = result["Type"].to_s
  Array(result["Vulnerabilities"]).each do |vuln|
    pkg_path = vuln["PkgPath"].to_s

    if pkg_path.empty?
      # gobinary findings carry the path on the Result target instead.
      target = result["Target"].to_s
      next if target.empty?

      unless File.exist?(File.join(root, target))
        pathless[target] += 1
      end
      next
    end

    checked += 1
    absolute = File.join(root, pkg_path)

    unless File.exist?(absolute)
      phantom_paths << { path: pkg_path, pkg: vuln["PkgName"], version: vuln["InstalledVersion"],
                         id: vuln["VulnerabilityID"], type: type }
      next
    end

    next unless pkg_path.end_with?(".gemspec")

    parsed = parse_gemspec_basename(File.basename(pkg_path))
    next unless parsed

    _name, on_disk_version = parsed
    reported = vuln["InstalledVersion"].to_s
    next if on_disk_version == reported

    version_mismatches << { path: pkg_path, reported: reported, on_disk: on_disk_version,
                            id: vuln["VulnerabilityID"] }
  end
end

puts "trivy_selfcheck: #{checked} finding path(s) checked against #{root}"

if phantom_paths.empty? && version_mismatches.empty? && pathless.empty?
  # Positive assertion, deliberately. A silent pass and "nothing was examined"
  # must never look the same.
  puts "trivy_selfcheck: every reported path exists and every version matches — report is consistent with the artifact"
  exit 0
end

unless phantom_paths.empty?
  puts
  puts "PATHS THAT DO NOT EXIST (#{phantom_paths.length} finding(s)):"
  phantom_paths.first(25).each do |p|
    puts "  #{p[:id]}  #{p[:pkg]} #{p[:version]}"
    puts "    reported at: #{p[:path]}"
    siblings = Dir[File.join(root, File.dirname(p[:path]), "#{p[:pkg]}-*")].map { |s| File.basename(s) }
    puts "    actually there: #{siblings.empty? ? '(nothing by that name)' : siblings.join(', ')}"
  end
  puts "  ... and #{phantom_paths.length - 25} more" if phantom_paths.length > 25
end

unless version_mismatches.empty?
  puts
  puts "VERSION DISAGREES WITH THE FILE ON DISK (#{version_mismatches.length}):"
  version_mismatches.first(25).each do |m|
    puts "  #{m[:id]}  reported #{m[:reported]}, file says #{m[:on_disk]}  (#{m[:path]})"
  end
end

unless pathless.empty?
  puts
  puts "SCAN TARGETS THAT DO NOT EXIST (#{pathless.length}):"
  pathless.each { |t, n| puts "  #{t}  (#{n} finding(s))" }
end

puts
message = "trivy report describes #{phantom_paths.length + version_mismatches.length + pathless.values.sum} " \
          "finding(s) that are not in the scanned artifact — see #1080"

if options[:warn_only]
  warn "::warning::#{message} (warn-only)"
  exit 0
end

warn "::error::#{message}"
warn "trivy_selfcheck: refusing to treat this report as evidence."
exit 1
