# frozen_string_literal: true

require "rails_helper"

# #1218 — the worksheets in docs/api/samples/ are published as files a team can
# fill in and send unchanged. That is a claim about SPARC, not about the files,
# so it is tested against profiles built the way SPARC builds them: the bundled
# Rev 5 catalog imported, each NIST baseline's controls selected and resolved
# (the path db/seeds.rb takes), and the worksheet PUT through the API.
RSpec.describe "Rev 5 ODP worksheets against SPARC profiles", type: :request do
  before(:context) do
    source = Rails.root.join(OdpWorksheetBuilder::CATALOG)
    result = CatalogImportService.call(File.open(source), File.basename(source))
    @catalog = result.is_a?(Hash) ? result[:catalog] : result
  end

  after(:context) do
    # before(:context) writes outside the per-example transaction.
    ProfileDocument.where(control_catalog_id: @catalog&.id).destroy_all
    @catalog&.destroy
  end

  let(:admin) { create(:user, :admin) }
  let(:api_token) { ApiToken.generate!(user: admin, name: "Test") }
  let(:headers) do
    { "Authorization" => "Bearer #{api_token.plaintext_token}", "Content-Type" => "application/json" }
  end
  let(:worksheets) { OdpWorksheetBuilder.new.worksheets }

  before { allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true) }

  def baseline_profile(level)
    sheet_ids = OdpWorksheetBuilder.new.send(:baseline_control_ids, OdpWorksheetBuilder::BASELINES.fetch(level))
    profile = ProfileDocument.create!(name: "Rev 5 #{level} worksheet check", control_catalog: @catalog,
                                      baseline_level: level, status: "completed")
    present = @catalog.catalog_controls.where(control_id: sheet_ids.to_a).pluck(:control_id)
    ProfileControlSelectionService.new(profile).update(present)
    profile.update!(resolved_catalog_json: JSON.parse(OscalResolvedProfileCatalogService.new(profile).export))
    profile
  end

  # Every parameter given a value and every selection its first choice — the
  # most a team could send in one request.
  def filled(sheet)
    {
      "parameters" => sheet["parameters"].map { |p| p.merge("value" => "value for #{p['param_id']}") },
      "selections" => sheet["selections"].map { |s| s.merge("selected" => [ s["choices"].first ]) }
    }
  end

  def parameter_rows(profile)
    ProfileControlField.joins(:profile_control)
                       .where(profile_controls: { profile_document_id: profile.id })
                       .where("field_name LIKE 'parameter:%'")
                       .order(:id).pluck(:id, :field_name, :field_value, :updated_at)
  end

  def put_sheet(profile, body)
    put "/api/v1/profile_documents/#{profile.id}/parameters", params: body.to_json, headers: headers
    JSON.parse(response.body)["data"]
  end

  %w[low moderate high].each do |level|
    describe "the #{level.upcase} worksheet" do
      let(:sheet) { worksheets.fetch("rev5-#{level}-odp.json") }
      let(:profile) { baseline_profile(level) }

      it "names only ids the #{level.upcase} baseline profile has, and every write lands" do
        data = put_sheet(profile, filled(sheet))

        unknown = data["validation_errors"].select { |e| e["error"].start_with?("Unknown") }
        expect(unknown).to be_empty, "ids the profile does not have: #{unknown.first(5).inspect}"
        expect(data["parameters_updated"]).to eq(sheet["parameters"].size)
        expect(data["selections_updated"]).to eq(sheet["selections"].size)
        expect(response).to have_http_status(:ok)
      end

      it "changes nothing when sent untouched" do
        # Building the profile stores the values the resolved baseline already
        # carries, so the test is that none of them moves, not that none exist.
        before_put = parameter_rows(profile)
        data = put_sheet(profile, sheet)

        expect(data["parameters_updated"]).to eq(0)
        expect(data["selections_updated"]).to eq(0)
        expect(data["skipped"].size).to eq(sheet["parameters"].size + sheet["selections"].size)
        expect(parameter_rows(profile)).to eq(before_put)
      end
    end
  end

  it "the catalog worksheet names only ids a profile on the whole catalog has" do
    profile = ProfileDocument.create!(name: "Rev 5 catalog worksheet check", control_catalog: @catalog, status: "completed")
    known = BaselineParameterService.new(profile).extract_schema
                                    .then { |s| s[:parameters].map { |p| p[:param_id] } + s[:selections].map { |p| p[:select_id] } }
                                    .to_set
    sheet = worksheets.fetch("rev5-catalog-odp.json")
    ids = sheet["parameters"].map { |p| p["param_id"] } + sheet["selections"].map { |s| s["select_id"] }

    expect(ids.reject { |id| known.include?(id) }).to be_empty
    expect(ids.size).to eq(1458)
  end
end
