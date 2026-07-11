# frozen_string_literal: true

require "rails_helper"

# #623 — parse-failure notification to the uploading user.
RSpec.describe DocumentParseMailer, type: :mailer do
  let(:uploader) { create(:user, email: "uploader@sparc.local") }
  let(:document) do
    create(:ssp_document, name: "ACME SSP", status: "failed",
      error_message: "Unexpected token at line 12", uploaded_by: uploader)
  end

  describe "#parse_failed" do
    context "when SMTP is enabled and the upload is attributable" do
      before do
        allow(SparcConfig).to receive(:enable_smtp?).and_return(true)
        allow(SparcConfig).to receive(:smtp_from_address).and_return("noreply@sparc.test")
        allow(SparcConfig).to receive(:app_host).and_return("sparc.test")
      end

      let(:mail) { described_class.parse_failed(document) }

      it "sends to the uploader" do
        expect(mail.to).to eq([ "uploader@sparc.local" ])
      end

      it "names the document type and title in the subject" do
        expect(mail.subject).to include("parse failed").and include("ACME SSP")
      end

      it "includes the failure reason in the body" do
        expect(mail.body.encoded).to include("Unexpected token at line 12")
      end
    end

    context "when SMTP is disabled" do
      before { allow(SparcConfig).to receive(:enable_smtp?).and_return(false) }

      it "produces no deliverable message" do
        expect(described_class.parse_failed(document).message).to be_a(ActionMailer::Base::NullMail)
      end
    end

    context "when the upload is not attributable to a user" do
      before { allow(SparcConfig).to receive(:enable_smtp?).and_return(true) }

      it "sends nothing when there is no uploader" do
        document.update!(uploaded_by: nil)
        expect(described_class.parse_failed(document).message).to be_a(ActionMailer::Base::NullMail)
      end
    end
  end
end
