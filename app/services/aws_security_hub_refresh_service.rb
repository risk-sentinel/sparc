# frozen_string_literal: true

require "net/http"
require "uri"
require "json"

# Issue #494 -- Re-scrapes the AWS Security Hub user guide and reloads
# the aws_security_hub_to_nist Converter. Same shape as
# AwsConfigRefreshService -- stage stamps, transactional reload,
# preservation of operator-edited rows via the unique-pair index.
#
# This service ALSO rewrites lib/data_mappings/aws_security_hub_to_nist.json
# because that file is the runtime source of truth for the SecHub ->
# AWS Config Rule bridge consumed by AwsLabsCdefImportService. The
# converter and the bridge stay coherent through a single refresh.
class AwsSecurityHubRefreshService
  class Error < StandardError; end

  STAGES = {
    fetching_index:    "Fetching AWS Security Hub controls reference page...",
    fetching_services: "Fetching per-service pages...",
    parsing:           "Parsing scraped pages...",
    loading:           "Reloading converter entries...",
    complete:          "Successfully refreshed AWS Security Hub mappings",
    failed:            "Refresh failed"
  }.freeze

  def self.call(converter)
    new(converter).call
  end

  def initialize(converter)
    @converter = converter
    @user_agent = "SPARC-Compliance-Tooling/#{SparcConfig::VERSION} " \
                  "(+https://github.com/risk-sentinel/sparc; issue #494)"
    @throttle = (ENV["SCRAPE_THROTTLE_SECONDS"] || "0.25").to_f
  end

  def call
    validate_converter!

    update_stage!(:fetching_index)
    require Rails.root.join("lib/aws_security_hub/control_scraper")
    index_html = fetch(AwsSecurityHub::ControlScraper::REFERENCE_PAGE)
    slugs = AwsSecurityHub::ControlScraper.discover_service_pages(index_html)

    update_stage!(:fetching_services, "Discovered #{slugs.length} service pages")
    all_entries = []
    slugs.each_with_index do |slug, idx|
      url = AwsSecurityHub::ControlScraper::SERVICE_PAGE_TEMPLATE % slug
      html = fetch(url)
      next if html.nil?
      entries = AwsSecurityHub::ControlScraper.parse_service_page(html, service_slug: slug)
      all_entries.concat(entries)
      sleep @throttle
      update_stage!(:fetching_services, "[#{idx + 1}/#{slugs.length}] #{slug} (#{entries.length} controls)") if (idx % 10).zero?
    end

    update_stage!(:parsing)
    doc = AwsSecurityHub::ControlScraper.build_document(all_entries)
    File.write(vendored_path, JSON.pretty_generate(doc) + "\n")

    update_stage!(:loading, "Loading entries into database...")
    rows = AwsSecurityHub::AwsSecurityHubMappingLoader.build(doc)
    stats = reload_converter!(rows, total_sec_hub_controls: doc["total_entries"])

    update_stage!(:complete)
    @converter.update!(status: "complete", error_message: nil)
    stats
  rescue => e
    @converter.update!(
      status: "failed",
      error_message: e.message,
      metadata_extra: (@converter.metadata_extra || {}).merge(
        "refresh_stage" => "failed",
        "refresh_message" => e.message,
        "refresh_failed_at" => Time.current.iso8601
      )
    )
    raise
  end

  private

  def validate_converter!
    return if @converter.converter_type == "aws_security_hub_to_nist"
    raise Error, "Converter must be of type aws_security_hub_to_nist"
  end

  def update_stage!(stage, custom_message = nil)
    message = custom_message || STAGES[stage]
    meta = (@converter.metadata_extra || {}).merge(
      "refresh_stage"      => stage.to_s,
      "refresh_message"    => message,
      "refresh_updated_at" => Time.current.iso8601
    )
    @converter.update_columns(metadata_extra: meta)
    Rails.logger.info("[AwsSecurityHubRefreshService] #{stage}: #{message}")
  end

  def fetch(url)
    uri = URI(url)
    req = Net::HTTP::Get.new(uri)
    req["User-Agent"] = @user_agent
    res = SparcHttp.start(uri) do |http|  # proxy-aware (#775)
      http.read_timeout = 30
      http.request(req)
    end
    return nil unless res.code.to_i == 200
    res.body
  rescue SocketError, Timeout::Error => e
    Rails.logger.warn("[AwsSecurityHubRefreshService] Fetch failed for #{url}: #{e.message}")
    nil
  end

  def vendored_path
    Rails.root.join("lib/data_mappings/aws_security_hub_to_nist.json")
  end

  def reload_converter!(rows, total_sec_hub_controls:)
    Converter.transaction do
      @converter.converter_entries.where(category: "aws_direct").delete_all

      row_order_start = (@converter.converter_entries.maximum(:row_order) || 0)
      entries = rows.map.with_index do |r, i|
        {
          converter_id: @converter.id,
          source_id:    r["source_id"],
          target_id:    r["target_id"],
          relationship: r["relationship"],
          category:     r["category"],
          remarks:      r["remarks"],
          row_order:    row_order_start + i + 1,
          uuid:         SecureRandom.uuid,
          created_at:   Time.current,
          updated_at:   Time.current
        }
      end

      ConverterEntry.insert_all(
        entries,
        unique_by: :idx_converter_entries_unique_pair
      ) if entries.any?

      {
        total_sec_hub_controls: total_sec_hub_controls,
        entries: entries.length,
        direct_mapped: rows.map { |r| r["source_id"] }.uniq.length
      }
    end
  end
end
