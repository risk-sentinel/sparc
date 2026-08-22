# frozen_string_literal: true

require "rails_helper"

# #1031 — file ingest over the API for the four document types that had none.
#
# Six web controllers ingest a document from a file; only SSP and SAR had an API
# counterpart. CDEF, POA&M, SAP and Profile could be created empty over the API
# and populated only in a browser — and for CDEF that is the primary way
# documents enter SPARC, since a component definition is normally authored
# elsewhere.
#
# The checks that matter are not the 201. An ingest that skipped its security
# validation, or that created the record and never enqueued the parse, returns
# exactly the same status as one that worked.
RSpec.describe "Api::V1 document file import", type: :request do
  let(:admin) { create(:user, :admin) }
  let(:headers) do
    { "Authorization" => "Bearer #{ApiToken.generate!(user: admin, name: 'T').plaintext_token}" }
  end

  before { allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true) }

  def upload(path, type: "application/json")
    Rack::Test::UploadedFile.new(Rails.root.join(path), type)
  end

  # A local, not a constant: a constant assigned inside a `describe` block is
  # defined at TOP LEVEL in Ruby, so `TYPES` would become `::TYPES` and leak
  # into every other spec in the suite.
  types = {
    "cdef_documents" => {
      model: CdefDocument, type_key: "cdef",
      fixture: "spec/fixtures/files/components/example-component-definition.json"
    },
    "sap_documents" => {
      model: SapDocument, type_key: "sap", param_key: "sap_document", boundary: true,
      fixture: "spec/fixtures/files/sap/ifa_assessment-plan.json"
    },
    "poam_documents" => {
      model: PoamDocument, type_key: "poam", param_key: "poam_document", boundary: true,
      fixture: "spec/fixtures/files/poam/ifa_plan-of-action-and-milestones.json"
    },
    "profile_documents" => {
      model: ProfileDocument, type_key: "profile",
      fixture: "spec/fixtures/files/profiles/basic-profile.yaml"
    }
  }.freeze

  types.each do |resource, cfg|
    describe "POST /api/v1/#{resource}/import" do
      let(:model)    { cfg[:model] }
      let(:type_key) { cfg[:type_key] }
      let(:file)     { upload(cfg[:fixture], type: cfg[:fixture].end_with?(".yaml") ? "application/x-yaml" : "application/json") }
      let(:boundary) { create(:authorization_boundary) }

      # SAP and POA&M are boundary-scoped and will not save without one. The id
      # goes under the DOCUMENT param key, which is where
      # `authorize_document_write!` looks for it — see the note in
      # DocumentFileIngestApi#requested_ingest_boundary_id.
      def scoping(cfg, boundary)
        return {} unless cfg[:boundary]

        { cfg[:param_key] => { authorization_boundary_id: boundary.id } }
      end

      it "creates a document from the uploaded file" do
        expect {
          post "/api/v1/#{resource}/import",
               params: { file: file }.merge(scoping(cfg, boundary)), headers: headers
        }.to change(model, :count).by(1)

        expect(response).to have_http_status(:created)
        expect(response.parsed_body["meta"]).to include("created" => 1, "rejected" => 0)
      end

      it "attaches the file, so the parser has bytes to read" do
        post "/api/v1/#{resource}/import",
             params: { file: file }.merge(scoping(cfg, boundary)), headers: headers

        document = model.find(response.parsed_body["data"].first["id"])
        expect(document.file).to be_attached
        expect(document.original_filename).to eq(File.basename(cfg[:fixture]))
      end

      it "enqueues the conversion job — without it the document sits in pending forever" do
        expect {
          post "/api/v1/#{resource}/import",
               params: { file: file }.merge(scoping(cfg, boundary)), headers: headers
        }.to have_enqueued_job(DocumentConversionJob).with(type_key, anything)
      end

      it "reports the document as pending, so a caller knows to poll" do
        post "/api/v1/#{resource}/import",
             params: { file: file }.merge(scoping(cfg, boundary)), headers: headers

        expect(response.parsed_body["data"].first["status"]).to eq("pending")
      end

      # #982 — an action missing from AuditEvent::ACTIONS records NOTHING and
      # raises nothing, so "the mutation is audited" has to be asserted against
      # the table rather than assumed from the call site existing.
      it "records an audit event naming the ingest" do
        expect {
          post "/api/v1/#{resource}/import",
               params: { file: file }.merge(scoping(cfg, boundary)), headers: headers
        }.to change { AuditEvent.where(action: "#{cfg[:type_key]}_document_created").count }.by(1)

        expect(AuditEvent.where(action: "#{cfg[:type_key]}_document_created").last.metadata["via"])
          .to eq("api_import")
      end

      it "refuses a request with no file, by name" do
        post "/api/v1/#{resource}/import", headers: headers

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body["error"]).to match(/file/i)
      end

      it "refuses an anonymous caller" do
        post "/api/v1/#{resource}/import", params: { file: file }

        expect(response).to have_http_status(:unauthorized)
      end

      # SI-10 — the validators are the reason this is a second caller of the web
      # path rather than a second implementation. A skipped validator returns
      # the same 201 as one that ran, so each is asserted directly.
      it "rejects an executable disguised by its extension" do
        elf = Tempfile.new([ "payload", ".json" ])
        elf.binmode
        elf.write("\x7FELF\x02\x01\x01".b + ("\x00".b * 64))
        elf.rewind

        expect {
          post "/api/v1/#{resource}/import",
               params: { file: Rack::Test::UploadedFile.new(elf.path, "application/json") },
               headers: headers
        }.not_to change(model, :count)

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body["meta"]["errors"].first["error"]).to match(/executable/i)
      end

      it "rejects an unsupported extension, naming what is accepted" do
        txt = Tempfile.new([ "notes", ".txt" ])
        txt.write("plain text")
        txt.rewind

        post "/api/v1/#{resource}/import",
             params: { file: Rack::Test::UploadedFile.new(txt.path, "text/plain") },
             headers: headers

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body["meta"]["errors"].first["error"]).to match(/accepted/i)
      end

      it "rejects a file whose contents are not the structure its extension claims" do
        broken = Tempfile.new([ "broken", ".json" ])
        broken.write("{ this is not json")
        broken.rewind

        expect {
          post "/api/v1/#{resource}/import",
               params: { file: Rack::Test::UploadedFile.new(broken.path, "application/json") },
               headers: headers
        }.not_to change(model, :count)

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe "several files in one request" do
    let(:boundary) { create(:authorization_boundary) }

    it "creates one document per file" do
      files = [
        upload("spec/fixtures/files/sap/ifa_assessment-plan.json"),
        upload("spec/fixtures/files/sap/ifa_assessment-plan-example.json")
      ]

      expect {
        post "/api/v1/sap_documents/import",
             params: { files: files, sap_document: { authorization_boundary_id: boundary.id } },
             headers: headers
      }.to change(SapDocument, :count).by(2)

      expect(response).to have_http_status(:created)
      expect(response.parsed_body["meta"]["created"]).to eq(2)
    end

    it "reports partial success distinctly from total success" do
      bad = Tempfile.new([ "bad", ".txt" ])
      bad.write("nope")
      bad.rewind

      post "/api/v1/sap_documents/import",
           params: { files: [
             upload("spec/fixtures/files/sap/ifa_assessment-plan.json"),
             Rack::Test::UploadedFile.new(bad.path, "text/plain")
           ], sap_document: { authorization_boundary_id: boundary.id } },
           headers: headers

      expect(response).to have_http_status(:multi_status)
      body = response.parsed_body
      expect(body["meta"]).to include("created" => 1, "rejected" => 1)
      expect(body["meta"]["errors"].first["filename"]).to end_with(".txt")
    end
  end

  describe "authorization" do
    let(:non_admin) { create(:user) }
    let(:reader_headers) do
      { "Authorization" => "Bearer #{ApiToken.generate!(user: non_admin, name: 'R').plaintext_token}" }
    end

    # #1031 — CDEF ingest is gated on `cdef.write`, matching the WEB create it
    # mirrors. The allow leg alone would pass against an action with no guard.
    it "refuses a CDEF ingest from a user without cdef.write" do
      expect {
        post "/api/v1/cdef_documents/import",
             params: { file: upload("spec/fixtures/files/components/example-component-definition.json") },
             headers: reader_headers
      }.not_to change(CdefDocument, :count)

      expect(response).to have_http_status(:forbidden)
    end

    # #1031 — the boundary is read only from the document param key, because
    # that is where `authorize_document_write!` looks for it. Were it also
    # accepted at the top level, the guard would see no requested boundary,
    # check instance-level permission, and let the document be created inside a
    # boundary the caller holds no grant on.
    it "refuses an ingest into a boundary the caller has no write grant on" do
      boundary = create(:authorization_boundary)

      expect {
        post "/api/v1/sap_documents/import",
             params: {
               file: upload("spec/fixtures/files/sap/ifa_assessment-plan.json"),
               sap_document: { authorization_boundary_id: boundary.id }
             },
             headers: reader_headers
      }.not_to change(SapDocument, :count)

      expect(response).to have_http_status(:forbidden)
    end

    it "does not honour a boundary passed at the top level, where no guard reads it" do
      boundary = create(:authorization_boundary)

      post "/api/v1/sap_documents/import",
           params: {
             file: upload("spec/fixtures/files/sap/ifa_assessment-plan.json"),
             authorization_boundary_id: boundary.id
           },
           headers: headers

      # Admin, so authorization is not what stops this — the document simply
      # never receives the boundary, and SAP will not save without one.
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["meta"]["errors"].first["error"]).to match(/boundary/i)
    end

    it "refuses a Profile ingest from a user without profiles.write" do
      post "/api/v1/profile_documents/import",
           params: { file: upload("spec/fixtures/files/profiles/basic-profile.yaml", type: "application/x-yaml") },
           headers: reader_headers

      expect(response).to have_http_status(:forbidden)
    end
  end
end
