# frozen_string_literal: true

require "rails_helper"

# #860 — the daily digest.
RSpec.describe UnmatchedGrantDigestJob do
  include ActiveJob::TestHelper
  include ActiveSupport::Testing::TimeHelpers

  subject(:job) { described_class.new }

  # The mailer is deliver_later, so the message exists only after the enqueued
  # job runs. Asserting on deliveries without this passes for a job that
  # enqueues nothing at all.
  def run = perform_enqueued_jobs { job.perform }

  let!(:admin) { create(:user, :admin) }
  let(:member) { create(:user) }

  def skip_grant(user: member, grant: "sparc:org:acme:member", reason: 'organization "acme" not found')
    AuditEvent.log(user: user, action: "idp_grant_skipped", provider: "oidc",
                   metadata: { grant: grant, reason: reason })
  end

  before { allow(SparcConfig).to receive(:enable_smtp?).and_return(true) }

  it "emails the administrators when grants were refused" do
    skip_grant

    expect { run }.to change { ActionMailer::Base.deliveries.size }.by(1)
  end

  it "sends nothing when nothing was refused" do
    expect { run }.not_to change { ActionMailer::Base.deliveries.size }
  end

  it "sends nothing when SMTP is not configured" do
    # A deployment with no mail is supported, not broken — the queue is still
    # readable in the admin area.
    allow(SparcConfig).to receive(:enable_smtp?).and_return(false)
    skip_grant

    expect { run }.not_to change { ActionMailer::Base.deliveries.size }
  end

  it "sends ONE digest however many refusals there were" do
    # One missing boundary produces a refusal per user per sign-in. Per-event
    # mail would send dozens of messages describing one thing to create, and
    # bulk mail gets filtered — which is how a real signal stops being one.
    6.times { skip_grant }
    skip_grant(user: create(:user))

    expect { run }.to change { ActionMailer::Base.deliveries.size }.by(1)
  end

  it "ignores refusals outside the 24 hour window" do
    travel_to(3.days.ago) { skip_grant }

    expect { run }.not_to change { ActionMailer::Base.deliveries.size }
  end

  it "reports distinct users, not raw sign-ins, in the body" do
    4.times { skip_grant }
    skip_grant(user: create(:user))

    run
    # Multipart: .body on the container is empty, so read the text part. An
    # assertion against the container passes for an email with no content.
    body = ActionMailer::Base.deliveries.last.text_part.body.to_s

    expect(body).to match(/Affected users: 2\b/),
      "expected 2 distinct users, got: #{body[/Affected users: \d+/]}"
    expect(body).to match(/Sign-ins: 5\b/)
    expect(body).to include('organization "acme" not found')
  end

  describe "when there are no administrators to tell" do
    it "does not raise" do
      admin.update!(admin: false)
      skip_grant

      expect { run }.not_to raise_error
    end
  end
end
