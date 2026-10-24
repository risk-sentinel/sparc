# frozen_string_literal: true

require "rails_helper"

# #1268 — Refresh Now says "queued" only when the job was queued, and the CDEF
# screen shows what the last refresh did.
RSpec.describe "AWS Labs refresh, as the operator sees it (#1268)", type: :request do
  let(:admin) { create(:user, :admin) }

  before do
    allow(SparcConfig).to receive_messages(any_auth_enabled?: true, aws_labs_cdef_enabled?: true)
    sign_in_as(admin)
  end

  describe "POST /cdef_documents/refresh_aws_labs" do
    it "reports a job the queue did not accept as an error, not as queued" do
      declined = AwsLabsCdefRefreshJob.new(force: true)
      allow(declined).to receive(:successfully_enqueued?).and_return(false)
      allow(AwsLabsCdefRefreshJob).to receive(:perform_later).and_return(declined)
      allow(Rails.cache).to receive(:delete).and_call_original

      post refresh_aws_labs_cdef_documents_path

      expect(flash[:error]).to match(/could not be queued/)
      expect(flash[:success]).to be_nil
      expect(AuditEvent.where(action: "aws_labs_cdef_refresh_enqueue_failed")).to exist
      expect(AuditEvent.where(action: "aws_labs_cdef_refresh_requested")).not_to exist
      expect(Rails.cache).to have_received(:delete).with("aws_labs_cdef_refresh:in_flight")
    end

    it "reports a queue that raised" do
      allow(AwsLabsCdefRefreshJob).to receive(:perform_later).and_raise(ActiveJob::EnqueueError, "Invented outage")

      post refresh_aws_labs_cdef_documents_path

      expect(flash[:error]).to eq("The AWS Labs refresh could not be queued: ActiveJob::EnqueueError: Invented outage")
    end

    it "says queued, and how long a refresh takes, when it was" do
      post refresh_aws_labs_cdef_documents_path

      expect(flash[:success]).to match(/queued\. It takes one to two minutes/)
    end
  end

  describe "the CDEF screen" do
    it "shows the last refresh's outcome to someone who may start one" do
      AuditEvent.log(action: "aws_labs_cdef_refresh_kept_nothing",
                     metadata: { discovered: 230, kept: 0, skipped_by_version: { "1.2.1" => 230 }, allowed_versions: %w[1.2.3] })

      get cdef_documents_path

      status = Nokogiri::HTML(response.body).at_css("[data-testid='aws-labs-refresh-status']")
      expect(status["data-state"]).to eq("kept_nothing")
      expect(status.text.squish).to include("imported nothing", "1.2.1 (230)", "allows 1.2.3")
    end

    it "shows no status to someone who may not start a refresh" do
      sign_in_as(create(:user))

      get cdef_documents_path

      expect(response.body).not_to include("aws-labs-refresh-status")
    end

    it "no longer says a refresh takes a few seconds" do
      get cdef_documents_path

      expect(response.body).not_to include("a few seconds")
      expect(response.body).to include("takes one to two minutes")
    end
  end
end
