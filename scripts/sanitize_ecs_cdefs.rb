#!/usr/bin/env ruby
# frozen_string_literal: true

# Refresh the ECS Fargate boundary CDEF fixtures used by the #817 end-to-end
# OSCAL pipeline proof.
#
# The source of truth for these component definitions is the sparc-iac repo
# (AWS/CDEF/ECS/). They are copied here — not referenced across repos — so the
# spec suite is hermetic and CI does not depend on a sibling checkout. Copying
# means they drift, hence this script: refreshing is one command, and
# spec/fixtures/files/components/ecs_boundary_spec.rb enforces that whatever
# lands here is still sanitized.
#
# Sanitization is deliberately narrow. The sparc-iac CDEFs are already
# generalized (ARNs carry <region>/<account> placeholders, UUIDs are synthetic,
# no real account IDs), so this only strips the remaining org-identifying
# strings. Narrow means reviewable: a broad regex sweep would quietly mangle
# control prose and nobody would notice.
#
# Usage:
#   ruby scripts/sanitize_ecs_cdefs.rb [path/to/sparc-iac]
#
# Defaults to ../sparc-iac relative to the repo root.

require "json"
require "fileutils"

REPO_ROOT = File.expand_path("..", __dir__)
DEST = File.join(REPO_ROOT, "spec/fixtures/files/components/ecs_boundary")

# Ordered: longest/most specific first, so a later rule cannot partially
# rewrite what an earlier one already replaced.
SUBSTITUTIONS = [
  [ "risk-sentinel.io/ns/oscal", "example.com/ns/oscal" ],
  [ "risk-sentinel.org",         "example.com" ],
  [ "risk-sentinel/",            "example-org/" ]
].freeze

# Anything matching these must NOT survive into the fixtures. Kept in sync with
# the guard in the fixture spec — that spec is the enforcement, this is the fix.
#
# The account-id pattern deliberately excludes hex/hyphen neighbours: the CDEFs
# are full of synthetic UUIDs whose final segment is twelve digits
# (11111111-0000-4000-8000-000000000001), and a naive \b\d{12}\b flags every one
# of them. A guard that cries wolf on every file gets switched off.
FORBIDDEN = [
  /risk-?sentinel/i,
  /(?<![0-9a-fA-F-])\d{12}(?![0-9a-fA-F-])/ # bare AWS account id
].freeze

def sanitize(text)
  SUBSTITUTIONS.reduce(text) { |acc, (from, to)| acc.gsub(from, to) }
end

source_root = ARGV[0] || File.expand_path("../sparc-iac", REPO_ROOT)
source_dir = File.join(source_root, "AWS/CDEF/ECS")

abort("source not found: #{source_dir}") unless Dir.exist?(source_dir)

files = Dir.glob(File.join(source_dir, "component-definition-*.json")).sort
abort("no component definitions under #{source_dir}") if files.empty?

# Sanitize and verify EVERYTHING before writing ANYTHING: a partial refresh
# that stops halfway leaves the fixture set internally inconsistent, and the
# boundary is only meaningful as a complete set.
problems = []
cleaned_files = files.to_h do |path|
  name = File.basename(path)
  cleaned = sanitize(File.read(path))

  FORBIDDEN.each do |pattern|
    next unless cleaned.match?(pattern)
    offending = cleaned[pattern]
    problems << "#{name}: still matches #{pattern.inspect} (#{offending.inspect})"
  end

  # Round-trip through the parser so a corrupt copy is caught here, not in CI.
  begin
    JSON.parse(cleaned)
  rescue JSON::ParserError => e
    problems << "#{name}: not valid JSON after sanitization — #{e.message}"
  end

  [ name, cleaned ]
end

if problems.any?
  warn "Sanitization incomplete — nothing written:"
  problems.each { |p| warn "  - #{p}" }
  exit 1
end

FileUtils.mkdir_p(DEST)
cleaned_files.each do |name, content|
  File.write(File.join(DEST, name), content)
  puts "  wrote #{name}"
end

puts "\n#{files.size} component definitions refreshed into #{DEST.sub("#{REPO_ROOT}/", '')}"
