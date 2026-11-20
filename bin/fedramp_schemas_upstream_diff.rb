#!/usr/bin/env ruby
# frozen_string_literal: true

# #1354 / #1384 — has FedRAMP moved on from the package schemas SPARC vendors?
#
#   bin/fedramp_schemas_upstream_diff.rb               # FedRAMP/schemas main on GitHub
#   bin/fedramp_schemas_upstream_diff.rb --ref <sha>   # ...or another ref
#   bin/fedramp_schemas_upstream_diff.rb --published   # the copies at https://www.fedramp.gov/schemas/
#   bin/fedramp_schemas_upstream_diff.rb --dir DIR     # ...or a checkout on disk (no network)
#
# SPARC validates against the vendored copies in lib/data/fedramp/schemas and
# never fetches them. This is the other half: it fetches upstream and reports
# what a re-vendor would change, schema by schema, with each file's
# $schemaVersion before and after. Files are compared as parsed JSON, because
# fedramp.gov serves them minified.
#
# --published can only check the files SPARC already has: fedramp.gov
# publishes no index, so a NEW schema shows up only with --ref or --dir.
#
# Exit status:
#   0  no drift
#   1  drift — the report says what changed
#   2  could not compare (a fetch failed, a file was unreadable)
#
# FAILS CLOSED: a comparison that did not happen is exit 2, never a pass.
#
# NIST SP 800-53 Rev 5: CM-3 (a change to an external baseline is detected
# before it is applied), SA-9 / SR-3 (external source monitored), CA-7.
require "json"
require "net/http"
require "optparse"
require "uri"

REPO_ROOT = File.expand_path("..", __dir__)
VENDORED_DIR = File.join(REPO_ROOT, "lib/data/fedramp/schemas")
SCHEMA_FILE = /\Afedramp-.+-schema-\d{4}-\d{2}-\d{2}\.json\z/
RAW_URL = "https://raw.githubusercontent.com/FedRAMP/schemas/%<ref>s/%<file>s"
TREE_URL = "https://api.github.com/repos/FedRAMP/schemas/git/trees/%<ref>s"
PUBLISHED_URL = "https://www.fedramp.gov/schemas/%<file>s"

def fail_closed(message)
  warn "fedramp_schemas_upstream_diff: #{message}"
  exit 2
end

def get(url)
  uri = URI(url)
  response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 15, read_timeout: 60) do |http|
    http.request(Net::HTTP::Get.new(uri, "User-Agent" => "sparc-fedramp-schemas-diff"))
  end
  fail_closed("GET #{uri} answered #{response.code}") unless response.is_a?(Net::HTTPSuccess)
  response.body
rescue SocketError, SystemCallError, Net::OpenTimeout, Net::ReadTimeout, OpenSSL::SSL::SSLError => e
  fail_closed("could not fetch #{url}: #{e.class}: #{e.message}")
end

def parse(text, label)
  JSON.parse(text)
rescue JSON::ParserError => e
  fail_closed("#{label} is not JSON: #{e.message}")
end

def schema_files(names) = names.grep(SCHEMA_FILE).sort

options = { ref: "main" }
OptionParser.new do |o|
  o.on("--ref REF") { |v| options[:ref] = v }
  o.on("--published") { options[:published] = true }
  o.on("--dir DIR") { |v| options[:dir] = v }
end.parse!

vendored = schema_files(Dir.children(VENDORED_DIR)).to_h do |file|
  [ file, parse(File.read(File.join(VENDORED_DIR, file)), file) ]
end
fail_closed("no vendored schemas in #{VENDORED_DIR}") if vendored.empty?

source, upstream =
  if options[:dir]
    dir = options[:dir]
    fail_closed("#{dir} is not a directory") unless File.directory?(dir)
    [ dir, schema_files(Dir.children(dir)).to_h { |f| [ f, parse(File.read(File.join(dir, f)), f) ] } ]
  elsif options[:published]
    [ "https://www.fedramp.gov/schemas/ (vendored files only)",
      vendored.keys.to_h { |f| [ f, parse(get(format(PUBLISHED_URL, file: f)), f) ] } ]
  else
    ref = options[:ref]
    tree = parse(get(format(TREE_URL, ref: ref)), "the FedRAMP/schemas tree at #{ref}")
    names = Array(tree["tree"]).select { |e| e["type"] == "blob" }.map { |e| e["path"] }
    [ "FedRAMP/schemas@#{ref}",
      schema_files(names).to_h { |f| [ f, parse(get(format(RAW_URL, ref: ref, file: f)), f) ] } ]
  end

changed = (vendored.keys & upstream.keys).reject { |f| vendored[f] == upstream[f] }
added = upstream.keys - vendored.keys
removed = vendored.keys - upstream.keys

puts "Compared #{vendored.size} vendored FedRAMP schema(s) with #{source}."
if changed.empty? && added.empty? && removed.empty?
  puts "No FedRAMP schema drift."
  exit 0
end

changed.each do |f|
  puts "CHANGED  #{f}: $schemaVersion #{vendored[f]['$schemaVersion'].inspect} -> #{upstream[f]['$schemaVersion'].inspect}"
end
added.each { |f| puts "ADDED    #{f}: $schemaVersion #{upstream[f]['$schemaVersion'].inspect}" }
removed.each { |f| puts "REMOVED  #{f}" }
puts "Re-vendor: see re_vendor in lib/data/fedramp/fedramp-schemas.provenance.json."
exit 1
