# frozen_string_literal: true

# #1390 — records a boundary's answer to a FedRAMP rule or Key Security
# Indicator (FedrampStatement), and lists what applies to it with its answers.
# The boundary's FedRAMP page and Api::V1::FedrampStatementsController are
# thin clients of it.
#
# A rule may be answered only when it applies to the boundary's certification
# profile (type, path, class; FedrampRules.applicable). Any KSI may be
# answered: the SDR requires KSIs for 20x (SDR-CSX-KSI), and a Rev5 boundary
# may record them too.
#
# NIST SP 800-53: PL-2, CA-2, AU-12 (the controllers audit each change).
class FedrampStatementService
  class Error < StandardError; end

  FIELDS = %w[status implementation validation assessment].freeze
  KSI_FIELDS = %w[tests evidence].freeze

  Entry = Struct.new(:rule, :statement, keyword_init: true) do
    def id = rule.id
    def status = statement&.status
  end
  Result = Struct.new(:statement, :created, :changes, keyword_init: true)

  def initialize(boundary)
    @boundary = boundary
  end

  # Every rule (kind "frr") or KSI (kind "ksi") that applies, with the
  # boundary's statement, if any.
  def entries(kind)
    kind = check_kind!(kind)
    rules = kind == FedrampRules::FRR ? @boundary.fedramp_applicable_rules : FedrampRules.ksis
    by_id = @boundary.fedramp_statements.where(kind: kind).index_by(&:rule_id)
    rules.map { |rule| Entry.new(rule: rule, statement: by_id[rule.id]) }
  end

  # Counts by status ("Implemented", ..., nil for unanswered).
  def summary(kind) = entries(kind).group_by(&:status).transform_values(&:size)

  def record(kind:, rule_id:, attributes:, user:)
    kind = check_kind!(kind)
    rule = find!(kind, rule_id)
    statement = @boundary.fedramp_statements.find_or_initialize_by(kind: kind, rule_id: rule.id)
    created = statement.new_record?
    allowed = kind == FedrampRules::KSI ? FIELDS + KSI_FIELDS : FIELDS
    statement.assign_attributes(attributes.to_h.stringify_keys.slice(*allowed))
    changes = statement.changes.keys
    statement.updated_by = user if changes.any?
    raise Error, statement.errors.full_messages.to_sentence unless statement.save

    Result.new(statement: statement, created: created, changes: changes)
  end

  def find!(kind, rule_id)
    kind = check_kind!(kind)
    rule = if kind == FedrampRules::FRR
             @boundary.fedramp_applicable_rules.find { |r| r.id == rule_id.to_s }
    else
             FedrampRules.find_ksi(rule_id.to_s)
    end
    return rule if rule

    raise Error, applicability_message(kind, rule_id)
  end

  private

  def check_kind!(kind)
    kind = kind.to_s
    return kind if FedrampRules::KINDS.include?(kind)

    raise Error, "kind must be one of: #{FedrampRules::KINDS.join(', ')}"
  end

  def applicability_message(kind, rule_id)
    return "#{rule_id} is not a FedRAMP Key Security Indicator" if kind == FedrampRules::KSI
    unless @boundary.fedramp_profile_complete?
      return "Set the boundary's FedRAMP certification type, path and class first; they decide which rules apply"
    end

    type, path, klass = @boundary.fedramp_profile
    "#{rule_id} does not apply to a #{type} #{path} Class #{klass} provider"
  end
end
