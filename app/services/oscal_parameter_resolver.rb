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
# A **value** parameter resolves to, in order: the operator's set value (from
# the SSP or the profile), the catalog parameter's own `values` (#1241), the
# values its aggregated parts resolve to, the parameter's `guidelines[].prose`,
# its `label`. If none of those exist the markup is left standing — a gap in
# the catalog should look like a gap rather than like prose that trails off.
#
# #1241 — a catalog can ASSIGN a parameter (an organization's copy of SP 800-53
# with its ODPs filled in carries them in `values`). That assignment was never
# read: every screen fell through to the generic label. A set value still wins,
# because tailoring is what a profile and an SSP are for.
#
# A **select** parameter resolves to THE SELECTED CHOICES, each itself resolved,
# concatenated. Not the list of available options, and not the referenced ODPs
# emitted as separate lines: "we assemble per the construction rules and the
# selected value(s)". With both AC-20 branches selected the statement reads as
# one sentence, which is the whole point — a resolved profile that still says
# `{{ insert: param, … }}` has not been resolved.
#
# With nothing selected, a select resolves to the choices the CATALOG assigned
# in `values`, if any (#1241), and only then falls back to its options, so the
# reader can still see what the choice IS. Rendering nothing would silently
# delete the requirement.
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
    if param && param["select"].present?
      return resolve_selection(param, set_value.presence || catalog_values(param), depth)
    end

    return resolve_text(set_value, depth) if set_value.present?
    return nil if param.nil?

    assigned = catalog_values(param)
    return assigned.map { |value| resolve_text(value, depth) }.join(", ") if assigned.any?

    aggregated = resolve_aggregate(param, depth)
    return aggregated if aggregated

    prose = param.dig("guidelines", 0, "prose").presence
    return resolve_text(prose, depth) if prose

    param["label"].presence
  end

  private

  # The values the catalog itself assigns the parameter (#1241).
  def catalog_values(param)
    Array(param && param["values"]).map { |value| value.to_s.strip }.reject(&:blank?)
  end

  # Is this parameter answered, by a set value or by the catalog?
  def answered?(param_id)
    @values[param_id].present? || catalog_values(@params[param_id]).any?
  end

  # NIST Rev 5 writes some statements against an AGGREGATE parameter:
  # ac-1's text inserts `ac-1_prm_1`, whose `aggregates` props name the two
  # ODPs an organization actually sets (`ac-01_odp.01`, `ac-01_odp.02`). 142
  # parameters in Rev 5 are aggregates. Setting the parts used to change
  # nothing in the statement, which kept showing the aggregate's label.
  #
  # The aggregate stands for the values its parts carry (set, or assigned by
  # the catalog, #1241), each resolved, without repeats. With none of its
  # parts answered it returns nil, so the caller's fallback (guidelines, then
  # label) still applies.
  def resolve_aggregate(param, depth)
    part_ids = Array(param["props"]).select { |prop| prop["name"] == "aggregates" }.filter_map { |prop| prop["value"].presence }
    return nil if part_ids.empty?

    values = part_ids.filter_map { |id| answered?(id) && resolve_param(id, depth + 1) }.uniq
    values.presence&.join(", ")
  end

  # The chosen branches, each resolved, assembled into one string. `chosen` is
  # a stored set value (a joined string) or the catalog's `values` (an array).
  def resolve_selection(param, chosen, depth)
    choices = Array(param.dig("select", "choice"))
    chosen  = chosen.is_a?(Array) ? chosen : ParameterValueList.split(chosen)

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
