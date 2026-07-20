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
    ts_text = SparcHttp.get(source_url)  # proxy-aware (#775)
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
      res = SparcHttp.start(uri) do |http|  # proxy-aware (#775)
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
    require "set"

    sec_hub_converter    = Converter.find_by(converter_type: "aws_security_hub_to_nist")
    aws_config_converter = Converter.find_by(converter_type: "aws_config_to_nist")

    unless sec_hub_converter && aws_config_converter
      abort "Required converters not found. Run `bin/rails db:seed` first.\n" \
            "  aws_security_hub_to_nist: #{sec_hub_converter ? 'OK' : 'MISSING'}\n" \
            "  aws_config_to_nist:       #{aws_config_converter ? 'OK' : 'MISSING'}"
    end

    direct_ids = sec_hub_converter.converter_entries.reorder(nil).distinct.pluck(:source_id).to_set
    config_rules_mapped = aws_config_converter.converter_entries.reorder(nil).distinct.pluck(:source_id).to_set

    # Build the SecHub -> Config Rule bridge from the data file so we can
    # determine which unmapped SecHub controls could in theory chain via
    # the AWS Config converter.
    require Rails.root.join("lib/aws_security_hub/aws_security_hub_mapping_loader")
    bridge_path = Rails.root.join("lib/data_mappings/aws_security_hub_to_nist.json")
    bridge = bridge_path.exist? ? AwsSecurityHub::AwsSecurityHubMappingLoader.build_config_rule_bridge(JSON.parse(File.read(bridge_path))) : {}

    aws_docs = CdefDocument.aws_labs_sourced

    if aws_docs.empty?
      puts "Converter inventory (no AWS-Labs-sourced CdefDocuments yet)"
      puts "  aws_security_hub_to_nist: #{sec_hub_converter.converter_entries.count} rows across #{direct_ids.size} SecHub controls"
      puts "  aws_config_to_nist:       #{aws_config_converter.converter_entries.count} rows across #{config_rules_mapped.size} Config Rules"
      next
    end

    total_controls = 0
    referenced_sec_hub_ids = Set.new
    direct_match_count = 0
    chained_match_count = 0
    unmapped_count = 0
    unmapped_ids = Set.new

    aws_docs.find_each do |doc|
      doc.cdef_controls.find_each do |c|
        total_controls += 1
        next unless c.control_id.to_s.match?(/\A[A-Za-z][A-Za-z0-9]*\.\d+\z/)

        referenced_sec_hub_ids << c.control_id

        if direct_ids.include?(c.control_id)
          direct_match_count += 1
        elsif (rule = bridge[c.control_id]) && config_rules_mapped.include?(rule)
          chained_match_count += 1
        else
          unmapped_count += 1
          unmapped_ids << c.control_id
        end
      end
    end

    puts "AWS Security Hub -> NIST 800-53 mapping coverage"
    puts "================================================="
    puts "AWS Labs CDEFs imported:               #{aws_docs.count}"
    puts "Total CdefControl rows:                #{total_controls}"
    puts "Unique SecHub-shaped control_ids:      #{referenced_sec_hub_ids.size}"
    puts ""
    puts "Resolution path"
    puts "  direct (aws_security_hub_to_nist):   #{direct_match_count}"
    puts "  chained (via aws_config_to_nist):    #{chained_match_count}"
    puts "  unmapped:                            #{unmapped_count}"
    puts ""
    puts "Converter inventory"
    puts "  aws_security_hub_to_nist: #{sec_hub_converter.converter_entries.count} rows / #{direct_ids.size} SecHub controls"
    puts "  aws_config_to_nist:       #{aws_config_converter.converter_entries.count} rows / #{config_rules_mapped.size} Config Rules"

    if unmapped_ids.any?
      puts ""
      puts "Unmapped SecHub controls (sample of up to 30):"
      unmapped_ids.to_a.sort.first(30).each { |id| puts "  - #{id}" }
      puts "  ... and #{unmapped_ids.size - 30} more" if unmapped_ids.size > 30
      puts ""
      puts "To resolve gaps:"
      puts "  1. Re-scrape AWS docs (case: AWS may have added the mapping)"
      puts "     /converters/<aws_security_hub_to_nist> -> 'Refresh from AWS docs'"
      puts "     OR rake mappings:scrape_aws_security_hub"
      puts "  2. Re-vendor MITRE data (case: MITRE may have added the Config Rule)"
      puts "     /converters/<aws_config_to_nist> -> 'Refresh from MITRE'"
      puts "     OR rake mappings:vendor_mitre_aws_config"
      puts "  3. For controls AWS + MITRE both omit, hand-curate via the converter UI"
      puts "     (Edit on /converters/<id>, requires converters.write)"
    end
  end
end
