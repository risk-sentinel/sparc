# frozen_string_literal: true

# Shared concern for resolving STIG SV/V identifiers to NIST SP 800-53 control IDs.
#
# Two-tier resolution:
#   1. Converter lookup — checks the existing stig_to_nist Converter for a cached mapping
#   2. CCI fallback    — resolves CCI references via cci_to_nist.json (prefers rev5 over rev4)
#
# Also provides InSpec NIST tag normalization:
#   "CM-6 b"   → "cm-6.b"
#   "AC-2 (1)" → "ac-2.1"
#   "SI-2"     → "si-2"
#
module CciNistResolvable
  extend ActiveSupport::Concern

  private

  # Master method: resolve a STIG SV/V-ID to a NIST control ID.
  #
  # @param sv_id [String] the SV or V identifier (e.g., "SV-257777")
  # @param ccis  [Array<String>] CCI references (e.g., ["CCI-000366"])
  # @return [String, nil] NIST control ID (e.g., "cm-6") or nil
  def resolve_nist_for_stig(sv_id, ccis = [])
    # Tier 1: Converter lookup
    nist = stig_converter_lookup[sv_id.to_s]
    return nist if nist.present? && nist != "unmapped"

    # Tier 2: CCI → NIST fallback
    resolve_nist_from_ccis(ccis)
  end

  # Normalize an InSpec NIST tag to OSCAL-compatible format.
  #
  # @param tag [String] raw InSpec tag (e.g., "CM-6 b", "AC-2 (1)", "SI-2")
  # @return [String] normalized ID (e.g., "cm-6.b", "ac-2.1", "si-2")
  def normalize_nist_tag(tag)
    return nil if tag.blank?

    normalized = tag.to_s.strip

    # "AC-2 (1)" → "ac-2.1"  (parenthesised enhancement)
    normalized = normalized.gsub(/\s*\((\d+)\)/, '.\\1')

    # "CM-6 b" → "cm-6.b", "AC-8 c 1" → "ac-8.c.1"  (space-separated sub-parts)
    normalized = normalized.gsub(/\s+([a-zA-Z0-9])(?=\s|$)/, '.\\1')

    normalized.downcase
  end

  # Extract the NIST family prefix from a resolved control ID.
  #
  # @param nist_id [String] e.g., "cm-6.b", "ac-2.1", "si-2"
  # @return [String, nil] e.g., "CM", "AC", "SI"
  def nist_family_from_id(nist_id)
    return nil if nist_id.blank?
    nist_id.to_s.split("-").first.upcase.presence
  end

  # Strip revision suffix from XCCDF rule_id: "SV-257777r925318_rule" → "SV-257777"
  def extract_sv_id(rule_id)
    match = rule_id.to_s.match(/(SV-\d+)/i)
    match ? match[1] : nil
  end

  # ── Converter cache ──────────────────────────────────────────────

  def stig_converter_lookup
    @stig_converter_lookup ||= load_stig_converter_lookup
  end

  def load_stig_converter_lookup
    converter = Converter.find_by(converter_type: "stig_to_nist")
    return {} unless converter

    converter.converter_entries
             .where.not(target_id: "unmapped")
             .pluck(:source_id, :target_id)
             .to_h
  end

  # ── CCI → NIST fallback ─────────────────────────────────────────

  def resolve_nist_from_ccis(ccis)
    return nil if ccis.blank?

    ccis.each do |cci|
      nist = cci_to_nist_lookup[cci.to_s.upcase]
      return nist if nist.present?
    end

    nil
  end

  def cci_to_nist_lookup
    @cci_to_nist_lookup ||= load_cci_to_nist_lookup
  end

  def load_cci_to_nist_lookup
    path = Rails.root.join("lib", "data_mappings", "cci_to_nist.json")
    return {} unless File.exist?(path)

    data = JSON.parse(File.read(path))
    lookup = {}

    Array(data["mappings"]).each do |entry|
      cci = entry["cci"].to_s.upcase
      nist = entry["nist_rev5"].presence || entry["nist_rev4"].presence
      lookup[cci] = nist if nist.present?
    end

    lookup
  end
end
