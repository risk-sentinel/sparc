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
#   trivy_selfcheck.rb --report trivy.json --image sparc:abc123
#   trivy_selfcheck.rb --report trivy.json --root rootfs --warn-only
#
# --image checks the paths INSIDE the image in a single `docker run`, so CI does
# not have to export a ~650 MB rootfs just to answer "does this file exist".

require "json"
require "open3"
require "optparse"
require "set"

options = { warn_only: false }
parser = OptionParser.new do |opts|
  opts.banner = "Usage: trivy_selfcheck.rb --report FILE --root DIR [--warn-only]"
  opts.on("--report FILE", "Trivy JSON report") { |v| options[:report] = v }
  opts.on("--root DIR", "Filesystem root the report describes") { |v| options[:root] = v }
  opts.on("--image REF", "Image the report describes (checked via docker run)") { |v| options[:image] = v }
  opts.on("--warn-only", "Report without failing (adoption ramp)") { options[:warn_only] = true }
  opts.on("-h", "--help") { puts opts; exit 0 }
end
parser.parse!

unless options[:report]
  warn "trivy_selfcheck: --report is required"
  warn parser
  exit 2
end

if options[:root].nil? == options[:image].nil?
  warn "trivy_selfcheck: pass exactly one of --root or --image"
  warn parser
  exit 2
end

unless File.file?(options[:report])
  warn "trivy_selfcheck: #{options[:report]} does not exist"
  exit 2
end
if options[:root] && !File.directory?(options[:root])
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

root  = options[:root]&.chomp("/")
image = options[:image]

# Which of `paths` exist inside the image. ONE `docker run`, paths fed on stdin
# so the argument list cannot overflow and no path needs shell-quoting.
#
# A docker failure is FATAL rather than "nothing exists" — treating an
# unreachable daemon as "every path is missing" would turn a broken runner into
# a wall of fake phantoms, the same class of lie this script exists to catch.
def paths_present_in_image(image, paths)
  return Set.new if paths.empty?

  # `if` rather than `[ -e ] && printf`: with `&&` the loop's exit status is the
  # LAST test, so a final path that legitimately does not exist makes the whole
  # command exit 1 and look like a docker failure. Same shape as the CI-1 gate
  # loop that errexit killed. `exit 0` makes the success signal explicit.
  script = 'while IFS= read -r p; do if [ -e "/$p" ]; then printf "%s\n" "$p"; fi; done; exit 0'
  # THE TRAILING NEWLINE IS LOAD-BEARING. `read` returns non-zero when it reaches
  # EOF without seeing its delimiter, so with `paths.join("\n")` the LAST path is
  # read into `p` and then the loop condition fails before the body runs — the
  # path is never tested and is reported as a phantom.
  #
  # It cost a full CI cascade on 2026-09-03. Trivy's DB had just added a resolv
  # advisory, which made the report carry EXACTLY ONE gemspec finding; the one
  # path was the last path, so 100% of findings were dropped and a real,
  # present-on-disk file was called phantom. trivy_container_scan failed, never
  # uploaded syft-container-sbom, and grype_sbom_scan / normalize_hdf /
  # bundle_results / security_gate all failed behind it.
  #
  # The bug survived because the spec only ever exercised --root, which resolves
  # existence with File.exist? in Ruby and never runs this loop at all.
  out, err, status = Open3.capture3("docker", "run", "--rm", "-i", "--entrypoint", "sh",
                                    image, "-c", script, stdin_data: paths.join("\n") + "\n")
  unless status.success?
    warn "trivy_selfcheck: could not inspect #{image}: #{err.strip}"
    exit 2
  end

  Set.new(out.split("\n").map(&:strip).reject(&:empty?))
end

# name-version from a gemspec basename. Gem versions may carry more than three
# segments (erb-4.0.4.1) and platform suffixes (nokogiri-1.19.1-aarch64-linux),
# so split on the LAST hyphen that begins a digit and keep the remainder.
# A Target is a path only if it looks like one. Trivy uses the same field for
# human-readable descriptions ("sparc:sha (redhat 9.8)", "Ruby", "Node.js"), and
# those must never be asserted to exist on disk.
def target_is_path?(target)
  return false if target.empty?
  return false unless target.include?("/")
  return false if target.match?(/[()\s]/)

  true
end

def parse_gemspec_basename(base)
  stem = base.sub(/\.gemspec\z/, "")
  m = stem.match(/\A(?<name>.+?)-(?<version>\d[^-]*(?:-.+)?)\z/)
  return nil unless m

  [ m[:name], m[:version] ]
end

phantom_paths = []
version_mismatches = []
pathless = Hash.new(0)

# Pass 1 — collect every path the report asserts, so existence is resolved in
# ONE operation rather than once per finding.
findings = []
targets = []
Array(report["Results"]).each do |result|
  target = result["Target"].to_s
  Array(result["Vulnerabilities"]).each do |vuln|
    pkg_path = vuln["PkgPath"].to_s
    if pkg_path.empty?
      # gobinary findings carry the path on the Result target instead. But an
      # OS-package result's Target is a DESCRIPTION, not a path — e.g.
      # "sparc:abc123 (redhat 9.8)" — and asserting that a description exists on
      # disk would fail every RHEL finding. Only treat a Target as a path when it
      # looks like one, and say so rather than silently skipping.
      targets << target if target_is_path?(target)
      next
    end
    findings << { path: pkg_path, pkg: vuln["PkgName"], version: vuln["InstalledVersion"].to_s,
                  id: vuln["VulnerabilityID"], type: result["Type"].to_s, target: target }
  end
end

all_paths = (findings.map { |f| f[:path] } + targets).uniq

present =
  if image
    paths_present_in_image(image, all_paths)
  else
    Set.new(all_paths.select { |rel| File.exist?(File.join(root, rel)) })
  end

where = image ? "image #{image}" : root

# Pass 2 — classify.
findings.each do |f|
  unless present.include?(f[:path])
    phantom_paths << f
    next
  end

  next unless f[:path].end_with?(".gemspec")

  parsed = parse_gemspec_basename(File.basename(f[:path]))
  next unless parsed

  _name, on_disk_version = parsed
  next if on_disk_version == f[:version]

  version_mismatches << { path: f[:path], reported: f[:version], on_disk: on_disk_version, id: f[:id] }
end

targets.tally.each do |target, count|
  pathless[target] += count unless present.include?(target)
end

checked = findings.length

puts "trivy_selfcheck: #{checked} finding path(s) checked against #{where}"

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
    if root
      siblings = Dir[File.join(root, File.dirname(p[:path]), "#{p[:pkg]}-*")].map { |s| File.basename(s) }
      puts "    actually there: #{siblings.empty? ? '(nothing by that name)' : siblings.join(', ')}"
    end
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
