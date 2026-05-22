# frozen_string_literal: true

require "open-uri"
require "zip"
require "nokogiri"

# Downloads the official DISA CCI XML from a configurable URL,
# validates the ZIP/XML structure, applies revision and status
# filtering, then reloads a cci_to_nist Converter's entries
# inside a single transaction.
#
# Progress stages are written to converter.metadata_extra["refresh_stage"]
# so the UI can show live status updates via auto-refresh.
#
# Filtering rules:
#   - Only revisions listed in SPARC_CCI_REVS (default "4,5")
#   - Skip deprecated CCIs entirely
#   - Prefer published over draft (if both exist for same CCI ID)
#
# Usage:
#   stats = CciRefreshService.call(converter)
#   # => { total: 4200, entries: 6800, by_revision: { "4" => 3000, "5" => 3800 },
#   #      skipped_deprecated: 65, skipped_draft: 12 }
#
class CciRefreshService
  class Error < StandardError; end

  STAGES = {
    downloading: "Downloading CCI ZIP from DISA...",
    extracting:  "Unpacking and validating schema...",
    parsing:     "Parsing CCI items...",
    loading:     "Loading data into database...",
    complete:    "Successfully refreshed database",
    failed:      "Refresh failed"
  }.freeze

  def self.call(converter)
    new(converter).call
  end

  def initialize(converter)
    @converter = converter
    @revisions = SparcConfig.cci_revisions
    @tmp_dir = nil
  end

  def call
    validate_converter!

    update_stage!(:downloading)
    zip_path = download_zip

    update_stage!(:extracting)
    xml_path = extract_xml(zip_path)
    doc = parse_and_validate_xml(xml_path)

    update_stage!(:parsing)
    entries = build_entries(doc)

    update_stage!(:loading, "Loading #{entries.size} entries into database...")
    reload_converter!(entries)
  ensure
    FileUtils.rm_rf(@tmp_dir) if @tmp_dir
  end

  private

  # ── Progress Tracking ──────────────────────────────────────────────

  def update_stage!(stage, custom_message = nil)
    message = custom_message || STAGES[stage]
    meta = (@converter.metadata_extra || {}).merge(
      "refresh_stage" => stage.to_s,
      "refresh_message" => message,
      "refresh_updated_at" => Time.current.iso8601
    )
    @converter.update_columns(metadata_extra: meta)
    Rails.logger.info("[CciRefreshService] Stage: #{stage} — #{message}")
  end

  # ── Guards ────────────────────────────────────────────────────────────

  def validate_converter!
    raise Error, "Converter must be of type cci_to_nist" unless @converter.converter_type == "cci_to_nist"
  end

  # ── Download ──────────────────────────────────────────────────────────

  def download_zip
    url = SparcConfig.disa_cci_url
    @tmp_dir = Dir.mktmpdir("cci_refresh")
    zip_path = File.join(@tmp_dir, "cci_list.zip")

    URI.parse(url).open(
      "User-Agent" => "SPARC/#{SparcConfig.version}",
      read_timeout: 120,
      open_timeout: 30
    ) do |remote|
      File.open(zip_path, "wb") { |f| IO.copy_stream(remote, f) }
    end

    zip_path
  rescue OpenURI::HTTPError, SocketError, Errno::ECONNREFUSED, Timeout::Error => e
    raise Error, "Failed to download CCI ZIP: #{e.message}"
  end

  # ── Extract ───────────────────────────────────────────────────────────

  def extract_xml(zip_path)
    xml_path = File.join(@tmp_dir, "U_CCI_List.xml")

    Zip::File.open(zip_path) do |zip|
      entry = zip.glob("**/U_CCI_List.xml").first
      raise Error, "ZIP does not contain U_CCI_List.xml" unless entry

      # Read content from ZIP entry and write manually (rubyzip 3.x compatible)
      File.binwrite(xml_path, entry.get_input_stream.read)
    end

    raise Error, "Failed to extract U_CCI_List.xml" unless File.exist?(xml_path)
    xml_path
  rescue Zip::Error => e
    raise Error, "Invalid ZIP archive: #{e.message}"
  end

  # ── Parse & Validate ──────────────────────────────────────────────────

  def parse_and_validate_xml(xml_path)
    doc = XmlSecurity.parse(File.read(xml_path))
    doc.remove_namespaces!

    root = doc.at_xpath("//cci_list")
    raise Error, "XML missing <cci_list> root element" unless root

    items = doc.xpath("//cci_item")
    raise Error, "XML contains no <cci_item> elements" if items.empty?

    sample = items.first
    raise Error, "CCI items missing <references> children" unless sample.at_xpath("references")

    update_stage!(:extracting, "Validated schema — #{items.size} CCI items found")
    doc
  end

  # ── Build Entries ─────────────────────────────────────────────────────

  def build_entries(doc)
    items = doc.xpath("//cci_item")

    # First pass: collect all items grouped by CCI ID to handle published/draft preference
    cci_groups = items.group_by { |item| item["id"] }

    stats = { total: 0, by_revision: Hash.new(0), skipped_deprecated: 0, skipped_draft: 0 }
    entries = []

    cci_groups.each do |cci_id, group_items|
      # Pick the best item: prefer published over draft, skip deprecated
      selected = select_best_item(group_items, stats)
      next unless selected

      refs = selected.xpath("references/reference")
      added_any = false

      # Collect unique (source_id, target_id) pairs — when multiple revisions
      # map to the same NIST control, merge into a single entry with combined remarks.
      target_revs = {}
      @revisions.each do |rev|
        ref = refs.find { |r| r["version"].to_s.include?(rev) }
        next unless ref

        nist_id = normalize_nist_id(ref["index"])
        next if nist_id.blank?

        target_revs[nist_id] ||= []
        target_revs[nist_id] << rev
        stats[:by_revision][rev] += 1
        added_any = true
      end

      target_revs.each do |nist_id, revs|
        entries << {
          source_id: cci_id,
          target_id: nist_id,
          relationship: "equal",
          category: "cci",
          remarks: revs.map { |r| "Rev #{r}" }.join(", ")
        }
      end

      stats[:total] += 1 if added_any
    end

    @stats = stats
    entries
  end

  # Select the best CCI item from a group:
  #   - Skip all deprecated items
  #   - Prefer published over draft
  #   - Returns nil if all items are deprecated
  def select_best_item(items, stats)
    non_deprecated = items.reject do |item|
      status = item.at_xpath("status")&.text.to_s.strip.downcase
      if status == "deprecated"
        stats[:skipped_deprecated] += 1
        true
      else
        false
      end
    end

    return nil if non_deprecated.empty?

    published = non_deprecated.find { |item| item.at_xpath("status")&.text.to_s.strip.downcase == "published" }
    if published
      draft_count = non_deprecated.size - 1
      stats[:skipped_draft] += draft_count if draft_count > 0
      published
    else
      # All are draft — use the first one
      non_deprecated.first
    end
  end

  # ── Reload ────────────────────────────────────────────────────────────

  def reload_converter!(entries)
    now = Time.current

    # Build bulk-insert rows (bypasses per-row validations for speed;
    # data is already validated/deduplicated by build_entries)
    rows = entries.each_with_index.map do |attrs, idx|
      {
        uuid: SecureRandom.uuid,
        converter_id: @converter.id,
        source_id: attrs[:source_id],
        target_id: attrs[:target_id],
        relationship: attrs[:relationship],
        category: attrs[:category],
        remarks: attrs[:remarks],
        row_order: idx,
        created_at: now,
        updated_at: now
      }
    end

    ActiveRecord::Base.transaction do
      @converter.converter_entries.delete_all

      # Bulk insert in batches of 1000 to avoid oversized SQL statements
      rows.each_slice(1000) do |batch|
        ConverterEntry.insert_all!(batch)
      end

      rev_summary = @stats[:by_revision].map { |k, v| "Rev #{k}: #{v}" }.join(", ")
      @converter.update!(
        version: Time.current.strftime("%Y.%m"),
        status: "complete",
        error_message: nil,
        metadata_extra: (@converter.metadata_extra || {}).merge(
          "refresh_stage" => "complete",
          "refresh_message" => "Successfully refreshed — #{entries.size} entries (#{rev_summary})",
          "refresh_completed_at" => Time.current.iso8601,
          "refresh_stats" => {
            "total_ccis" => @stats[:total],
            "total_entries" => entries.size,
            "by_revision" => @stats[:by_revision],
            "skipped_deprecated" => @stats[:skipped_deprecated],
            "skipped_draft" => @stats[:skipped_draft]
          }
        )
      )
    end

    @stats.merge(entries: entries.size)
  end

  # ── Helpers ───────────────────────────────────────────────────────────

  def normalize_nist_id(raw)
    return nil if raw.blank?

    raw.strip.downcase
       .gsub(/\s*\(\s*/, ".")   # "AC-2 (1)" → "ac-2.1"
       .gsub(")", "")
       .gsub(/\s+/, "-")
  end
end
