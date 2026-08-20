# frozen_string_literal: true

# What a baseline actually requires of one control, assembled once for every
# screen that shows it (#997).
#
# ── Why this exists ────────────────────────────────────────────────────────
#
# The Profile screen listed control identifiers grouped by family with priority
# counts, and stopped. It never showed the control language, the parameters,
# the control's own priority, the guidance or the related controls — so a
# reviewer could not answer "what does this baseline actually require?" without
# leaving SPARC, and an operator who tailored an ODP through the API had no way
# to confirm from the product that the tailoring was what they intended.
#
# Nearly all of it already existed and was simply not reachable from these
# screens: the prose is on `catalog_controls`, the substitution is
# OscalParameterResolver (#942), the values are `profile_control_fields`. This
# class puts them together in one place so the Profile screen and the SSP
# screen render the same content from the same definition instead of growing a
# third and fourth copy of `control_families/show.html.erb`.
#
# ── The one rule that matters ──────────────────────────────────────────────
#
# Prose is ALWAYS resolved. Showing a reviewer
# `{{ insert: param, ac-20_odp.01 }}` would be worse than showing nothing: it
# is markup where the organization-defined text belongs, and it reads as a
# defect in the baseline rather than in the display. Every string this class
# hands to a template has been through OscalParameterResolver.
class BaselineControlDetail
  # One parameter, in the forms a screen needs: what to call it, what it is for,
  # what the operator answered, and what that answer READS as once resolved.
  Parameter = Struct.new(
    :id, :label, :description, :select, :how_many, :choices, :value, :display,
    keyword_init: true
  ) do
    def select? = select.present?
    def answered? = value.present?
  end

  attr_reader :catalog_control, :priority

  # @param catalog_control [CatalogControl] the control as the catalog defines it
  # @param values [Hash] param_id => the value this profile has set, if any
  # @param priority [String, nil] the profile's priority override, if it has one
  # @param sub_parts [Array<CatalogControl>] the control's statement sub-parts,
  #   preloaded by the controller (grouped by CatalogControl.sub_parts_by_parent)
  def initialize(catalog_control, values: {}, priority: nil, sub_parts: [])
    @catalog_control = catalog_control
    @values = (values || {}).compact
    @priority = priority.presence || catalog_control&.priority.presence
    @raw_sub_parts = Array(sub_parts)
  end

  def resolver
    @resolver ||= OscalParameterResolver.new(param_definitions, @values)
  end

  def statement
    @statement ||= resolve(guidance_hash["statement"])
  end

  def guidance
    @guidance ||= resolve(guidance_hash["supplemental_guidance"])
  end

  # Ids only. The screen decides whether it can link them; this decides what
  # the baseline says they are.
  def related_controls
    @related_controls ||= guidance_hash["related_controls"].to_s
                                                           .split(",")
                                                           .map(&:strip)
                                                           .reject(&:blank?)
  end

  def parameters
    @parameters ||= param_definitions.map { |param| build_parameter(param) }
  end

  # One statement sub-part, in the form a screen needs it.
  SubPart = Struct.new(:display_id, :title, keyword_init: true)

  # The control's statement sub-parts, TITLES RESOLVED (#1002).
  #
  # These are half the policy language on the panel — "ac-1a Develops,
  # documents, and disseminates to ..." — and they used to be rendered straight
  # from the catalog by the Profile view, which is why they were the one string
  # on the screen still showing `{{ insert: param, ac-1_prm_1 }}`. 734
  # catalog_controls carry insert markup in `title`, so it was not an edge case.
  #
  # Sorting lives here rather than in a template so the Profile and SSP screens
  # cannot order the same control's statement differently.
  def sub_parts
    @sub_parts ||= @raw_sub_parts
      .sort_by { |sp| sp.sort_id || sp.control_id.to_s.gsub(/\d+/) { |n| n.rjust(3, "0") } }
      .map { |sp| SubPart.new(display_id: sp.display_id, title: humanize(sub_part_resolver.resolve_text(sp.title))) }
  end

  # Sub-parts do not all reference the PARENT's parameters. `ac-1a` references
  # `ac-1_prm_1`, declared on ac-1 — but `ac-1b.1` references `ac-1_prm_2`,
  # which is not in the parent's list at all. Resolving sub-part prose against
  # the parent's definitions alone therefore left exactly those references
  # standing, which is the same defect one level down: measured on the SSP
  # screen, ac-1a resolved while ac-1b.1 still read
  # "Access control policy {{ insert: param, ac-1_prm_2 }}; and".
  #
  # One resolver over the union, built once per control rather than per
  # sub-part, so a control with a dozen parts does not build a dozen resolvers.
  def sub_part_resolver
    @sub_part_resolver ||= begin
      merged = (param_definitions + @raw_sub_parts.flat_map { |sp|
        Array(sp.effective_params_list)
      }).uniq { |param| param["id"] }
      OscalParameterResolver.new(merged, @values)
    end
  end

  # A catalog SUB-PART's title, resolved against this profile's values (#1002).
  #
  # Sub-parts are loaded by the controller and rendered alongside everything
  # this class assembles, so they used to be the one string on the panel that
  # reached the screen raw — `ac-1a` reads "Develops, documents, and
  # disseminates to {{ insert: param, ac-1_prm_1 }}:" in the catalog, and that
  # is exactly what a reviewer saw. 734 catalog_controls carry insert markup in
  # `title`, so this was not an edge case.
  #
  # It routes through the same resolver as `statement`, which is what makes the
  # class's promise — every string handed to a template has been resolved —
  # true for the whole panel rather than most of it. `effective_params_list`
  # matters here specifically: a sub-part references parameters declared on its
  # PARENT, so resolving against the local set alone would leave exactly these
  # references standing.
  def sub_part_title(text)
    resolve(text)
  end

  # True when there is anything worth expanding for. A control with no prose,
  # no parameters and no guidance should not render an empty panel that invites
  # a click and shows nothing.
  def any?
    statement.present? || guidance.present? || parameters.any? ||
      related_controls.any? || sub_parts.any?
  end

  private

  def guidance_hash
    @guidance_hash ||= catalog_control&.guidance_hash || {}
  end

  # `effective_params_list` rather than `params_list`: a statement sub-part
  # references parameters declared on its PARENT ("ac-1a" referencing
  # "ac-1_prm_1"), and resolving only the local set leaves exactly those
  # references standing.
  def param_definitions
    @param_definitions ||= Array(catalog_control&.effective_params_list)
  end

  def resolve(text)
    return nil if text.blank?

    humanize(resolver.resolve_text(text))
  end

  # Last line of defence for the SCREEN: a reference the resolver could not
  # substitute must still not reach the reader as OSCAL markup (#1002).
  #
  # `OscalParameterResolver#resolve_param` returns nil — leave the markup
  # standing — when it has no definition and no value. That is right for an
  # EXPORT, where inventing text would be a lie about the baseline (#942), and
  # wrong for a screen, where this class's whole rule is that markup is worse
  # than nothing.
  #
  # Two things reach here. A reference to a parameter defined in a DIFFERENT
  # catalog, which is a data-scoping problem; and a reference that is simply
  # broken — CatalogImportService stores a sub-part's prose as its title with
  # `prose.truncate(200)`, and 44 controls are cut mid-reference, leaving
  # `{{ insert: param, cm-06...` with no closing brace and no recoverable id.
  # Neither is resolvable here, and neither should be shown as markup.
  #
  # The id is kept when it is intact, because "which ODP is missing" is the
  # first thing a reviewer asks; a mangled id is dropped rather than displayed.
  def humanize(text)
    return text if text.blank? || !text.include?("insert:")

    text
      .gsub(/\{\{\s*insert:\s*param,\s*([A-Za-z0-9_.\-]+)\s*\}\}/) {
        "[organization-defined: #{Regexp.last_match(1)}]"
      }
      .gsub(/\{\{\s*insert:\s*param,[^}]*\z/, "[organization-defined parameter]")
      .gsub(/\{\{\s*insert:\s*param,[^}]*\}\}/, "[organization-defined parameter]")
  end

  def build_parameter(param)
    id = param["id"]
    select = param["select"]

    Parameter.new(
      id:          id,
      label:       param["label"],
      description: param.dig("guidelines", 0, "prose").presence,
      select:      select,
      how_many:    select && (select["how-many"] || "one"),
      # Resolved, because a choice can itself be composed from other parameters
      # ("establish {{ insert: param, ac-20_odp.02 }}") and raw markup is not an
      # option a person can choose between.
      choices:     Array(select && select["choice"]).map { |choice| resolver.resolve_text(choice).strip },
      value:       @values[id],
      display:     resolver.resolve_param(id)
    )
  end
end
