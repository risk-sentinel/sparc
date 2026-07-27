# frozen_string_literal: true

module Admin
  # #809 (D3) — Instance-Admin screen for the remediation-timeline (SLA) table:
  # how many days to remediate, keyed by profile baseline × NIST criticality.
  # Feeds amendment-validity when a control has no profile ODP remediation value.
  class RemediationTimelinesController < ApplicationController
    before_action :authorize_admin!

    def index
      @grid = grid
    end

    def update
      row = RemediationTimeline.find_or_initialize_by(
        baseline_level: params[:baseline_level], criticality: params[:criticality]
      )
      row.days = params[:days]
      row.updated_by = current_user&.email
      if row.save
        redirect_to admin_remediation_timelines_path,
                    notice: "#{row.baseline_level} / #{row.criticality} set to #{row.days} days."
      else
        redirect_to admin_remediation_timelines_path, alert: row.errors.full_messages.to_sentence
      end
    end

    private

    def grid
      provisioned = RemediationTimeline.all.index_by { |r| [ r.baseline_level, r.criticality ] }
      RemediationTimeline::BASELINE_LEVELS.index_with do |baseline|
        RemediationTimeline::CRITICALITIES.index_with do |criticality|
          row = provisioned[[ baseline, criticality ]]
          { days: row&.days || RemediationTimeline::DEFAULTS.dig(baseline, criticality),
            provisioned: row.present? }
        end
      end
    end
  end
end
