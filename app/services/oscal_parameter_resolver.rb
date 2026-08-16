# frozen_string_literal: true

# Resolves OSCAL `{{ insert: param, <id> }}` into the text it stands for (#942).
#
# OSCAL composes control prose out of parameters, and those parameters compose
# out of each other. AC-20 nests two levels:
#
#   statement    "{{ insert: param, ac-20_odp.01 }} , consistent with the trust
#                 relationships established with other organizations…"
#   odp.01       SELECT one-or-more
#                  "establish {{ insert: param, ac-20_odp.02 }} "
#                  "identify {{ insert: param, ac-20_odp.03 }} "
#   odp.02       label "terms and conditions"
#                guidelines[0].prose "terms and conditions consistent with the
#                  trust relationships … are defined (if selected);"
#
# So substituting odp.01 yields text that itself needs substituting. Resolution
# is therefore recursive, not a single pass.
#
# ── The construction rule (owner-decided) ──────────────────────────────────
#
# A **value** parameter resolves to, in order: the operator's set value, the
# parameter's `guidelines[].prose`, its `label`. If none of those exist the
# markup is left standing — a gap in the catalog should look like a gap rather
# than like prose that trails off.
#
# A **select** parameter resolves to THE SELECTED CHOICES, each itself resolved,
# concatenated. Not the list of available options, and not the referenced ODPs
# emitted as separate lines: "we assemble per the construction rules and the
# selected value(s)". With both AC-20 branches selected the statement reads as
# one sentence, which is the whole point — a resolved profile that still says
# `{{ insert: param, … }}` has not been resolved.
#
# With nothing selected, a select falls back to its options so the reader can
# still see what the choice IS. Rendering nothing would silently delete the
# requirement.
#
# NIST 800-53: CM-6 (configuration settings — a parameter value is the setting),
# CA-2 (a control statement is only assessable once its ODPs are resolved).
class OscalParameterResolver
  # Cycle guard. OSCAL does not forbid a parameter referencing one that
  # references it back, and an unbounded recursion here would take out the
  # export rather than produce imperfect prose.
  MAX_DEPTH = 8

  # @param params [Array<Hash>] the OSCAL parameter definitions in scope
  # @param values [Hash] param_id => the operator's set value, if any
  def initialize(params, values = {})
    @params = Array(params).index_by { |param| param["id"] }
    @values = values || {}
  end

  # Substitute every reference in a piece of prose.
  def resolve_text(text, depth = 0)
    return text.to_s if depth > MAX_DEPTH || text.blank?

    OscalParamReference.resolve_with(text) do |param_id|
      resolve_param(param_id, depth + 1)
    end
  end

  # The text a single parameter stands for, or nil to leave the markup alone.
  def resolve_param(param_id, depth = 0)
    return nil if depth > MAX_DEPTH

    param = @params[param_id]
    set_value = @values[param_id]

    # A select's stored value is WHICH branches were chosen, not the finished
    # text, so it is resolved as a selection rather than used verbatim.
    return resolve_selection(param, set_value, depth) if param && param["select"].present?

    return resolve_text(set_value, depth) if set_value.present?
    return nil if param.nil?

    prose = param.dig("guidelines", 0, "prose").presence
    return resolve_text(prose, depth) if prose

    param["label"].presence
  end

  private

  # The chosen branches, each resolved, assembled into one string.
  def resolve_selection(param, set_value, depth)
    choices = Array(param.dig("select", "choice"))
    chosen  = ParameterValueList.split(set_value)

    # Only the branches actually taken. An unrecognised stored value is kept
    # rather than dropped: it may be a hand-written answer, and discarding what
    # someone wrote because it is not one of the offered options would lose it
    # silently.
    selected = chosen.presence || choices
    selected.map { |choice| resolve_text(choice, depth).strip }
            .reject(&:blank?)
            .join(" ")
            .presence
  end
end
