# frozen_string_literal: true

# #852 — the one canonical representation of a NIST control identifier.
#
# SPARC had at least a dozen ad-hoc transformers converting control IDs between
# formats: four byte-identical private copies of the same normalizer, three
# padding implementations, two de-padding ones, and a weaker variant used by the
# mapping export. They did not agree, and none of them reconciled zero-padding —
# so `AC-02` and `ac-2` were different strings everywhere despite naming the
# same control.
#
# ── Three legitimate forms ────────────────────────────────────────────────
#
#   canonical  ac-2.1      lowercase, unpadded, dot notation. What OSCAL wants.
#   padded     AC-02       SPARC's display and sort convention.
#   human      AC-2 (1)    how the control is written in NIST SP 800-53.
#
# All three are correct in their place. The defect was never that they exist —
# it was that converting between them lived in a dozen private methods.
#
# ── Why canonical must not drift ──────────────────────────────────────────
#
# `control-id` and `target-id` are **TokenDatatype** in the ssp, profile,
# component-definition, assessment-plan, assessment-results and poam schemas:
#
#   ^(\p{L}|_)(\p{L}|\p{N}|[.\-_])*$
#
# Parentheses and spaces are not in that set, which is why the canonical form
# converts `AC-2 (1)` to `ac-2.1` rather than merely lowercasing. The four
# duplicated normalizers already produced exactly this, and their output is
# schema-validated today, so `canonical` is a faithful reproduction of them
# rather than a new convention. Changing it would invalidate every OSCAL
# document SPARC exports.
#
# `id-ref` in the mapping schema is StringDatatype, so it is the one field where
# the looser form was legal. It was still wrong — the same control was
# identified two ways depending on which document you exported, which nothing
# would ever link up and no validator would ever flag.
#
# NIST 800-53: CA-2, CA-5, PM-6 (consistent control identification across the
# assessment and authorization artifacts).
module ControlId
  extend self

  # OSCAL TokenDatatype, for asserting our own output rather than trusting it.
  TOKEN = /\A(\p{L}|_)(\p{L}|\p{N}|[.\-_])*\z/

  # Lowercase, unpadded, dot-notation. The form written into OSCAL.
  #
  # Byte-for-byte the behaviour of the four normalizers this replaces, plus
  # zero-padding removal — which they lacked, and whose absence is why `AC-02`
  # and `ac-2` never matched.
  def canonical(raw)
    return "unknown" if raw.blank?

    strip_padding(
      raw.to_s.strip
         .downcase
         .gsub(/\s+/, "-")     # spaces -> hyphens
         .gsub("(", ".")       # enhancement paren -> dot
         .gsub(")", "")
         .gsub(/\.{2,}/, ".")  # collapse repeated dots
         .gsub(/-\./, ".")     # "ac-2-.1" -> "ac-2.1"
    )
  end

  # SPARC's display/sort form: family uppercase, base number zero-padded to two
  # digits, enhancement padded likewise. `AC-2` -> `AC-02`, `ac-2.1` -> `AC-02.01`.
  def padded(raw)
    canonical(raw).upcase.gsub(/(?<=\A|[-.])(\d+)/) { ::Regexp.last_match(1).rjust(2, "0") }
  end

  # NIST publication form: `AC-2 (1)`.
  def human(raw)
    base, *enhancements = strip_padding(canonical(raw)).split(".")
    return base.upcase if enhancements.empty?

    "#{base.upcase} #{enhancements.map { |e| "(#{e})" }.join(' ')}"
  end

  # Do two identifiers name the same control, regardless of case, padding or
  # notation? This is the comparison that was missing everywhere: matching was
  # case-insensitive but never padding-insensitive, so a selection of "ac-2"
  # silently matched nothing against a stored "AC-02".
  def same?(left, right)
    return false if left.blank? || right.blank?

    canonical(left) == canonical(right)
  end

  # Membership using `same?` semantics, for filtering a list by a selection.
  def include?(collection, candidate)
    Array(collection).any? { |value| same?(value, candidate) }
  end

  # A set-like index for O(1) membership over many comparisons.
  def canonical_set(collection)
    Array(collection).reject(&:blank?).map { |value| canonical(value) }.to_set
  end

  def token?(value) = value.to_s.match?(TOKEN)

  private

  # Remove zero padding from every numeric segment: `ac-02.01` -> `ac-2.1`.
  # Guarded so a segment of only zeros keeps one digit rather than vanishing.
  def strip_padding(value)
    value.gsub(/(?<=\A|[-.])0+(\d)/) { ::Regexp.last_match(1) }
  end
end
