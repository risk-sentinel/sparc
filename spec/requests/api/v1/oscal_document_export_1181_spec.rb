# frozen_string_literal: true

require "rails_helper"

# #1181 — `GET /api/v1/{ssp,sap,sar,poam}_documents/:id/export` serve the OSCAL
# document, not only SPARC's field JSON, through the same OscalApiExport body
# #1029 proved on cdef_documents. POA&M had no API export at all until now.
#
# #1154 part 3 — every export answers a conditional GET: a strong ETag, and 304
# for an If-None-Match that still matches. The ETag digests the exported bytes,
# because a document's updated_at does not move when its controls, fields or
# items do; the "child-only change" examples below are the guard on that.
#
# Every document here is boundary-scoped. The read gate is the controller's own
# `authorize_document_read!` and is proved in both directions per type.
RSpec.describe "Api::V1 OSCAL document export (#1181)", type: :request do
  let(:admin) { create(:user, :admin) }
  let(:admin_headers) { bearer_for(admin) }
  let(:boundary) { create(:authorization_boundary) }
  let(:other_boundary) { create(:authorization_boundary) }

  # A catalog carrying ac-2, so the validated path (#911 refuses a control that
  # resolves to no loaded catalog) can succeed for real rather than by stub.
  let!(:catalog_control) do
    catalog = create(:control_catalog)
    family  = create(:control_family, control_catalog: catalog, code: "AC")
    create(:catalog_control, control_family: family, control_id: "ac-2")
  end

  before { allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true) }

  def bearer_for(user)
    { "Authorization" => "Bearer #{ApiToken.generate!(user: user, name: SecureRandom.hex(4)).plaintext_token}" }
  end

  def reader_on(target_boundary, permission)
    create(:user).tap do |user|
      role = create(:role, :authorization_boundary_scoped, permissions: { permission => true })
      create(:user_role, user: user, role: role, authorization_boundary_id: target_boundary.id)
    end
  end

  # One row per document type (run with instance_exec, so FactoryBot is in
  # scope). `build` returns a document that passes the
  # VALIDATED export; `change_child` alters its exported content WITHOUT
  # touching the document row, which is the case an updated_at-only ETag gets
  # wrong.
  types = {
    "ssp_documents" => {
      service: "OscalSspExportService", root: "system-security-plan", xml_root: "system-security-plan",
      permission: "ssp.read", audit: "ssp_document_exported", fields_export: :export_ssp,
      build: lambda { |b|
        ssp = create(:ssp_document, :enriched, authorization_boundary: b)
        create(:ssp_control, ssp_document: ssp, control_id: "ac-2")
        ssp
      },
      change_child: ->(doc) { create(:ssp_control, ssp_document: doc, control_id: "ac-3") }
    },
    "sap_documents" => {
      service: "OscalAssessmentPlanExportService", root: "assessment-plan", xml_root: "assessment-plan",
      permission: "sap.read", audit: "sap_document_exported", fields_export: :export_sap,
      build: lambda { |b|
        sap = create(:sap_document, authorization_boundary: b)
        create(:sap_control, sap_document: sap, control_id: "ac-2")
        sap
      },
      change_child: ->(doc) { create(:sap_control, sap_document: doc, control_id: "ac-2", title: "Another").tap { doc.reload } }
    },
    "sar_documents" => {
      service: "OscalSarExportService", root: "assessment-results", xml_root: "assessment-results",
      permission: "sar.read", audit: "sar_document_exported", fields_export: :export_sar,
      build: ->(b) { create(:sar_document, authorization_boundary: b, assessment_end: Time.zone.parse("2026-01-31T00:00:00Z")) },
      change_child: ->(doc) { create(:sar_control, sar_document: doc, control_id: "ac-2") }
    },
    "poam_documents" => {
      service: "OscalPoamExportService", root: "plan-of-action-and-milestones", xml_root: "plan-of-action-and-milestones",
      permission: "poam.read", audit: "poam_document_exported", fields_export: :export_poam,
      build: lambda { |b|
        poam = create(:poam_document, authorization_boundary: b)
        create(:poam_item, poam_document: poam)
        poam
      },
      change_child: ->(doc) { create(:poam_item, poam_document: doc) }
    }
  }

  types.each do |resource, cfg|
    describe "/api/v1/#{resource}/:slug/export" do
      let(:document) { instance_exec(boundary, &cfg[:build]) }
      let(:path) { "/api/v1/#{resource}/#{document.slug}/export" }
      let(:service_class) { cfg[:service].constantize }

      describe "the default" do
        it "is SPARC's control-field JSON, unchanged, and the same as format=fields" do
          get path, headers: admin_headers

          expect(response).to have_http_status(:ok)
          expect(response.parsed_body).to eq(JSON.parse(JsonExportService.public_send(cfg[:fields_export], document)))
          expect(response.parsed_body).to have_key("document_name")
          expect(response.parsed_body).not_to have_key(cfg[:root])

          implicit = response.parsed_body
          get path, params: { format: "fields" }, headers: admin_headers
          expect(response.parsed_body).to eq(implicit)
        end
      end

      describe "format=oscal" do
        it "returns the validated OSCAL document and audits the export" do
          expect {
            get path, params: { format: "oscal" }, headers: admin_headers
          }.to change { AuditEvent.where(action: cfg[:audit], subject_id: document.id).count }.by(1)

          expect(response).to have_http_status(:ok), response.body
          expect(response.parsed_body.keys).to eq([ cfg[:root] ])
          expect(response.parsed_body.dig(cfg[:root], "uuid")).to eq(document.uuid)
          event = AuditEvent.where(action: cfg[:audit], subject_id: document.id).last
          expect(event.metadata).to include("format" => "oscal", "validated" => true)
        end

        it "validates by default, and refuses a document that does not conform — naming the way out" do
          allow_any_instance_of(service_class)
            .to receive(:export).and_raise(OscalValidationError, "line one\nline two")

          get path, params: { format: "oscal" }, headers: admin_headers

          expect(response).to have_http_status(:unprocessable_content)
          expect(response.parsed_body["error"]).to match(/does not conform to the OSCAL schema/)
          expect(response.parsed_body["details"]).to eq([ "line one", "line two" ])
          expect(response.parsed_body["hint"]).to match(/validate=false/)
        end

        it "skips validation on validate=false, so the document is still reachable" do
          allow_any_instance_of(service_class)
            .to receive(:export).and_raise(OscalValidationError, "must not be called")

          get path, params: { format: "oscal", validate: "false" }, headers: admin_headers

          expect(response).to have_http_status(:ok)
          expect(response.parsed_body).to have_key(cfg[:root])
          event = AuditEvent.where(action: cfg[:audit], subject_id: document.id).last
          expect(event.metadata).to include("validated" => false)
        end
      end

      describe "the other serialisations" do
        it "returns YAML" do
          get path, params: { format: "oscal-yaml" }, headers: admin_headers

          expect(response).to have_http_status(:ok)
          expect(response.media_type).to eq("application/x-yaml")
          expect(YAML.safe_load(response.body).keys).to eq([ cfg[:root] ])
        end

        it "returns OSCAL-namespaced XML" do
          get path, params: { format: "oscal-xml" }, headers: admin_headers

          expect(response).to have_http_status(:ok)
          root = Nokogiri::XML(response.body).root
          expect(root.name).to eq(cfg[:xml_root])
          expect(root.namespace.href).to eq("http://csrc.nist.gov/ns/oscal/1.0")
        end
      end

      describe "conditional GET" do
        it "answers 304 to a matching If-None-Match, and does not re-audit it" do
          get path, params: { format: "oscal" }, headers: admin_headers
          etag = response.headers["ETag"]
          expect(etag).to be_present
          expect(etag).not_to start_with("W/"), "the ETag must be strong"

          expect {
            get path, params: { format: "oscal" }, headers: admin_headers.merge("If-None-Match" => etag)
          }.not_to change { AuditEvent.where(action: cfg[:audit]).count }

          expect(response).to have_http_status(:not_modified)
          expect(response.body).to be_empty
        end

        it "answers 304 on the fields default too" do
          get path, headers: admin_headers
          get path, headers: admin_headers.merge("If-None-Match" => response.headers["ETag"])

          expect(response).to have_http_status(:not_modified)
        end

        it "answers 200 with a new ETag once the document changes" do
          get path, params: { format: "oscal" }, headers: admin_headers
          etag = response.headers["ETag"]

          document.touch(time: 1.minute.from_now)
          get path, params: { format: "oscal" }, headers: admin_headers.merge("If-None-Match" => etag)

          expect(response).to have_http_status(:ok)
          expect(response.headers["ETag"]).to be_present
          expect(response.headers["ETag"]).not_to eq(etag)
        end

        it "answers 200 with a new ETag when only a child record changed (updated_at did not move)" do
          get path, params: { format: "oscal", validate: "false" }, headers: admin_headers
          etag = response.headers["ETag"]
          before = document.reload.updated_at

          instance_exec(document, &cfg[:change_child])
          expect(document.reload.updated_at).to eq(before), "precondition: the document row itself is untouched"

          get path, params: { format: "oscal", validate: "false" }, headers: admin_headers.merge("If-None-Match" => etag)

          expect(response).to have_http_status(:ok),
            "a 304 here serves a stale document as current: the ETag must cover the content, not only updated_at"
          expect(response.headers["ETag"]).not_to eq(etag)
        end

        it "gives each format, and each validate setting, its own ETag" do
          etags = [ { format: "oscal" }, { format: "oscal-yaml" }, { format: "oscal-xml" },
                    { format: "oscal", validate: "false" }, {} ].map do |params|
            get path, params: params, headers: admin_headers
            response.headers["ETag"]
          end

          expect(etags.uniq.size).to eq(etags.size)

          get path, params: { format: "oscal-yaml" }, headers: admin_headers.merge("If-None-Match" => etags.first)
          expect(response).to have_http_status(:ok)
        end
      end

      describe "refusals" do
        it "names an unknown format and lists what it accepts" do
          get path, params: { format: "carrier_pigeon" }, headers: admin_headers

          expect(response).to have_http_status(:unprocessable_content)
          expect(response.parsed_body["error"]).to include("carrier_pigeon")
          expect(response.parsed_body["expected"]).to eq(%w[fields oscal oscal-yaml oscal-xml])
        end

        it "refuses an anonymous caller" do
          get path, params: { format: "oscal" }

          expect(response).to have_http_status(:unauthorized)
        end
      end

      describe "boundary-scoped read" do
        it "serves a caller holding #{cfg[:permission]} on the document's boundary" do
          get path, params: { format: "oscal" }, headers: bearer_for(reader_on(boundary, cfg[:permission]))

          expect(response).to have_http_status(:ok)
          expect(response.parsed_body).to have_key(cfg[:root])
        end

        it "refuses a caller whose #{cfg[:permission]} is on a different boundary" do
          get path, params: { format: "oscal" }, headers: bearer_for(reader_on(other_boundary, cfg[:permission]))

          expect(response).to have_http_status(:forbidden)
          expect(response.body).not_to include(cfg[:root])
        end

        it "refuses the default fields export to that caller too" do
          get path, headers: bearer_for(reader_on(other_boundary, cfg[:permission]))

          expect(response).to have_http_status(:forbidden)
        end
      end
    end
  end

  # CDEF moved onto the shared body with no behaviour change —
  # spec/requests/api/v1/cdef_export_formats_spec.rb is the regression guard and
  # is untouched. Conditional GET is the one additive change, pinned here.
  describe "/api/v1/cdef_documents/:slug/export conditional GET" do
    let(:cdef) { create(:cdef_document) }
    let(:path) { "/api/v1/cdef_documents/#{cdef.slug}/export" }

    it "answers 304 to a matching If-None-Match" do
      get path, params: { format: "oscal" }, headers: admin_headers
      etag = response.headers["ETag"]

      get path, params: { format: "oscal" }, headers: admin_headers.merge("If-None-Match" => etag)

      expect(response).to have_http_status(:not_modified)
    end

    it "answers 200 with a new ETag once the document changes" do
      get path, params: { format: "oscal" }, headers: admin_headers
      etag = response.headers["ETag"]

      cdef.touch(time: 1.minute.from_now)
      get path, params: { format: "oscal" }, headers: admin_headers.merge("If-None-Match" => etag)

      expect(response).to have_http_status(:ok)
      expect(response.headers["ETag"]).not_to eq(etag)
    end
  end
end
