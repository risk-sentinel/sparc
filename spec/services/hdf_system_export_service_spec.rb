# frozen_string_literal: true

require "rails_helper"

# #1179 — the boundary as an HDF hdf-system document.
RSpec.describe HdfSystemExportService do
  let(:boundary) do
    create(:authorization_boundary, name: "Portal Production", description: "Citizen portal",
           authorization_boundary_description: "All resources in the prod VPC")
  end
  let(:environment) { create(:boundary, authorization_boundary: boundary) }

  # The CLI leg is exercised separately below; everything else asserts the
  # document and the in-process schema check, which run everywhere.
  let(:service) { described_class.new(boundary, cli: false) }

  def link_cdef(**attrs)
    cdef = create(:cdef_document, **attrs)
    create(:boundary_cdef_document, boundary: environment, cdef_document: cdef)
    cdef
  end

  def index_component(cdef, uuid:, title:, type:, has_checks: false, description: nil)
    CdefComponent.create!(cdef_document: cdef, component_uuid: uuid, title: title,
                          component_type: type, has_checks: has_checks, description: description)
  end

  def ssp_control(ssp, control_id, row_order:, **fields)
    control = create(:ssp_control, ssp_document: ssp, control_id: control_id, row_order: row_order)
    fields.each do |name, value|
      create(:ssp_control_field, ssp_control: control, field_name: name.to_s, field_value: value)
    end
    control
  end

  describe "#export" do
    let!(:cdef) { link_cdef(name: "Web tier", component_type: "software", component_title: "Portal web tier") }

    it "emits a document that passes the vendored hdf-system v3.7.0 schema" do
      doc = service.export

      expect(Hdf::SystemSchema.errors(doc)).to eq([])
    end

    it "identifies the system by the boundary uuid, under the RFC 4122 scheme (D4)" do
      doc = service.export

      expect(doc["systemId"]).to eq(boundary.uuid)
      expect(doc["identifier"]).to eq(boundary.uuid)
      expect(doc["identifierScheme"]).to eq("urn:ietf:rfc:4122")
      expect(doc["labels"]).to eq("system_id" => boundary.uuid)
    end

    it "maps name, description and boundaryDescription from the boundary" do
      doc = service.export

      expect(doc["name"]).to eq("Portal Production")
      expect(doc["description"]).to eq("Citizen portal")
      expect(doc["boundaryDescription"]).to eq("All resources in the prod VPC")
    end

    it "omits description and boundaryDescription when the boundary has none" do
      boundary.update!(description: nil, authorization_boundary_description: "")
      doc = service.export

      expect(doc).not_to have_key("description")
      expect(doc).not_to have_key("boundaryDescription")
    end

    it "names SPARC and its version as the generator" do
      expect(service.export["generator"]).to eq("name" => "sparc", "version" => SparcConfig.version)
    end

    it "omits dataFlows — SPARC does not model them" do
      expect(service.export).not_to have_key("dataFlows")
    end

    it "is deterministic: the same state exports byte-identically" do
      a = JSON.generate(service.export)
      b = JSON.generate(described_class.new(boundary.reload, cli: false).export)

      expect(a).to eq(b)
    end

    describe "authorizationStatus (D3)" do
      {
        "authorized"   => "authorized",
        "deauthorized" => "revoked",
        "draft"        => "notYetRequested",
        "active"       => "pendingAuthorization"
      }.each do |sparc, hdf|
        it "maps #{sparc} to #{hdf}" do
          boundary.update_column(:status, sparc)
          expect(service.export["authorizationStatus"]).to eq(hdf)
        end
      end

      it "covers every SPARC status" do
        expect(described_class::AUTHORIZATION_STATUS.keys).to match_array(AuthorizationBoundary::STATUSES)
      end
    end

    describe "authorizationDate" do
      it "is omitted when the boundary records none" do
        expect(service.export).not_to have_key("authorizationDate")
      end

      it "exports an ISO 8601 date as a UTC date-time" do
        boundary.update!(authorization_date: "2025-06-15")
        expect(service.export["authorizationDate"]).to eq("2025-06-15T00:00:00Z")
      end

      it "normalizes an ISO 8601 date-time to UTC" do
        boundary.update!(authorization_date: "2025-06-15T09:30:00-04:00")
        expect(service.export["authorizationDate"]).to eq("2025-06-15T13:30:00Z")
      end

      # Date.parse would accept "May"; a date nobody chose must not be exported.
      it "is omitted, not guessed, when the value is not ISO 8601" do
        boundary.update!(authorization_date: "sometime in May")
        doc = service.export

        expect(doc).not_to have_key("authorizationDate")
        expect(Hdf::SystemSchema.errors(doc)).to eq([])
      end
    end

    describe "categorizationLevel" do
      it "is the FIPS 199 high-water mark without the storage prefix" do
        boundary.update!(security_objective_confidentiality: "fips-199-low",
                         security_objective_integrity: "fips-199-high")
        expect(service.export["categorizationLevel"]).to eq("high")
      end

      it "is omitted when the boundary is uncategorized" do
        expect(service.export).not_to have_key("categorizationLevel")
      end
    end

    describe "owner" do
      it "is the system owner's email from the roster" do
        create(:authorization_boundary_membership, authorization_boundary: boundary,
               role: "system_owner", user_email: "so@example.gov")
        create(:authorization_boundary_membership, authorization_boundary: boundary,
               role: "isso", user_email: "isso@example.gov")

        expect(service.export["owner"]).to eq("identifier" => "so@example.gov", "type" => "email")
      end

      it "reads an admin-assigned system_owner role when there is no legacy membership" do
        role = create(:role, :authorization_boundary_scoped, name: "system_owner")
        user = create(:user, email: "assigned-so@example.gov")
        create(:user_role, user: user, role: role, authorization_boundary: boundary)

        expect(service.export["owner"]).to eq("identifier" => "assigned-so@example.gov", "type" => "email")
      end

      it "falls back to the organization when no system owner has an email" do
        org = create(:organization, name: "Agency X")
        boundary.update!(organization: org)
        create(:authorization_boundary_membership, authorization_boundary: boundary,
               role: "system_owner", user_email: nil)

        expect(service.export["owner"]).to eq(
          "identifier" => org.uuid, "type" => "other", "description" => "SPARC organization: Agency X"
        )
      end

      it "is omitted when there is neither" do
        expect(service.export).not_to have_key("owner")
      end
    end
  end

  describe "components" do
    it "lists a CDEF with no component index as its one document-level component" do
      cdef = link_cdef(name: "Web tier", component_type: "software",
                       component_title: "Portal web tier", component_description: "Rails app")

      expect(service.export["components"]).to eq([
        { "type" => "application", "name" => "Portal web tier",
          "componentId" => OscalUuidService.derived(cdef.uuid, "cdef-component"),
          "description" => "Rails app" }
      ])
    end

    # Same identity as the OSCAL CDEF export gives the same component.
    it "uses the component uuid the OSCAL CDEF export uses" do
      cdef = link_cdef(name: "Web tier", component_type: "software")
      oscal = OscalComponentDefinitionExportService.new(cdef).send(:build_component)

      expect(service.export["components"].first["componentId"]).to eq(oscal["uuid"])
    end

    it "lists indexed components by their upstream uuids" do
      cdef = link_cdef(name: "Amazon S3")
      index_component(cdef, uuid: "11111111-2222-4333-8444-555555555555", title: "Amazon S3", type: "service",
                      has_checks: true, description: "Object storage")

      expect(service.export["components"]).to eq([
        { "type" => "application", "name" => "Amazon S3",
          "componentId" => "11111111-2222-4333-8444-555555555555", "description" => "Object storage" }
      ])
    end

    it "derives a stable uuid for an indexed component whose upstream id is not one" do
      cdef = link_cdef(name: "Odd")
      index_component(cdef, uuid: "not-a-uuid-dupe", title: "Odd", type: "software")

      id = service.export["components"].first["componentId"]
      expect(id).to eq(OscalUuidService.derived(cdef.uuid, "cdef-component-not-a-uuid-dupe"))
    end

    {
      "software" => "application", "service" => "application", "hardware" => "host", "" => "application"
    }.each do |oscal, hdf|
      it "maps OSCAL #{oscal.presence || '(blank)'} to HDF #{hdf}" do
        link_cdef(name: "C", component_type: oscal.presence)
        expect(service.export["components"].first["type"]).to eq(hdf)
      end
    end

    it "excludes non-technical and interconnection components rather than mislabelling them" do
      link_cdef(name: "App", component_type: "software")
      %w[policy process-procedure plan guidance standard validation physical interconnection].each do |t|
        link_cdef(name: "Doc #{t}", component_type: t)
      end
      doc = service.export

      expect(doc["components"].map { |c| c["name"] }).to eq([ "App" ])
      expect(service.excluded_components.map { |c| c[:oscal_type] })
        .to match_array(%w[policy process-procedure plan guidance standard validation physical interconnection])
    end

    it "excludes an automated-check component (an AWS Config Rule), keeping the service" do
      cdef = link_cdef(name: "Amazon S3")
      index_component(cdef, uuid: "11111111-2222-4333-8444-555555555555", title: "Amazon S3",
                      type: "service", has_checks: true)
      index_component(cdef, uuid: "66666666-7777-4888-8999-000000000000", title: "s3-bucket-versioning",
                      type: "software", has_checks: true)

      expect(service.export["components"].map { |c| c["name"] }).to eq([ "Amazon S3" ])
    end

    it "lists a CDEF linked to two environments once" do
      cdef = link_cdef(name: "Shared", component_type: "software")
      other_env = create(:boundary, authorization_boundary: boundary, environment: "development")
      create(:boundary_cdef_document, boundary: other_env, cdef_document: cdef)

      expect(service.export["components"].size).to eq(1)
    end

    describe "a boundary with no exportable component" do
      it "refuses, naming the gap, when nothing is linked" do
        expect { service.export }
          .to raise_error(described_class::Unexportable, /has no components.*link a component definition/i)
      end

      it "refuses, naming the types found, when every linked component is excluded" do
        link_cdef(name: "Policy", component_type: "policy")

        expect { service.export }
          .to raise_error(described_class::Unexportable, /none is a technical component.*types found: policy/)
      end
    end
  end

  describe "controlDesignations" do
    let!(:cdef) { link_cdef(name: "App", component_type: "software") }
    let!(:ssp) { create(:ssp_document, authorization_boundary: boundary) }

    it "maps the SSP origination and uses the implementation statement as the description" do
      ssp_control(ssp, "AC-2", row_order: 1, control_type: "System Specific",
                  implementation_statement: "Accounts are managed in the IdP.")
      ssp_control(ssp, "AC-2(1)", row_order: 2, control_type: "Hybrid — partially inherited",
                  implementation_summary: "Automated account management, shared.")
      ssp_control(ssp, "PE-3", row_order: 3, control_type: "Inherited from provider",
                  implementation_statement: "Provided by the CSP data centre.")

      expect(service.export["controlDesignations"]).to eq([
        { "controlId" => "AC-2", "designation" => "system-specific",
          "description" => "Accounts are managed in the IdP." },
        { "controlId" => "AC-2 (1)", "designation" => "hybrid",
          "description" => "Automated account management, shared." },
        { "controlId" => "PE-3", "designation" => "common",
          "description" => "Provided by the CSP data centre." }
      ])
    end

    it "prefers the implementation statement over the summary" do
      ssp_control(ssp, "AC-3", row_order: 1, control_type: "System Specific",
                  implementation_statement: "Statement.", implementation_summary: "Summary.")

      expect(service.export["controlDesignations"].first["description"]).to eq("Statement.")
    end

    it "states plainly when the control has no narrative, rather than dropping or inventing one" do
      ssp_control(ssp, "AC-4", row_order: 1, control_type: "Inherited from provider")

      expect(service.export["controlDesignations"].first["description"]).to eq(
        "Designation recorded in the SPARC SSP as \"Inherited from provider\". " \
        "No implementation statement has been written for this control."
      )
    end

    it "drops Not Applicable and controls with no origination" do
      ssp_control(ssp, "AC-5", row_order: 1, control_type: "Not Applicable", implementation_statement: "n/a")
      ssp_control(ssp, "AC-6", row_order: 2, implementation_statement: "no origination recorded")

      expect(service.export).not_to have_key("controlDesignations")
    end

    it "is omitted when the boundary has no SSP" do
      ssp.update!(authorization_boundary: create(:authorization_boundary))
      expect(service.export).not_to have_key("controlDesignations")
    end

    it "passes the schema with designations present" do
      ssp_control(ssp, "SC-7", row_order: 1, control_type: "System Specific")
      expect(Hdf::SystemSchema.errors(service.export)).to eq([])
    end
  end

  # The in-process gate is not a formality: a document that fails it is never
  # returned. Proven by corrupting a real document on its way out.
  describe "schema gate" do
    before { link_cdef(name: "App", component_type: "software") }

    it "raises InvalidDocument instead of returning a non-conformant document" do
      allow(service).to receive(:build).and_wrap_original do |original|
        original.call.merge("authorizationStatus" => "active")
      end

      expect { service.export }.to raise_error(described_class::InvalidDocument) { |e|
        expect(e.errors).to include(a_string_starting_with("/authorizationStatus:"))
      }
    end
  end

  describe "CLI validation" do
    before { link_cdef(name: "App", component_type: "software") }

    it "hands the document to `hdf validate --type system` as readable content" do
      runner = instance_double(HdfRunner)
      received = nil
      expect(runner).to receive(:validate) { |io, type:| received = [ io, type ] }.and_return(true)

      doc = described_class.new(boundary, runner: runner, cli: true).export

      expect(received[1]).to eq("system")
      expect(received[0]).to respond_to(:read)
      expect(JSON.parse(received[0].read)).to eq(doc)
    end

    it "does not call the CLI when it is unavailable" do
      runner = instance_double(HdfRunner)
      expect(runner).not_to receive(:validate)

      described_class.new(boundary, runner: runner, cli: false).export
    end

    it "propagates a CLI refusal" do
      runner = instance_double(HdfRunner)
      allow(runner).to receive(:validate).and_raise(
        HdfRunner::Error.new("invalid", command: "hdf validate", exit_code: 1, stderr: "bad")
      )

      expect { described_class.new(boundary, runner: runner, cli: true).export }.to raise_error(HdfRunner::Error)
    end
  end

  # The authority downstream consumers run. Skipped, visibly, where no hdf
  # binary exists (the CI test runner — #835); the shipped image and a
  # provisioned workstation run these.
  describe "with the real hdf binary" do
    before do
      skip "hdf-cli not on PATH (see #835); run in the image or after script/dev/install-hdf.sh" \
        unless described_class.cli_available?
    end

    let(:runner) { HdfRunner.new }

    def cli_validate(doc)
      runner.validate(StringIO.new(JSON.generate(doc)), type: "system")
    end

    it "passes `hdf validate --type system` for a fully populated boundary" do
      org = create(:organization)
      boundary.update!(organization: org, security_objective_availability: "fips-199-moderate",
                       authorization_date: "2025-06-15")
      boundary.update_column(:status, "authorized")
      cdef = link_cdef(name: "S3")
      index_component(cdef, uuid: "11111111-2222-4333-8444-555555555555", title: "Amazon S3", type: "service")
      link_cdef(name: "Hosts", component_type: "hardware")
      ssp = create(:ssp_document, authorization_boundary: boundary)
      ssp_control(ssp, "AC-2(1)", row_order: 1, control_type: "Hybrid — partially inherited")

      doc = described_class.new(boundary, runner: runner, cli: true).export
      expect(doc.keys).to include("owner", "authorizationDate", "categorizationLevel", "controlDesignations")
      expect(cli_validate(doc)).to be true
    end

    # Refusal legs, so the pass above is the CLI talking. Each is a rule the
    # CLI was MEASURED to enforce on 3.7.0.
    {
      "zero components" => ->(d) { d.merge("components" => []) },
      "an authorizationStatus outside the enum" => ->(d) { d.merge("authorizationStatus" => "active") },
      "a componentId that is not a uuid" => ->(d) { d.merge("components" => [ d["components"].first.merge("componentId" => "zzz") ]) }
    }.each do |what, mutate|
      it "is refused by `hdf validate --type system` for #{what}" do
        link_cdef(name: "App", component_type: "software")
        doc = mutate.call(described_class.new(boundary, cli: false).export)

        expect { cli_validate(doc) }.to raise_error(HdfRunner::Error)
      end
    end

    # Pinned divergence, measured on 3.7.0: the CLI does NOT enforce the
    # schema's top-level `unevaluatedProperties: false`. This is why the
    # in-process check exists as more than a CI stand-in. If upstream starts
    # enforcing it, this fails and the comment in Hdf::SystemSchema is stale.
    it "does not refuse an undefined top-level key — which the in-process check does" do
      link_cdef(name: "App", component_type: "software")
      doc = described_class.new(boundary, cli: false).export.merge("bogusTopLevel" => 1)

      expect(cli_validate(doc)).to be true
      expect(Hdf::SystemSchema.errors(doc)).to include(a_string_starting_with("/bogusTopLevel:"))
    end
  end
end
