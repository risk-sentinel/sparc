# frozen_string_literal: true

require "rails_helper"

RSpec.describe "STIG Parser", type: :request do
  let(:user) { create(:user, :admin) }
  let(:rhel_fixture) { Rails.root.join("spec/fixtures/files/stigs/U_RHEL_9_STIG_V2R7_Manual-xccdf.xml") }

  before { sign_in_as(user) }

  describe "GET /converters/stig_parser" do
    it "renders the STIG parser page" do
      get stig_parser_converters_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("STIG Parser")
      expect(response.body).to include("XCCDF")
    end
  end

  describe "POST /converters/import_stig" do
    context "with a valid XCCDF file" do
      it "creates a stig_to_nist converter and redirects" do
        file = Rack::Test::UploadedFile.new(rhel_fixture, "application/xml")

        expect {
          post import_stig_converters_path, params: { stig_file: file }
        }.to change(Converter, :count).by(1)

        converter = Converter.find_by(converter_type: "stig_to_nist")
        expect(converter).to be_present
        expect(converter.converter_entries.count).to be > 0
        expect(response).to redirect_to(converter_path(converter))

        follow_redirect!
        expect(response).to have_http_status(:ok)
      end
    end

    context "with no file" do
      it "redirects back with error" do
        post import_stig_converters_path
        expect(response).to redirect_to(stig_parser_converters_path)
        follow_redirect!
        expect(response.body).to include("Please select")
      end
    end

    context "with a non-XML file" do
      it "redirects back with error" do
        tmpfile = Tempfile.new([ "test", ".json" ])
        tmpfile.write("not xml")
        tmpfile.rewind
        file = Rack::Test::UploadedFile.new(tmpfile.path, "application/json")
        post import_stig_converters_path, params: { stig_file: file }
        expect(response).to redirect_to(stig_parser_converters_path)
      ensure
        tmpfile&.close!
      end
    end
  end

  describe "converter slug URLs" do
    it "serves converter show page via slug" do
      converter = Converter.create!(
        name: "Test Converter",
        converter_type: "custom",
        status: "draft"
      )
      expect(converter.slug).to eq("test-converter")

      get converter_path(converter)
      expect(response).to have_http_status(:ok)
    end
  end
end
