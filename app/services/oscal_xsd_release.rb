# frozen_string_literal: true

# Which carried OSCAL XSD set validates (and orders) a document that declares
# `declared` (owner, 2026-09-29: carry 1.1.2, 1.1.3, 1.2.2, 1.2.3 —
# `OscalSchema::XSD_VERSIONS`).
#
#   * nothing declared          -> DEFAULT_VERSION
#   * a carried version         -> that version
#   * uncarried, same line held -> the nearest carried release in that
#     major.minor line (the lowest one at or above it, else the highest
#     below): 1.1.1 -> 1.1.2, 1.2.0 / 1.2.1 -> 1.2.2
#   * no release of that line   -> DEFAULT_VERSION
#
# The answer is always one of the carried release strings (a constant), never
# the declared text itself, so it is safe to build a schema path from.
# Callers report `declared` alongside the result, so a substitution is always
# visible ("nearest carried, flagged"), never silent.
#
# A plain module rather than a method on OscalSchema: the resolution is pure
# logic over constants, and on an ActiveRecord model its result reads as a
# model attribute to static analysis.
module OscalXsdRelease
  extend self

  def for(declared)
    carried = OscalSchema::XSD_VERSIONS
    declared = declared.to_s.strip
    return OscalSchema::DEFAULT_VERSION if declared.empty?

    exact = carried.find { |v| v == declared }
    return exact if exact

    line = declared.split(".").first(2)
    same_line = carried.select { |v| v.split(".").first(2) == line }
    return OscalSchema::DEFAULT_VERSION if same_line.empty?

    target = Gem::Version.new(declared) rescue nil
    return same_line.last unless target

    same_line.find { |v| Gem::Version.new(v) >= target } || same_line.last
  end

  # The carried set's directory name for `version`, or nil if not carried.
  def dir_for(version) = OscalSchema::XSD_VERSIONS.include?(version) ? "v#{version}" : nil
end
