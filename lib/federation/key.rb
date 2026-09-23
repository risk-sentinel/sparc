# frozen_string_literal: true

# Reference implementation of the UUIDv5 object-key grammar (#1161).
#
# The grammar is specified normatively in sparc-horizon `docs/03-data-model.md`,
# section *Deterministic UUIDs*. Identifiers derived under it are exchanged
# between instances, so **a disagreement between two implementations is a silent
# data-integrity fault, not a bug someone notices**: the same logical object
# arrives under a second identity and nothing reconciles it.
#
#   namespace  = 9f434272-f796-589b-b972-954790395630   (registered, #1155)
#   grammar    = "v1"
#   uuid(obj)  = uuidv5(namespace, grammar + "\x1f" + join(fields(obj), "\x1f"))
#
# ── Why this reads a data file instead of declaring the fields here ──────────
#
# The field lists live in `key-grammar.v1.json` and are read at load time, so
# Ruby, Python and Go build keys from ONE declaration rather than three
# transcriptions. Every `canonical-fields` in that file is regenerated from the
# same field lists, so the vectors and the rule they encode cannot drift apart.
#
# ── What this does NOT do (#1161 scope) ─────────────────────────────────────
#
# Nothing in SPARC derives object UUIDs through this yet. It is a reference
# implementation and its vectors; wiring it into attestations, observations and
# findings is separate work with its own migration posture.
#
# NIST SP 800-53 Rev 5: SR-11 (component authenticity — a federated object's
# identity is derived, not asserted), CA-3 (information exchange), SI-10.
module Federation
  class Key
    GRAMMAR_PATH = Rails.root.join("lib/federation/key-grammar.v1.json")

    # Raised rather than escaped. A printable delimiter would make ("a|b","c")
    # and ("a","b|c") hash identically — a collision by accident, which is
    # harder to notice than one by attack. \x1f cannot appear in any defined
    # field, so a field carrying it is a caller error, not something to repair.
    class SeparatorInField < StandardError; end

    # A key missing a field is a DIFFERENT key, not a key with an empty field.
    # Deriving one anyway is exactly the silent divergence this grammar exists
    # to prevent, so an unresolvable field refuses.
    class MissingField < StandardError; end

    class UnknownKind < StandardError; end

    # A field whose VALUE cannot be what it claims to be. Distinct from a
    # missing field, and rejected for the same reason: `2026-1` is not a
    # spelling of `2026-01`, and a component named `web-01` does not federate.
    class InvalidField < StandardError; end

    # Identifier kinds, named once. These are keys into the grammar file and
    # into `vocabulary-normalisers`, so a typo would otherwise be a silently
    # non-matching string rather than a NameError.
    CONTROL_ID        = "control-id"
    FAMILY_ID         = "family-id"

    TYPE_RULES = {
      "uuid"      => ->(v) { v.match?(/\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/) },
      FAMILY_ID   => ->(v) { v.match?(/\A[a-z]{2,3}\z/) },
      # 2026-Q3 or 2026-01. Zero padding is required, and a quarter carries its
      # hyphen — neither is a spelling variant to be repaired.
      "period"    => ->(v) { v.match?(/\A\d{4}-(Q[1-4]|0[1-9]|1[0-2])\z/) },
      "decision-date" => ->(v) { v.match?(/\A\d{4}-\d{2}-\d{2}\z/) },
      "sha256"    => ->(v) { v.match?(/\A\h{64}\z/) },
      "half"      => ->(v) { %w[provider consumer].include?(v) },
      "horizon-bucket" => ->(v) { %w[today +7 +14 +30].include?(v) || v.match?(/\A\d{4}-\d{2}-\d{2}\z/) }
    }.freeze

    # Under NIST the canonicalised value must name a control or an enhancement.
    # This rejects a statement fragment (`ac-2_smt.a`, which names part of a
    # control, so keying on it counts one object twice) and a foreign-vocabulary
    # identifier declared as NIST (`ACM.1` canonicalises to `acm.1`, which
    # validates against nothing). Under an opaque vocabulary any non-empty
    # value is accepted unchanged — its form is that authority's business.
    NIST_CONTROL_FORM = /\A[a-z]{2,3}-\d+(\.\d+)*\z/

    # Key names from the grammar file, named once so a typo is a NameError
    # rather than a silently non-matching string.
    OBJECT_UUID       = "object-uuid"
    ORIGINATING_PARTY = "originating-party"
    ONE_OF            = "one-of"

    class << self
      def spec
        @spec ||= JSON.parse(File.read(GRAMMAR_PATH)).freeze
      end

      def separator  = spec.fetch("separator")
      def grammar    = spec.fetch("grammar")
      def namespace  = spec.dig("namespace", "uuid")
      def kinds      = spec.fetch("field-lists").keys
      def context_args = spec.fetch("context-args")

      # The canonical field list for an object: the grammar version followed by
      # each field, normalised and NFC-folded. Exposed because it is what a
      # disagreement is diagnosed from — comparing two UUIDs tells you only
      # that they differ.
      def canonical_fields(kind, args)
        fields = field_list(kind).map { |field_spec| resolve(kind, field_spec, args) }
        fields.each do |value|
          raise SeparatorInField, "#{kind}: a field contains the grammar separator" if value.include?(separator)
        end
        [ grammar ] + fields
      end

      def derive(kind, args)
        input = canonical_fields(kind, args).join(separator)
        Digest::UUID.uuid_v5(namespace, input)
      end

      # Deduplicate a set of claims (#1159).
      #
      # **An object UUID identifies a thing, not an assertion about a thing.**
      # The asserting party is never folded into the key, which is deliberate —
      # it is what lets two peers recognise the same object without
      # coordinating. The cost is that the grammar is public and the namespace
      # shared, so ANY peer can compute ANY boundary's identifiers. Determinism
      # is being used as an addressing scheme, and addressing needs an owner.
      #
      # So dedup scopes on the PAIR. Keying on the UUID alone would let a
      # hostile peer precompute another boundary's attestation identifier and
      # submit a document claiming it; the receiver would then treat two
      # parties' assertions about different things as one object, and which
      # survives would be a property of ingestion order rather than authority.
      #
      # Two parties on one UUID is a CONFLICT TO SURFACE, never a duplicate to
      # collapse. Both are kept: silently keeping one is the failure mode,
      # whichever one it keeps.
      #
      # Returns [objects, conflicts]. `objects` is one entry per distinct pair;
      # `conflicts` is one entry per CONTESTED UUID, not per excess claim, so
      # the count does not grow with how many peers pile on.
      def dedup(claims)
        scoped = claims.map do |claim|
          uuid  = (claim[:object_uuid] || claim[OBJECT_UUID]).to_s
          party = (claim[:originating_party] || claim[ORIGINATING_PARTY]).to_s

          if party.strip.empty?
            raise MissingField,
                  "a claim carries no originating party — it cannot be scoped, and defaulting " \
                  "it would recreate dedup-by-uuid for exactly the claims that skipped verification"
          end
          raise MissingField, "a claim carries no object uuid" if uuid.strip.empty?

          { OBJECT_UUID => uuid, ORIGINATING_PARTY => party }
        end

        objects = scoped.uniq
        conflicts = objects.group_by { |o| o[OBJECT_UUID] }
                           .select { |_uuid, group| group.length > 1 }
                           .map { |uuid, group| { OBJECT_UUID => uuid, "parties" => group.map { |o| o[ORIGINATING_PARTY] }.sort } }

        [ objects, conflicts ]
      end

      private

      def field_list(kind)
        spec.fetch("field-lists").fetch(kind.to_s) do
          raise UnknownKind, "unknown object kind #{kind.inspect} (known: #{kinds.join(', ')})"
        end
      end

      def resolve(kind, field_spec, args)
        return nfc(field_spec.fetch("literal")) if field_spec.key?("literal")

        name, rule, type =
          if field_spec.key?(ONE_OF)
            chosen = field_spec.fetch(ONE_OF).find { |candidate| present?(args, candidate) }
            raise MissingField, "#{kind}: none of #{field_spec[ONE_OF].join(' / ')} supplied" if chosen.nil?

            [ chosen, field_spec.fetch("normalise")[chosen], field_spec.fetch("type")[chosen] ]
          else
            [ field_spec.fetch("arg"), field_spec["normalise"], field_spec["type"] ]
          end

        raise MissingField, "#{kind}: #{name} is required and was not supplied" unless present?(args, name)

        value = nfc(normalise(rule, fetch(args, name), args, type))
        validate!(kind, name, type, value, args)
        value
      end

      # Validated AFTER normalisation, because that is the value the key is
      # built from — checking the raw input would pass a spelling the hashed
      # form rejects, or vice versa.
      def validate!(kind, name, type, value, args)
        return if type.nil?

        ok =
          if type == FAMILY_ID
            vocabulary_rule(args, FAMILY_ID) == "none" ? value.present? : TYPE_RULES.fetch(FAMILY_ID).call(value)
          elsif type == CONTROL_ID
            vocabulary_rule(args, CONTROL_ID) == "none" ? value.present? : value.match?(NIST_CONTROL_FORM)
          else
            TYPE_RULES.fetch(type).call(value)
          end

        return if ok

        raise InvalidField,
              "#{kind}: #{name} #{value.inspect} is not a valid #{type} " \
              "(#{spec.fetch('types')[type]})"
      end

      # The VOCABULARY decides how a control identifier is normalised. SPARC
      # owns the NIST form and canonicalises it; an identifier from another
      # authority is opaque and passes through untouched, because its casing is
      # that authority's business — `ACM.1` and `acm.1` are two Security Hub
      # controls, not two spellings of one.
      def normalise(rule, value, args, type = nil)
        rule = vocabulary_rule(args, type) if rule == "by-vocabulary"

        case rule
        when CONTROL_ID then ControlId.canonical(value)
        when "lowercase"  then value.to_s.downcase
        when "none", nil  then value.to_s
        else raise ArgumentError, "unknown normaliser #{rule.inspect}"
        end
      end

      # NOT defaulted. Without a vocabulary there is no way to know whether the
      # identifier may be canonicalised, and guessing NIST would canonicalise a
      # foreign identifier into something that validates and names nothing.
      # Keyed by vocabulary, then by the FIELD'S TYPE (#1175). A NIST control is
      # canonicalised; a NIST family is merely lowercased, because it is not a
      # control id. Under an opaque vocabulary neither is touched — `ACM` and
      # `acm` are two Security Hub families, not two spellings of one, and
      # lowercasing one into the other is how two runtimes derived two
      # identifiers for the same cell without either erroring.
      def vocabulary_rule(args, type)
        vocabulary = fetch(args, "vocabulary").to_s
        raise MissingField, "vocabulary is required for an object carrying a scoped identifier" if vocabulary.strip.empty?

        by_type = spec.fetch("vocabulary-normalisers").fetch(vocabulary) do
          raise InvalidField, "unknown vocabulary #{vocabulary.inspect} " \
                              "(known: #{spec.fetch('vocabulary-normalisers').keys.join(', ')})"
        end

        by_type.fetch(type.to_s) do
          raise InvalidField, "vocabulary #{vocabulary.inspect} declares no rule for a #{type.inspect} field"
        end
      end

      def fetch(args, name)   = args[name.to_sym] || args[name.to_s]
      def present?(args, name) = fetch(args, name).to_s.strip != ""
      def nfc(value)          = value.to_s.unicode_normalize(:nfc)
    end
  end
end
