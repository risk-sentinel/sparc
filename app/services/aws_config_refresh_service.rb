# frozen_string_literal: true

require "net/http"
require "uri"

# Issue #494 -- Re-vendors MITRE's AwsConfigMappingData and reloads the
# aws_config_to_nist Converter. Modeled after CciRefreshService:
#
#   - Stages are stamped to converter.metadata_extra["refresh_stage"]
#     so the existing /converters/:id status banner can render
#     progress without any UI changes.
#   - The reload happens in a single transaction so a failure during
#     load leaves the converter's old rows intact.
#   - Hand-edited rows are preserved by the unique-pair index plus an
#     insert_all on conflict do nothing semantics -- we delete only
#     the MITRE-vendored rows (category="mitre_vendored") and re-add
#     them. Rows with other categories (operator-added) survive.
class AwsConfigRefreshService
  class Error < StandardError; end

  STAGES = {
    fetching:  "Fetching MITRE heimdall2 source...",
    parsing:   "Parsing TypeScript array literal...",
    loading:   "Reloading converter entries...",
    complete:  "Successfully refreshed AWS Config Rule mappings",
    failed:    "Refresh failed"
  }.freeze

  def self.call(converter)
    new(converter).call
  end

  def initialize(converter)
    @converter = converter
  end

  def call
    validate_converter!

    update_stage!(:fetching)
    ts_text = fetch_mitre_source
    rebuild_vendored_data_file(ts_text)

    update_stage!(:parsing)
    rows = AwsSecurityHub::AwsConfigMappingLoader.from_path(vendored_path)

    update_stage!(:loading, "Loading #{rows.size} entries into database...")
    stats = reload_converter!(rows)

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
    return if @converter.converter_type == "aws_config_to_nist"
    raise Error, "Converter must be of type aws_config_to_nist"
  end

  def update_stage!(stage, custom_message = nil)
    message = custom_message || STAGES[stage]
    meta = (@converter.metadata_extra || {}).merge(
      "refresh_stage"      => stage.to_s,
      "refresh_message"    => message,
      "refresh_updated_at" => Time.current.iso8601
    )
    @converter.update_columns(metadata_extra: meta)
    Rails.logger.info("[AwsConfigRefreshService] #{stage}: #{message}")
  end

  def fetch_mitre_source
    require Rails.root.join("lib/aws_security_hub/mitre_mapping_porter")
    url = ENV["MITRE_TS_URL"] || AwsSecurityHub::MitreMappingPorter::UPSTREAM_TS_URL
    body = Net::HTTP.get(URI(url))
    raise Error, "Empty response from #{url}" if body.nil? || body.empty?
    body
  rescue SocketError, Timeout::Error => e
    raise Error, "Failed to fetch MITRE source: #{e.message}"
  end

  def rebuild_vendored_data_file(ts_text)
    require Rails.root.join("lib/aws_security_hub/mitre_mapping_porter")
    rows = AwsSecurityHub::MitreMappingPorter.parse_ts_source(ts_text)
    AwsSecurityHub::MitreMappingPorter.write!(rows, path: vendored_path)
  end

  def vendored_path
    Rails.root.join("lib/data_mappings/mitre_aws_config_to_nist.json")
  end

  # Replace only rows whose category indicates this service authored
  # them. Operator-added rows (category=nil, category="custom", or any
  # other non-mitre_vendored value) are left alone.
  def reload_converter!(rows)
    Converter.transaction do
      @converter.converter_entries.where(category: "mitre_vendored").delete_all

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

      # on_conflict do nothing: skip any pair that collides with an
      # operator-added row using the same (source_id, target_id).
      ConverterEntry.insert_all(
        entries,
        unique_by: :idx_converter_entries_unique_pair
      ) if entries.any?

      { entries: entries.length, source_rules: rows.map { |r| r["source_id"] }.uniq.length }
    end
  end
end
