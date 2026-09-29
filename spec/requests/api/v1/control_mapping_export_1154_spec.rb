# frozen_string_literal: true

require "rails_helper"

# #1154 part 2 — `GET /api/v1/control_mappings/:id/export` serves the OSCAL
# mapping collection, so Horizon can swap its heatmap axis THROUGH SPARC's
# mapping documents rather than a mapping it carries itself.
#
# Same body as every OSCAL document export (OscalApiExport): format, validate,
# strong ETag / 304, and the 422s. Two differences, both deliberate:
#   * the default is `oscal` — a mapping has no SPARC field-JSON export;
#   * `oscal-xml` is refused by name — SPARC carries no OSCAL mapping XSD, so
#     XML could be neither ordered nor validated.
#
# Reads are open to any authenticated caller, as `show` is; writes stay gated.
RSpec.describe "Api::V1 control mapping export (#1154)", type: :request do
  let(:admin) { create(:user, :admin) }
  let(:headers) { bearer_for(admin) }
  let(:mapping) { create(:control_mapping, :complete, description: "A reviewed crosswalk.") }
  let!(:entry) { create(:control_mapping_entry, control_mapping: mapping, source_control_id: "ac-2", target_control_id: "a.5.1") }
  let(:path) { "/api/v1/control_mappings/#{mapping.slug}/export" }

  before { allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true) }

  def bearer_for(user)
    { "Authorization" => "Bearer #{ApiToken.generate!(user: user, name: SecureRandom.hex(4)).plaintext_token}" }
  end

  describe "the default" do
    it "is the validated OSCAL mapping collection, and is audited" do
      expect {
        get path, headers: headers
      }.to change { AuditEvent.where(action: "control_mapping_exported", subject_id: mapping.id).count }.by(1)

      expect(response).to have_http_status(:ok), response.body
      expect(response.parsed_body.keys).to eq([ "mapping-collection" ])
      expect(response.parsed_body.dig("mapping-collection", "uuid")).to eq(mapping.uuid)
    end

    it "is the same as asking for format=oscal" do
      get path, headers: headers
      implicit = response.parsed_body

      get path, params: { format: "oscal" }, headers: headers

      expect(response.parsed_body).to eq(implicit)
    end

    it "is reachable by id as well as slug" do
      get "/api/v1/control_mappings/#{mapping.id}/export", headers: headers

      expect(response).to have_http_status(:ok)
    end
  end

  describe "provenance" do
    # Owner decision D2: collection-level provenance only, no confidence score
    # (follow-up #1196).
    it "carries the collection-level method, matching-rationale, status and description" do
      get path, headers: headers

      expect(response.parsed_body.dig("mapping-collection", "provenance")).to eq(
        "method" => "human", "matching-rationale" => "semantic",
        "status" => "complete", "mapping-description" => "A reviewed crosswalk."
      )
      map = response.parsed_body.dig("mapping-collection", "mappings", 0, "maps", 0)
      expect(map).to include("relationship" => "equivalent")
      expect(map.dig("sources", 0, "id-ref")).to eq("ac-2")
      expect(map).not_to have_key("confidence-score")
    end

    it "carries the FedRAMP source the KSI crosswalk records, from the real importer" do
      catalog = ControlCatalog.create!(name: "NIST SP 800-53 Rev 5.2.0 (test)", source: "OSCAL",
                                       version: "5.2.0", framework: "NIST SP 800-53")
      %w[ac-2 ac-2.2 ia-12].each do |id|
        family = catalog.control_families.find_or_create_by!(code: id.split("-").first.upcase) { |f| f.name = id }
        family.catalog_controls.create!(control_id: id, sort_id: id, title: id)
      end
      FedrampKsiImportService.new.call
      ksi = ControlMapping.find_by!(name: FedrampKsiImportService::MAPPING_NAME)

      get "/api/v1/control_mappings/#{ksi.slug}/export", headers: headers

      expect(response).to have_http_status(:ok), response.body
      provenance = response.parsed_body.dig("mapping-collection", "provenance")
      expect(provenance).to include("method" => "human", "matching-rationale" => "functional", "status" => "complete")
      expect(provenance["mapping-description"]).to include("FedRAMP/rules #{ksi.mapping_version}")
    end
  end

  describe "validate" do
    it "refuses a collection that does not conform, and names the way out" do
      allow_any_instance_of(OscalMappingExportService)
        .to receive(:export).and_raise(OscalValidationError, "maps: array size is less than: 1")

      get path, headers: headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to eq("The mapping collection does not conform to the OSCAL schema")
      expect(response.parsed_body["details"]).to eq([ "maps: array size is less than: 1" ])
      expect(response.parsed_body["hint"]).to match(/validate=false/)
    end

    it "refuses an empty collection for real — OSCAL requires at least one map" do
      empty = create(:control_mapping)

      get "/api/v1/control_mappings/#{empty.slug}/export", headers: headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["hint"]).to match(/validate=false/)
    end

    it "serves it anyway on validate=false" do
      empty = create(:control_mapping)

      get "/api/v1/control_mappings/#{empty.slug}/export", params: { validate: "false" }, headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to have_key("mapping-collection")
    end
  end

  describe "serialisations" do
    it "returns YAML" do
      get path, params: { format: "oscal-yaml" }, headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("application/x-yaml")
      expect(YAML.safe_load(response.body).keys).to eq([ "mapping-collection" ])
    end

    it "refuses XML by name, saying why, and lists what it does offer" do
      get path, params: { format: "oscal-xml" }, headers: headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["expected"]).to eq(%w[oscal oscal-yaml])
      expect(response.parsed_body["reason"]).to match(/no OSCAL XSD for the mapping model/)
    end

    it "refuses fields — a mapping has no field-JSON export" do
      get path, params: { format: "fields" }, headers: headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["expected"]).to eq(%w[oscal oscal-yaml])
      expect(response.parsed_body).not_to have_key("reason")
    end
  end

  describe "conditional GET" do
    it "answers 304 to a matching If-None-Match, without re-auditing" do
      get path, headers: headers
      etag = response.headers["ETag"]
      expect(etag).to be_present
      expect(etag).not_to start_with("W/")

      expect {
        get path, headers: headers.merge("If-None-Match" => etag)
      }.not_to change { AuditEvent.where(action: "control_mapping_exported").count }
      expect(response).to have_http_status(:not_modified)
    end

    it "answers 200 with a new ETag when an entry changes, even one that bypassed touch" do
      get path, headers: headers
      etag = response.headers["ETag"]

      # update_columns skips the entry's `touch: true`, so the mapping row is
      # unchanged: only the content digest in the ETag can notice this.
      expect { entry.update_columns(relationship: "intersects") }.not_to(change { mapping.reload.updated_at })
      get path, headers: headers.merge("If-None-Match" => etag)

      expect(response).to have_http_status(:ok)
      expect(response.headers["ETag"]).not_to eq(etag)
    end

    it "answers 200 for a different format" do
      get path, headers: headers
      etag = response.headers["ETag"]

      get path, params: { format: "oscal-yaml" }, headers: headers.merge("If-None-Match" => etag)

      expect(response).to have_http_status(:ok)
      expect(response.headers["ETag"]).not_to eq(etag)
    end
  end

  describe "who may read it" do
    it "serves any authenticated caller, as show does — no permission needed to read a crosswalk" do
      get path, headers: bearer_for(create(:user))

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to have_key("mapping-collection")
    end

    it "refuses an anonymous caller" do
      get path

      expect(response).to have_http_status(:unauthorized)
    end

    it "still refuses that same unprivileged caller a write" do
      patch "/api/v1/control_mappings/#{mapping.slug}", params: { control_mapping: { name: "x" } },
                                                        headers: bearer_for(create(:user)), as: :json

      expect(response).to have_http_status(:forbidden)
    end

    it "answers 404 for a mapping that does not exist" do
      get "/api/v1/control_mappings/no-such-mapping/export", headers: headers

      expect(response).to have_http_status(:not_found)
    end
  end
end
