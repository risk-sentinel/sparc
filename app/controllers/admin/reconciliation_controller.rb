# frozen_string_literal: true

module Admin
  # #911 layer 2 — instance-wide catalog-lineage report.
  #
  # Read-only. The fix for any individual row lives on that document's own page,
  # where the author has the context to choose the right baseline; offering a
  # bulk "set them all" here would invite exactly the guess the design forbids —
  # SPARC never picks a baseline on a user's behalf.
  class ReconciliationController < ApplicationController
    before_action :authorize_admin!

    def index
      @report = ReconciliationReportService.new
    end
  end
end
