# frozen_string_literal: true

# #1354 / #1384 — records the provider's FedRAMP evaluation of one detected
# vulnerability in a boundary. The one write path: the API
# (PUT /api/v1/authorization_boundaries/:id/fedramp_evaluations/:control_id)
# and the triage screen both call #record, so the same input is refused the
# same way on both.
#
# The fields are FedRAMP's (FRR.VER): internet-reachable (VER-EVA-EIR), likely
# exploitable (VER-EVA-ELX), the Potential Agency Impact N-rating, N0–N5
# (VER-EVA-EPA), and what a Vulnerability Detail Report carries about it
# (VER-RPT-VDT): when it was evaluated, the planned next reduction and
# supplementary information.
#
# An upsert keyed by (boundary, control_id): only the fields given change.
# evaluated_at is set to now the first time a vulnerability is evaluated
# unless the caller names it, and it cannot be cleared. A control the
# boundary has never had a failing finding for is not a detected
# vulnerability, and is refused.
#
# NIST SP 800-53: RA-3 (risk assessment — the N-rating), RA-5 (vulnerability
# monitoring and scanning), SI-2 (flaw remediation planning), AU-12 (who
# evaluated, and when; the callers audit `fedramp_evaluation_recorded`).
class FedrampEvaluationService
  class Error < StandardError; end

  Result = Struct.new(:evaluation, :created, :changes, keyword_init: true)

  FIELDS = %i[internet_reachable likely_exploitable pain_rating evaluated_at
              next_reduction_at next_reduction_rating supplementary_info].freeze
  BOOLEAN_FIELDS = %i[internet_reachable likely_exploitable].freeze
  RATING_FIELDS  = %i[pain_rating next_reduction_rating].freeze
  TIME_FIELDS    = %i[evaluated_at next_reduction_at].freeze
  TRUE_VALUES  = [ true, "true", "1", 1, "yes" ].freeze
  FALSE_VALUES = [ false, "false", "0", 0, "no" ].freeze
  MAX_SUPPLEMENTARY_INFO = 10_000

  def initialize(boundary)
    @boundary = boundary
  end

  # attributes: only the keys present are applied (string or symbol keys).
  def record(control_id:, attributes:, user:)
    control_id = control_id.to_s
    unless @boundary.scanner_findings.failed.exists?(control_id: control_id)
      raise Error, "This boundary has no failing finding for #{control_id}; only a detected vulnerability is evaluated"
    end

    attempts = 0
    begin
      attempts += 1
      save(control_id, attributes.to_h.symbolize_keys, user)
    rescue ActiveRecord::RecordNotUnique
      # Two first evaluations at once: the loser retries as an update.
      retry if attempts < 2
      raise
    end
  end

  private

  def save(control_id, attributes, user)
    evaluation = @boundary.fedramp_vulnerability_evaluations.find_or_initialize_by(control_id: control_id)
    created = evaluation.new_record?
    (attributes.keys & FIELDS).each { |field| assign(evaluation, field, attributes[field]) }
    evaluation.evaluated_at ||= Time.current
    evaluation.evaluated_by = user if user
    changes = evaluation.changes.keys - %w[updated_at created_at]
    evaluation.save!
    Result.new(evaluation: evaluation, created: created, changes: changes)
  rescue ActiveRecord::RecordInvalid => e
    raise Error, e.record.errors.full_messages.join("; ")
  end

  def assign(evaluation, field, raw)
    value =
      if BOOLEAN_FIELDS.include?(field) then boolean(field, raw)
      elsif RATING_FIELDS.include?(field) then rating(field, raw)
      elsif TIME_FIELDS.include?(field) then time(field, raw)
      else supplementary_info(raw)
      end
    # A blank evaluated_at leaves it as it is: an evaluation cannot be un-evaluated.
    return if field == :evaluated_at && value.nil?

    evaluation.public_send(:"#{field}=", value)
  end

  def blank?(raw) = raw.nil? || (raw.is_a?(String) && raw.strip.empty?)

  def boolean(field, raw)
    return nil if blank?(raw)
    return true if TRUE_VALUES.include?(raw.is_a?(String) ? raw.strip.downcase : raw)
    return false if FALSE_VALUES.include?(raw.is_a?(String) ? raw.strip.downcase : raw)

    raise Error, "#{field} must be true or false"
  end

  def rating(field, raw)
    return nil if blank?(raw)

    value = raw.is_a?(Integer) ? raw : Integer(raw.to_s.strip.delete_prefix("N").delete_prefix("n"), exception: false)
    raise Error, "#{field} must be an N-rating from 0 to 5" unless value && FedrampVulnerabilityEvaluation::PAIN_RATINGS.cover?(value)

    value
  end

  def time(field, raw)
    return nil if blank?(raw)

    parsed = begin
      Time.zone.parse(raw.to_s)
    rescue ArgumentError
      nil
    end
    raise Error, "#{field} must be a date or an ISO 8601 time" if parsed.nil?

    parsed
  end

  def supplementary_info(raw)
    return nil if blank?(raw)

    text = raw.to_s
    raise Error, "supplementary_info must be at most #{MAX_SUPPLEMENTARY_INFO} characters" if text.length > MAX_SUPPLEMENTARY_INFO

    text
  end
end
