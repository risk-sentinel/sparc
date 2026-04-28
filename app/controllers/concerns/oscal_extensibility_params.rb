# Shared param normalization for OSCAL extensibility arrays — props,
# links, and origins — across every POAM-related controller (#389/#416/#423).
#
# All three are stored as JSONB arrays on the underlying model, with the
# shape matching the OSCAL JSON spec (hyphenated keys: `media-type`,
# `actor-uuid`, etc.). Forms use Rails-friendly underscore keys
# (`media_type`, `actor_uuid`); these helpers convert and drop empty rows.
#
# Origins are wrapped as `{ "actors": [{ "type", "actor-uuid", "role-id" }] }`
# per OSCAL spec — the form sends one row per actor, the helper builds the
# wrapper.
#
# NIST SI-10: Information Input Validation (filter empty rows, normalize keys)
module OscalExtensibilityParams
  extend ActiveSupport::Concern

  private

  def compact_props(rows)
    Array(rows).filter_map do |row|
      h = row_to_hash(row)
      next if h["name"].to_s.empty? || h["value"].to_s.empty?

      h
    end
  end

  def compact_links(rows)
    Array(rows).filter_map do |row|
      h = row_to_hash(row)
      next if h["href"].to_s.empty?

      h["media-type"] = h.delete("media_type") if h.key?("media_type")
      h
    end
  end

  # Origins arrive as a flat list of actor-shaped rows from the form
  # (`{ actor_type, actor_uuid, role_id }`); each row becomes one origin
  # with a single-actor `actors[]` array. Drop rows with no actor_uuid.
  def compact_origins(rows)
    Array(rows).filter_map do |row|
      h = row_to_hash(row)
      next if h["actor_uuid"].to_s.empty?

      actor = { "type" => h["actor_type"].presence || "party",
                "actor-uuid" => h["actor_uuid"] }
      actor["role-id"] = h["role_id"] if h["role_id"].present?
      { "actors" => [ actor ] }
    end
  end

  def row_to_hash(row)
    raw = row.respond_to?(:to_unsafe_h) ? row.to_unsafe_h : row.to_h
    raw.transform_keys(&:to_s).reject { |_, v| v.to_s.strip.empty? }
  end
end
