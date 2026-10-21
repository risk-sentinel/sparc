# frozen_string_literal: true

# Records an assessor's determination of one 800-53A objective. The web form
# and the API both call this. The control's risk, and so the POA&M, follows
# through SarControlRiskSync, which SarControlObjective runs on a status change.
#
# NIST 800-53: CA-2 (control assessments), CA-5, CA-7.
class SarObjectiveDetermination
  DETERMINED = %w[passing failed].freeze

  def initialize(objective)
    @objective = objective
  end

  # @return [Boolean] false with errors on the objective when it is invalid
  def record(status: nil, assessor_name: nil, assessor_notes: nil)
    attrs = { status: status, assessor_name: assessor_name, assessor_notes: assessor_notes }.compact
    attrs[:assessed_at] = Time.current if DETERMINED.include?(status.to_s)
    return false unless @objective.update(attrs)

    @objective.sar_control.sar_document.regenerate_oscal_uuid!
    true
  end
end
