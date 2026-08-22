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

  # #1030 — the catalog-addressable control a reference belongs to.
  #
  # NIST catalogs hold controls (`ac-2`) and enhancements (`ac-2.1`). They do
  # NOT hold statement parts (`cm-6-b`, `ac-2.a`, `pm-14-a-1`), which are parts
  # OF a control rather than controls. A statement reference is a real reference
  # to a real thing — it is just not a thing `CatalogControl` holds, so storing
  # one in a column used to join against the catalog matches nothing.
  #
  # Measured on `lib/data_mappings/cci_to_nist.json`: only 42.9% of CCI→NIST
  # mappings named an id present in the catalog; 95.2% do once reduced this way.
  #
  # The rule is that a dot followed by DIGITS is an enhancement and is kept,
  # while anything else — a hyphen-letter, a dot-letter, and whatever follows —
  # is statement detail and is dropped:
  #
  #   ac-2        -> ac-2        (control, unchanged)
  #   ac-2.1      -> ac-2.1      (enhancement, unchanged)
  #   cm-6-b      -> cm-6
  #   ac-2.a      -> ac-2
  #   pm-14-a-1   -> pm-14
  #   ia-5.1.a    -> ia-5.1      (enhancement kept, statement dropped)
  #   ac-1-a-1.a  -> ac-1
  #
  # A hyphen followed by DIGITS never appears in the mapping data (measured:
  # zero occurrences of `xx-N-N`), so a hyphen suffix is always a statement
  # letter and never an enhancement written the other way. If that ever changes,
  # `ac-2-1` would silently reduce to `ac-2` and lose the enhancement — which is
  # what the spec asserting the measurement is there to catch.
  #
  # This does NOT touch `canonical`. That form is schema-validated in every
  # OSCAL document SPARC exports, and changing it would invalidate all of them.
  # `control_key` is a separate reduction for a separate purpose: joining.
  def control_key(raw)
    id = canonical(raw)
    match = id.match(/\A(\p{L}{1,3}-\d+(?:\.\d+)?)/)
    match ? match[1] : id
  end

  # SPARC's display/sort form: family uppercase, base number zero-padded to two
  # digits, enhancement padded likewise. `AC-2` -> `AC-02`, `ac-2.1` -> `AC-02.01`.
  def padded(raw)
    canonical(raw).upcase.gsub(/(?<=\A|[-.])(\d+)/) { ::Regexp.last_match(1).rjust(2, "0") }
  end

  # The NIST *tag* form: `AC-2(1)`, `CA-7`. Same as `human` but without the
  # space before an enhancement (#911).
  #
  # This is what tag-keyed consumers expect — the CMS / SAF CLI attestation
  # export is read by Heimdall, which matches on the NIST tag. `human` renders
  # the publication spacing (`AC-2 (1)`), which is right for prose and wrong
  # for a tag match, so the two are separate rather than one guessing.
  def nist_tag(raw)
    base, *enhancements = strip_padding(canonical(raw)).split(".")
    return base.to_s.upcase if enhancements.empty?

    "#{base.upcase}#{enhancements.map { |e| "(#{e})" }.join}"
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

  # Every legitimate spelling of one identifier, for matching a column whose
  # stored values may be in any of them (#911).
  #
  # Canonicalisation happens on write, so a row adopts the canonical form only
  # when it is next saved. Until then a table holds a mix — `SarControl` is
  # entirely padded today, evidence links likewise — and a query that
  # canonicalises only its INPUT still matches nothing. That is the same silent
  # failure canonicalisation exists to end, so comparisons match the set.
  #
  #   ControlId.forms("AC-2")   # => ["ac-2", "AC-02", "AC-2"]
  #
  # Prefer this over a bare `where(control_id: input)` anywhere the column is
  # not yet guaranteed canonical. Once a table is fully canonical the extra
  # values are simply redundant, so it stays correct rather than needing unwind.
  # Lowercase variants are included because catalogs do not agree on case for
  # the padded form. The FedRAMP KSI catalog stores `ksi-auth-01` — padded AND
  # lowercase — while SPARC's display convention uppercases it. Emitting only
  # `KSI-AUTH-01` would miss every KSI row, which is the same silent-mismatch
  # failure in a different vocabulary.
  def forms(raw)
    return [] if raw.blank?

    base = [ canonical(raw), padded(raw), human(raw), raw.to_s.strip ]
    (base + base.map(&:downcase)).reject(&:blank?).uniq
  end

  def token?(value) = value.to_s.match?(TOKEN)

  private

  # NIST control numbering is one or two digits per segment (AC-1 … AC-25), so
  # padding beyond that is not padding at all — it is a fixed-width identifier
  # from a DIFFERENT vocabulary.
  #
  # `CCI-000213` is the case that matters: those are six-digit fixed-width by
  # definition, and stripping the zeros produced `cci-213`, silently corrupting
  # an identifier from external tooling into one that matches nothing. Bounding
  # the rule keeps zero-stripping to the NIST shape it was written for.
  MAX_PADDED_DIGITS = 3

  # Remove zero padding from short numeric segments: `ac-02.01` -> `ac-2.1`.
  # Guarded so a segment of only zeros keeps one digit rather than vanishing,
  # and so a long fixed-width run is left exactly as it arrived.
  def strip_padding(value)
    value.gsub(/(?<=\A|[-.])(0+)(\d+)/) do
      zeros = ::Regexp.last_match(1)
      digits = ::Regexp.last_match(2)

      (zeros.length + digits.length) <= MAX_PADDED_DIGITS ? digits : "#{zeros}#{digits}"
    end
  end
end
