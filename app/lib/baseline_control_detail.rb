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
  def initialize(catalog_control, values: {}, priority: nil)
    @catalog_control = catalog_control
    @values = (values || {}).compact
    @priority = priority.presence || catalog_control&.priority.presence
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

  # True when there is anything worth expanding for. A control with no prose,
  # no parameters and no guidance should not render an empty panel that invites
  # a click and shows nothing.
  def any?
    statement.present? || guidance.present? || parameters.any? || related_controls.any?
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

    resolver.resolve_text(text)
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
