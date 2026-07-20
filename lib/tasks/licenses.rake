# frozen_string_literal: true

# ==============================================================================
# licenses.rake -- fetch SPDX license texts into LICENSES/ (#475)
# ==============================================================================
#
# Reads license-inventory.json (or a CI artifact path passed as an arg) and
# populates LICENSES/<spdx-id>.txt with canonical text from the SPDX
# license-list-data corpus. Regenerates LICENSES/README.md with a
# component-count map per license file.
#
# Why commit the texts? Apache 2.0 redistribution requirements and FedRAMP
# audit packages both expect the license text alongside the inventory. SPDX
# text is immutable per license version, so commit-and-forget is safe.
#
# Usage:
#   bin/rails licenses:fetch                       # uses ./license-inventory.json
#   bin/rails 'licenses:fetch[path/to/inv.json]'   # custom inventory path
#   bin/rails licenses:list                        # show what's missing
# ==============================================================================

require "net/http"
require "json"
require "uri"
require "fileutils"

namespace :licenses do
  SPDX_TEXT_BASE = "https://raw.githubusercontent.com/spdx/license-list-data/main/text"
  LICENSES_DIR = Rails.root.join("LICENSES")

  # SPDX expressions (with WITH ... or compound) need the bare license fetched;
  # we record the expression form in the README. Strings here are recognized
  # as "needs upstream-supplied text" rather than SPDX-fetchable.
  NON_SPDX_LICENSES = {
    "Brakeman Public Use License" => "Brakeman-Public-Use-License.txt",
    "BSD-3-clause-Cambridge WITH BINARY-LIBRARY-LIKE-PACKAGES-exception" =>
      "BSD-3-Clause-Cambridge-WITH-exception.txt"
  }.freeze

  desc "Fetch SPDX license texts referenced by license-inventory.json into LICENSES/"
  task :fetch, [ :inventory ] => :environment do |_t, args|
    inventory_path = args[:inventory] || "license-inventory.json"
    unless File.exist?(inventory_path)
      warn "Inventory file not found: #{inventory_path}"
      warn "Pass a path to the artifact: rake 'licenses:fetch[path/to/license-inventory.json]'"
      exit 1
    end

    inventory = JSON.parse(File.read(inventory_path))
    license_counts = (inventory["by_license"] || {}).transform_keys(&:to_s)

    FileUtils.mkdir_p(LICENSES_DIR)

    fetched, skipped, missing = [], [], []

    license_counts.each do |license, _info|
      next if license.nil? || license.strip.empty?

      if NON_SPDX_LICENSES.key?(license)
        target = LICENSES_DIR.join(NON_SPDX_LICENSES[license])
        if target.exist?
          skipped << license
        else
          warn "[#{license}] non-SPDX; needs manual curation at LICENSES/#{NON_SPDX_LICENSES[license]}"
          missing << license
        end
        next
      end

      # SPDX expressions (anything with WITH/AND/OR) — fetch the bare license
      # and let the README document the exception.
      base_spdx = license.split(/\s+(?:WITH|AND|OR)\s+/i).first
      target = LICENSES_DIR.join("#{base_spdx}.txt")

      if target.exist?
        skipped << license
        next
      end

      url = "#{SPDX_TEXT_BASE}/#{base_spdx}.txt"
      print "Fetching #{base_spdx}... "
      begin
        text = http_get(url)
        File.write(target, text)
        puts "ok (#{text.bytesize} bytes)"
        fetched << license
      rescue => e
        puts "FAILED (#{e.message})"
        missing << license
      end
    end

    write_readme(license_counts, missing)

    puts ""
    puts "Summary:"
    puts "  fetched: #{fetched.length}"
    puts "  skipped (already present): #{skipped.length}"
    puts "  missing / non-SPDX: #{missing.length}"
    puts "  README written: #{LICENSES_DIR.join('README.md')}"
  end

  desc "List licenses referenced by the inventory that have no committed text"
  task :list, [ :inventory ] => :environment do |_t, args|
    inventory_path = args[:inventory] || "license-inventory.json"
    unless File.exist?(inventory_path)
      warn "Inventory file not found: #{inventory_path}"
      exit 1
    end

    inventory = JSON.parse(File.read(inventory_path))
    (inventory["by_license"] || {}).each do |license, info|
      next if license.nil? || license.strip.empty?

      base_spdx = license.split(/\s+(?:WITH|AND|OR)\s+/i).first
      target = LICENSES_DIR.join(NON_SPDX_LICENSES[license] || "#{base_spdx}.txt")
      status = target.exist? ? "ok " : "MISS"
      puts "#{status}  count=#{info['count'].to_s.rjust(4)}  #{license}"
    end
  end

  def http_get(url)
    uri = URI(url)
    SparcHttp.start(uri) do |http|  # proxy-aware (#775)
      http.read_timeout = 30
      response = http.get(uri.request_uri)
      raise "HTTP #{response.code}" unless response.code.to_i == 200
      response.body.to_s.force_encoding("UTF-8")
    end
  end

  def write_readme(license_counts, missing)
    lines = []
    lines << "# SPARC License Texts"
    lines << ""
    lines << "Canonical text for every license referenced by SPARC's CycloneDX SBOM"
    lines << "inventory. Fetched from the SPDX license-list-data corpus by"
    lines << "`bin/rails licenses:fetch` (see `lib/tasks/licenses.rake`)."
    lines << ""
    lines << "Generated: `#{Time.now.utc.iso8601}`."
    lines << ""
    lines << "## Component count per license"
    lines << ""
    lines << "| File | Components | Notes |"
    lines << "| --- | ---: | --- |"

    license_counts.sort_by { |_lic, info| -info["count"].to_i }.each do |license, info|
      next if license.nil? || license.strip.empty?
      base = license.split(/\s+(?:WITH|AND|OR)\s+/i).first
      filename = NON_SPDX_LICENSES[license] || "#{base}.txt"
      note = NON_SPDX_LICENSES.key?(license) ? "non-SPDX; manually curated" : "SPDX canonical"
      note += "; missing — fetch failed" if missing.include?(license)
      lines << "| [`#{filename}`](#{filename}) | #{info['count']} | #{note} |"
    end

    lines << ""
    lines << "## How to refresh"
    lines << ""
    lines << "1. Download a fresh `license-inventory.json` from the latest Security Scanning CI run:"
    lines << "   `gh run download <run-id> --name license-inventory`"
    lines << "2. `bin/rails 'licenses:fetch[license-inventory.json]'`"
    lines << "3. Commit any new `LICENSES/*.txt` files and the updated `README.md`."
    lines << ""
    lines << "Non-SPDX entries (Brakeman Public Use License, etc.) require manual"
    lines << "curation -- copy the upstream text into the file path listed above."

    File.write(LICENSES_DIR.join("README.md"), lines.join("\n") + "\n")
  end
end
