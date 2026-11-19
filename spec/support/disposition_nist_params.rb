# frozen_string_literal: true

# #1368 — every disposition decided now carries its NIST POA&M fields
# (FindingDispositionService requires them). One definition for the specs that
# decide one through the service, the triage form or the API.
module DispositionNistParams
  def nist_params(kind = nil)
    {
      nist_risk_prop: kind.to_s == "falsePositive" ? "false-positive" : "accepted",
      nist_risk_status: "deviation-requested",
      nist_response_lifecycle: "planned",
      nist_facet_state: "initial",
      nist_likelihood: "moderate",
      nist_impact: "high"
    }
  end
end

RSpec.configure do |config|
  config.include DispositionNistParams
end
