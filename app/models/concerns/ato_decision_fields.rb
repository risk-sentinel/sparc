# frozen_string_literal: true

# The AO-decision fields a risk can carry (#1154), exported as the SPARC
# namespace props `blocks-ato`, `condition-expires` and `trigger`:
#
#   blocks_ato         nullable boolean — nil means "not decided", which is not
#                      the same claim as false, so it is never defaulted
#   condition_expires  date the condition on the decision lapses
#   reopen_trigger     the metric condition that reopens the decision, in the
#                      contract's grammar: `score<0.85`, `blockers>=1`
#
# Every column is optional; each is validated only where the model has it (a
# SAR risk carries blocks_ato alone — see the migrations for why).
#
# The checks read the value BEFORE type casting, because the casts are lossy in
# exactly the way that hides bad input: ActiveModel turns "maybe" into `true`
# and "2026-13-40" into nil, so a caller would be told their value was saved
# when it was replaced. The rule is SI-10 (information input validation):
# refuse what cannot be represented rather than store something else.
module AtoDecisionFields
  extend ActiveSupport::Concern

  BOOLEAN_INPUTS = [ true, false, "true", "false", "1", "0", 1, 0 ].freeze

  included do
    validate :blocks_ato_is_a_boolean
    validate :condition_expires_is_a_date
    validate :reopen_trigger_matches_the_contract
    before_validation :blank_reopen_trigger_is_nil
  end

  private

  def ato_column?(name) = has_attribute?(name)

  def blank_reopen_trigger_is_nil
    self.reopen_trigger = reopen_trigger.presence&.strip if ato_column?(:reopen_trigger)
  end

  def blocks_ato_is_a_boolean
    return unless ato_column?(:blocks_ato)

    raw = blocks_ato_before_type_cast
    return if raw.nil? || raw == "" || BOOLEAN_INPUTS.include?(raw)

    errors.add(:blocks_ato, "must be true, false or empty (not decided)")
  end

  def condition_expires_is_a_date
    return unless ato_column?(:condition_expires)

    raw = condition_expires_before_type_cast
    return if raw.blank? || raw.is_a?(Date) || raw.is_a?(Time)
    return if raw.is_a?(String) && SparcNamespaceProps.iso_date(raw)

    errors.add(:condition_expires, "must be a date in the form YYYY-MM-DD")
  end

  def reopen_trigger_matches_the_contract
    return unless ato_column?(:reopen_trigger)
    return if reopen_trigger.blank? || reopen_trigger.match?(SparcNamespaceProps::TRIGGER_PATTERN)

    errors.add(:reopen_trigger, "must be score or blockers, a comparison (<, <=, >, >=) and a number — " \
                                "for example score<0.85 or blockers>=1")
  end
end
