# frozen_string_literal: true

# Issue #491 — Rake tasks for maintaining the AWS Security Hub → NIST
# 800-53 mapping. The composite mapping is built from three sources:
#
#   1. MITRE's AWS Config Rule → NIST mapping (vendored from heimdall2)
#   2. AWS Security Hub control → AWS Config Rule bridge (scraped from
#      the AWS Security Hub user guide)
#   3. Hand-curated supplements for Sec Hub controls that have no
#      Config Rule, or controls absent from MITRE's data
#
# Slice 1 covers task (1) here. Slices 2-3 add the scraper and the
# composite build.

namespace :mappings do
  desc "Re-vendor MITRE's AwsConfigMappingData.ts as lib/data_mappings/mitre_aws_config_to_nist.json"
  task vendor_mitre_aws_config: :environment do
    require Rails.root.join("lib/aws_security_hub/mitre_mapping_porter")
    require "net/http"
    require "uri"

    out_path = Rails.root.join("lib/data_mappings/mitre_aws_config_to_nist.json")
    source_url = ENV["MITRE_TS_URL"] || AwsSecurityHub::MitreMappingPorter::UPSTREAM_TS_URL

    puts "Fetching: #{source_url}"
    ts_text = Net::HTTP.get(URI(source_url))
    if ts_text.nil? || ts_text.empty?
      abort "Empty response from #{source_url}"
    end

    rows = AwsSecurityHub::MitreMappingPorter.parse_ts_source(ts_text)
    doc  = AwsSecurityHub::MitreMappingPorter.write!(rows, path: out_path)

    puts "Wrote: #{out_path}"
    puts "Entries: #{doc["total_entries"]}"
    puts "Attribution: #{doc["attribution"]}"
    puts
    puts "Review the diff (`git diff lib/data_mappings/mitre_aws_config_to_nist.json`)"
    puts "and commit with a message that references mitre/heimdall2 commit SHA."
  end

  desc "Scrape the AWS Security Hub user guide for SecHub control -> NIST 800-53 rev5 mappings"
  task scrape_aws_security_hub: :environment do
    require Rails.root.join("lib/aws_security_hub/control_scraper")
    require "net/http"
    require "uri"
    require "json"

    out_path = Rails.root.join("lib/data_mappings/aws_security_hub_to_nist.json")
    throttle_seconds = (ENV["SCRAPE_THROTTLE_SECONDS"] || "0.25").to_f
    user_agent = "SPARC-Compliance-Tooling/#{SparcConfig::VERSION} " \
                 "(+https://github.com/risk-sentinel/sparc; issue #491)"

    fetch = lambda do |url|
      uri = URI(url)
      req = Net::HTTP::Get.new(uri)
      req["User-Agent"] = user_agent
      res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https") do |http|
        http.read_timeout = 30
        http.request(req)
      end
      unless res.code.to_i == 200
        warn "  #{url} returned HTTP #{res.code}; skipping"
        return nil
      end
      res.body
    end

    puts "Fetching index: #{AwsSecurityHub::ControlScraper::REFERENCE_PAGE}"
    index_html = fetch.call(AwsSecurityHub::ControlScraper::REFERENCE_PAGE)
    abort "Failed to fetch the controls reference page" if index_html.nil?

    slugs = AwsSecurityHub::ControlScraper.discover_service_pages(index_html)
    puts "Discovered #{slugs.length} per-service pages"

    all_entries = []
    slugs.each_with_index do |slug, idx|
      url = AwsSecurityHub::ControlScraper::SERVICE_PAGE_TEMPLATE % slug
      printf("  [%3d/%3d] %-40s ", idx + 1, slugs.length, slug)
      html = fetch.call(url)
      if html.nil?
        puts "(no HTML)"
        next
      end
      entries = AwsSecurityHub::ControlScraper.parse_service_page(html, service_slug: slug)
      all_entries.concat(entries)
      puts "#{entries.length} controls"
      sleep throttle_seconds
    end

    doc = AwsSecurityHub::ControlScraper.build_document(all_entries)
    File.write(out_path, JSON.pretty_generate(doc) + "\n")

    coverage = {
      total: all_entries.length,
      with_nist_mapping: all_entries.count { |e| e["nist_oscal_ids"].any? },
      with_config_rule:  all_entries.count { |e| e["aws_config_rule"].present? },
      with_neither:      all_entries.count { |e| e["nist_oscal_ids"].empty? && e["aws_config_rule"].nil? }
    }

    puts
    puts "Wrote: #{out_path}"
    puts "Total SecHub controls: #{coverage[:total]}"
    puts "  with NIST mapping:   #{coverage[:with_nist_mapping]}"
    puts "  with Config rule:    #{coverage[:with_config_rule]}"
    puts "  with neither (gap):  #{coverage[:with_neither]}"
  end

  desc "Report AWS Security Hub -> NIST mapping coverage across imported AWS Labs CDEFs"
  task coverage_report: :environment do
    converter = Converter.find_by(converter_type: "aws_security_hub_to_nist")
    unless converter
      abort "aws_security_hub_to_nist Converter not found. Run `bin/rails db:seed` first."
    end

    mapped_sec_hub_ids = converter.converter_entries.reorder(nil).distinct.pluck(:source_id).to_set
    aws_docs           = CdefDocument.aws_labs_sourced

    if aws_docs.empty?
      puts "No AWS-Labs-sourced CdefDocuments yet (SPARC_AWS_LABS_CDEF_ENABLED=true required)."
      puts "Converter has #{converter.converter_entries.count} rows across " \
           "#{mapped_sec_hub_ids.size} mapped SecHub controls."
      next
    end

    total_controls = 0
    referenced_sec_hub_ids = Set.new
    mapped_controls = 0
    unmapped_controls = []

    aws_docs.find_each do |doc|
      doc.cdef_controls.find_each do |c|
        total_controls += 1
        next unless c.control_id.to_s.match?(/\A[A-Za-z][A-Za-z0-9]*\.\d+\z/)

        referenced_sec_hub_ids << c.control_id
        if mapped_sec_hub_ids.include?(c.control_id)
          mapped_controls += 1
        else
          unmapped_controls << { doc: doc.name, sec_hub_id: c.control_id }
        end
      end
    end

    puts "AWS Security Hub -> NIST 800-53 mapping coverage"
    puts "================================================="
    puts "AWS Labs CDEFs imported:           #{aws_docs.count}"
    puts "Total CdefControl rows:            #{total_controls}"
    puts "SecHub-shaped control_ids:         #{referenced_sec_hub_ids.size} unique"
    puts "  with NIST mapping (covered):     #{(referenced_sec_hub_ids & mapped_sec_hub_ids).size}"
    puts "  without mapping (gap):           #{(referenced_sec_hub_ids - mapped_sec_hub_ids).size}"
    puts ""
    puts "Per-control rows (across documents)"
    puts "  mapped:                          #{mapped_controls}"
    puts "  unmapped:                        #{unmapped_controls.length}"

    if (gap_ids = referenced_sec_hub_ids - mapped_sec_hub_ids).any?
      puts ""
      puts "Unmapped SecHub controls (sample of up to 30):"
      gap_ids.to_a.sort.first(30).each { |id| puts "  - #{id}" }
      puts "" if gap_ids.size > 30
      puts "  ... and #{gap_ids.size - 30} more" if gap_ids.size > 30
      puts ""
      puts "To resolve gaps:"
      puts "  1. Re-scrape AWS docs (in case AWS added the mapping):"
      puts "     bundle exec rake mappings:scrape_aws_security_hub"
      puts "  2. Re-vendor MITRE data (in case MITRE updated):"
      puts "     bundle exec rake mappings:vendor_mitre_aws_config"
      puts "  3. Re-seed the converter:"
      puts "     bin/rails db:seed"
      puts "  4. For controls AWS and MITRE both omit, hand-curate via"
      puts "     the converter UI (converters.write permission)."
    end
  end
end
