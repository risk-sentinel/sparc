# frozen_string_literal: true

# Translates NIST SP 800-53 control IDs between revisions (Rev 4 ↔ Rev 5)
# by consulting the seeded ControlMapping records (#499 slice 1).
#
# Bulk-apply uses this when a converter's natively-emitted rev differs
# from the rev the caller (typically the CDEF baseline) expects.
#
# Usage:
#
#   ControlIdNormalizer.translate(["ac-2", "ac-2.1"], from_rev: 4, to_rev: 5)
#   # => [
#   #   <Translation source_id: "ac-2",   target_id: "ac-2",   relationship: "equal",  mapping_id: 42>,
#   #   <Translation source_id: "ac-2.1", target_id: "ac-2.1", relationship: "equal",  mapping_id: 42>
#   # ]
#
# 1→N preserved: when a source id has multiple ControlMappingEntry rows
# (e.g. a Rev 4 control that the Rev 5 catalog split into several), the
# caller gets one Translation per target so disambiguation can be
# surfaced (e.g. preview UI lets the operator pick).
#
# Graceful degradation:
#   - from_rev == to_rev → identity translation (no DB query)
#   - mapping not seeded → identity translation, mapping_id: nil
#   - source id not in mapping → identity passthrough, relationship: nil
class ControlIdNormalizer
  Translation = Struct.new(:source_id, :target_id, :relationship, :mapping_id, keyword_init: true)

  def self.translate(ids, from_rev:, to_rev:)
    new(from_rev: from_rev, to_rev: to_rev).translate(ids)
  end

  def initialize(from_rev:, to_rev:)
    @from_rev = from_rev.to_s
    @to_rev   = to_rev.to_s
  end

  def translate(ids)
    ids_array = Array(ids).map { |i| i.to_s.downcase }.reject(&:empty?)
    return [] if ids_array.empty?
    return identity_translations(ids_array) if @from_rev == @to_rev

    mapping = lookup_mapping
    return identity_translations(ids_array) unless mapping

    # Single batched query for all requested source ids.
    entries_by_source = mapping.control_mapping_entries
                               .where(source_control_id: ids_array)
                               .group_by(&:source_control_id)

    ids_array.flat_map do |id|
      matches = entries_by_source[id] || []
      if matches.empty?
        # Source id not in the mapping table — pass through unchanged
        # with nil relationship so the caller can distinguish a real
        # mapping hit (relationship populated) from a passthrough.
        [ Translation.new(source_id: id, target_id: id, relationship: nil, mapping_id: mapping.id) ]
      else
        matches.map do |entry|
          Translation.new(
            source_id:    id,
            target_id:    entry.target_control_id,
            relationship: entry.relationship,
            mapping_id:   mapping.id
          )
        end
      end
    end
  end

  private

  def identity_translations(ids)
    ids.map { |id| Translation.new(source_id: id, target_id: id, relationship: "equal", mapping_id: nil) }
  end

  def lookup_mapping
    @lookup_mapping ||= ControlMapping.find_by(name: "NIST SP 800-53 Rev #{@from_rev} → Rev #{@to_rev}")
  end
end
