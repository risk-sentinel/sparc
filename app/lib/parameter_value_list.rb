# frozen_string_literal: true

# Encoding for a parameter field that holds MORE THAN ONE value (#942).
#
# `profile_control_fields` stores a parameter's value as a single string, and a
# multi-valued parameter joined its values with ", ". That silently corrupted
# the data it most needed to carry: OSCAL insert markup always contains a comma,
# so choosing AC-20's branch
#
#   "establish {{ insert: param, ac-20_odp.02 }}"
#
# split back into TWO values — "establish {{ insert: param" and
# "ac-20_odp.02 }}" — and both travelled into exported OSCAL as `set-parameters`
# values nobody chose.
#
# Measured against the Rev 5 catalog: of 355 selection choices, 74 contain a
# comma and NONE contains a pipe. So " | " separates safely and, unlike a
# control character, stays readable in the text input the operator edits.
#
# ── Reading legacy values ──────────────────────────────────────────────────
#
# Rows written before this change are still comma-joined, so `split` accepts
# both forms and no data migration is required. Where a legacy value carries
# insert markup it is treated as ONE value rather than split: splitting is
# precisely what corrupts it, and a value that references a parameter is never
# a comma-separated list.
module ParameterValueList
  SEPARATOR = " | "
  LEGACY_SEPARATOR = ", "

  def self.split(value)
    text = value.to_s.strip
    return [] if text.blank?

    return clean(text.split(SEPARATOR)) if text.include?(SEPARATOR)
    # Never split a value that references a parameter -- see the note above.
    return [ text ] if OscalParamReference.references?(text)

    clean(text.split(LEGACY_SEPARATOR))
  end

  def self.join(values)
    Array(values).map { |v| v.to_s.strip }.reject(&:blank?).join(SEPARATOR)
  end

  def self.clean(parts)
    parts.map(&:strip).reject(&:blank?)
  end
  private_class_method :clean
end
