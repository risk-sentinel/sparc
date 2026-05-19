# frozen_string_literal: true

require "rails_helper"

# Issue #494 -- request specs for the new refresh_aws_config and
# refresh_aws_security_hub controller actions. Mirrors the existing
# refresh_cci flow but for the two AWS converters.
RSpec.describe "Converters refresh actions (#494)", type: :request do
  # Force auth on -- authorize_permission! short-circuits when
  # SparcConfig.any_auth_enabled? is false, which would let non-admins
  # through and break the RBAC assertions below. CI defaults to auth
  # disabled; local dev may default either way.
  before { allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true) }

  let(:admin) { create(:user, :admin) }

  let!(:aws_config_converter) do
    Converter.create!(
      name: "AWS Config Rule → NIST SP 800-53",
      converter_type: "aws_config_to_nist",
      source_framework: "AWS Config Rules",
      target_framework: "NIST SP 800-53",
      version: "test", description: "spec", status: "complete"
    )
  end

  let!(:sec_hub_converter) do
    Converter.create!(
      name: "AWS Security Hub → NIST SP 800-53 rev5",
      converter_type: "aws_security_hub_to_nist",
      source_framework: "AWS Security Hub",
      target_framework: "NIST SP 800-53",
      version: "test", description: "spec", status: "complete"
    )
  end

  describe "POST /converters/:id/refresh_aws_config" do
    context "as admin (converters.write)" do
      before { sign_in_as(admin) }

      it "enqueues ConverterRefreshJob and flips status to processing" do
        expect {
          post refresh_aws_config_converter_path(aws_config_converter)
        }.to have_enqueued_job(ConverterRefreshJob).with(aws_config_converter.id)

        aws_config_converter.reload
        expect(aws_config_converter.status).to eq("processing")
        expect(response).to redirect_to(aws_config_converter)
        expect(flash[:success]).to match(/MITRE/i)
      end

      it "writes a converter_refresh_started audit event" do
        expect {
          post refresh_aws_config_converter_path(aws_config_converter)
        }.to change { AuditEvent.where(action: "converter_refresh_started").count }.by(1)
      end

      it "no-ops with a flash warning when a refresh is already in progress" do
        aws_config_converter.update!(status: "processing")
        expect {
          post refresh_aws_config_converter_path(aws_config_converter)
        }.not_to have_enqueued_job(ConverterRefreshJob)
        expect(flash[:warning]).to match(/already in progress/i)
      end

      it "rejects refresh on a different converter type" do
        post refresh_aws_config_converter_path(sec_hub_converter)
        expect(flash[:error]).to match(/aws_config_to_nist/)
      end
    end

    context "without converters.write" do
      it "blocks unauthenticated requests" do
        post refresh_aws_config_converter_path(aws_config_converter)
        expect(response).not_to have_http_status(:ok)
      end

      it "blocks signed-in non-admin users" do
        sign_in_as(create(:user))
        expect {
          post refresh_aws_config_converter_path(aws_config_converter)
        }.not_to have_enqueued_job(ConverterRefreshJob)
      end
    end
  end

  describe "POST /converters/:id/refresh_aws_security_hub" do
    context "as admin (converters.write)" do
      before { sign_in_as(admin) }

      it "enqueues ConverterRefreshJob and flips status to processing" do
        expect {
          post refresh_aws_security_hub_converter_path(sec_hub_converter)
        }.to have_enqueued_job(ConverterRefreshJob).with(sec_hub_converter.id)

        sec_hub_converter.reload
        expect(sec_hub_converter.status).to eq("processing")
        expect(response).to redirect_to(sec_hub_converter)
        expect(flash[:success]).to match(/Security Hub/i)
      end

      it "writes a converter_refresh_started audit event" do
        expect {
          post refresh_aws_security_hub_converter_path(sec_hub_converter)
        }.to change { AuditEvent.where(action: "converter_refresh_started").count }.by(1)
      end

      it "no-ops with a flash warning when a refresh is already in progress" do
        sec_hub_converter.update!(status: "processing")
        expect {
          post refresh_aws_security_hub_converter_path(sec_hub_converter)
        }.not_to have_enqueued_job(ConverterRefreshJob)
        expect(flash[:warning]).to match(/already in progress/i)
      end

      it "rejects refresh on a different converter type" do
        post refresh_aws_security_hub_converter_path(aws_config_converter)
        expect(flash[:error]).to match(/aws_security_hub_to_nist/)
      end
    end

    context "without converters.write" do
      it "blocks signed-in non-admin users" do
        sign_in_as(create(:user))
        expect {
          post refresh_aws_security_hub_converter_path(sec_hub_converter)
        }.not_to have_enqueued_job(ConverterRefreshJob)
      end
    end
  end
end
