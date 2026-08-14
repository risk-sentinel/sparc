# frozen_string_literal: true

require "rails_helper"

RSpec.describe SspFromProfileService do
  let(:resolved_catalog_json) do
    {
      "catalog" => {
        "uuid" => SecureRandom.uuid,
        "metadata" => {
          "title" => "Test Resolved Catalog",
          "version" => "1.0.0",
          "oscal-version" => "1.1.2",
          "last-modified" => Time.current.iso8601
        },
        "groups" => [
          {
            "id" => "ac",
            "class" => "family",
            "title" => "Access Control",
            "controls" => [
              {
                "id" => "ac-1",
                "class" => "SP800-53",
                "title" => "Policy and Procedures",
                "props" => [
                  { "name" => "label", "value" => "AC-1" },
                  { "name" => "priority", "value" => "P1" }
                ],
                "parts" => [
                  { "id" => "ac-1_smt", "name" => "statement", "prose" => "Develop and document access control policy." },
                  { "id" => "ac-1_gdn", "name" => "guidance", "prose" => "Access control policy can be included in the general security policy." }
                ]
              },
              {
                "id" => "ac-2",
                "class" => "SP800-53",
                "title" => "Account Management",
                "props" => [
                  { "name" => "label", "value" => "AC-2" },
                  { "name" => "priority", "value" => "P2" }
                ],
                "parts" => [
                  { "id" => "ac-2_smt", "name" => "statement", "prose" => "Define and document account types." }
                ]
              }
            ]
          },
          {
            "id" => "sc",
            "class" => "family",
            "title" => "System and Communications Protection",
            "controls" => [
              {
                "id" => "sc-1",
                "class" => "SP800-53",
                "title" => "Policy and Procedures",
                "props" => [
                  { "name" => "label", "value" => "SC-1" },
                  { "name" => "priority", "value" => "P3" }
                ],
                "parts" => [
                  { "id" => "sc-1_smt", "name" => "statement", "prose" => "Develop and document system protection policy." }
                ]
              }
            ]
          }
        ]
      }
    }
  end

  let(:profile) do
    create(:profile_document,
      lifecycle_status: "published",
      resolved_catalog_json: resolved_catalog_json,
      published: Time.current.iso8601)
  end

  describe "#create" do
    it "creates an SspDocument with correct attributes" do
      ssp = described_class.new(profile, name: "Test SSP").create

      expect(ssp).to be_persisted
      expect(ssp.name).to eq("Test SSP")
      expect(ssp.creation_method).to eq("profile")
      expect(ssp.file_type).to eq("json")
      expect(ssp.status).to eq("completed")
      expect(ssp.lifecycle_status).to eq("started")
      expect(ssp.oscal_version).to eq("1.1.2")
    end

    it "uses default name when none provided" do
      ssp = described_class.new(profile).create

      expect(ssp.name).to eq("SSP from #{profile.name}")
    end

    it "sets profile_document_id to the source profile" do
      ssp = described_class.new(profile).create

      expect(ssp.profile_document_id).to eq(profile.id)
    end

    it "creates the correct number of SspControls" do
      ssp = described_class.new(profile).create

      expect(ssp.ssp_controls.count).to eq(3)
    end

    it "creates controls with correct control_ids and titles" do
      ssp = described_class.new(profile).create

      ac1 = ssp.ssp_controls.find_by(control_id: "ac-1")
      expect(ac1).to be_present
      expect(ac1.title).to eq("Policy and Procedures")

      sc1 = ssp.ssp_controls.find_by(control_id: "sc-1")
      expect(sc1).to be_present
    end

    it "extracts stated_requirement from statement prose" do
      ssp = described_class.new(profile).create

      ac1 = ssp.ssp_controls.find_by(control_id: "ac-1")
      field = ac1.ssp_control_fields.find_by(field_name: "stated_requirement")
      expect(field.field_value).to eq("Develop and document access control policy.")
    end

    it "extracts description from guidance prose" do
      ssp = described_class.new(profile).create

      ac1 = ssp.ssp_controls.find_by(control_id: "ac-1")
      field = ac1.ssp_control_fields.find_by(field_name: "description")
      expect(field.field_value).to include("general security policy")
    end

    it "creates editable placeholder fields with default status Deferred" do
      ssp = described_class.new(profile).create

      ac1 = ssp.ssp_controls.find_by(control_id: "ac-1")
      status = ac1.ssp_control_fields.find_by(field_name: "status")
      expect(status.field_value).to eq("Deferred")
    end

    it "creates empty editable placeholder fields for implementation" do
      ssp = described_class.new(profile).create

      ac1 = ssp.ssp_controls.find_by(control_id: "ac-1")
      %w[control_type responsible_entities implementation_statement implementation_summary notes].each do |field_name|
        field = ac1.ssp_control_fields.find_by(field_name: field_name)
        expect(field).to be_present, "Expected field '#{field_name}' to exist"
        expect(field.field_value).to eq("")
      end
    end

    it "creates a this-system SspComponent" do
      ssp = described_class.new(profile).create

      component = ssp.ssp_components.find_by(component_type: "this-system")
      expect(component).to be_present
      expect(component.uuid).to be_present
      expect(component.status_state).to eq("under-development")
    end

    it "creates a default SspInformationType" do
      ssp = described_class.new(profile).create

      expect(ssp.ssp_information_types.count).to eq(1)
      info_type = ssp.ssp_information_types.first
      expect(info_type.title).to eq("General Information")
      expect(info_type.uuid).to be_present
    end

    it "creates a default SspUser" do
      ssp = described_class.new(profile).create

      expect(ssp.ssp_users.count).to eq(1)
      user = ssp.ssp_users.first
      expect(user.title).to eq("System Administrator")
      expect(user.uuid).to be_present
    end

    it "creates SspByComponent records linking controls to this-system" do
      ssp = described_class.new(profile).create

      by_components = SspByComponent.joins(:ssp_control)
                                    .where(ssp_controls: { ssp_document_id: ssp.id })
      expect(by_components.count).to eq(3)
      expect(by_components.pluck(:implementation_status).uniq).to eq([ "planned" ])
    end

    it "stores import_metadata with source profile info" do
      ssp = described_class.new(profile).create

      expect(ssp.import_metadata["source_type"]).to eq("profile")
      expect(ssp.import_metadata["source_profile_id"]).to eq(profile.id)
      expect(ssp.import_metadata["source_profile_uuid"]).to eq(profile.uuid)
      expect(ssp.import_metadata["source_profile_name"]).to eq(profile.name)
      expect(ssp.import_metadata["format"]).to eq("resolved_catalog")
    end

    # #955 — an SSP generated from a profile carried no statements at all, so
    # nothing on it could be marked `provided` and a leveraged authorization
    # resolved zero links however it was configured.
    describe "control statements (#955)" do
      def statements_for(ssp)
        SspControlStatement.joins(:ssp_control).where(ssp_controls: { ssp_document_id: ssp.id })
      end

      it "creates a statement for each control that has a catalog statement" do
        ssp = described_class.new(profile).create

        expect(statements_for(ssp).pluck(:statement_id))
          .to contain_exactly("ac-1_smt", "ac-2_smt", "sc-1_smt")
      end

      # 30 base controls in Rev 5.2.0 genuinely have no statement (ac-2, au-2
      # among them). They must yield no row rather than an empty one.
      it "creates no statement for a control the catalog gives none" do
        catalog = resolved_catalog_json.deep_dup
        catalog["catalog"]["groups"][0]["controls"][1]["parts"] =
          [ { "id" => "ac-2_gdn", "name" => "guidance", "prose" => "Guidance only." } ]
        silent = create(:profile_document, lifecycle_status: "published",
                                           resolved_catalog_json: catalog,
                                           published: Time.current.iso8601)

        ssp = described_class.new(silent).create

        expect(statements_for(ssp).pluck(:statement_id)).to contain_exactly("ac-1_smt", "sc-1_smt")
        expect(ssp.ssp_controls.count).to eq(3)
      end

      # #397 invariant, shared with the OSCAL importer so one statement cannot
      # end up with two different ids depending on how it arrived.
      # The count assertion in each of the next three is load-bearing: without
      # it they pass vacuously when no statement is created at all, which is
      # exactly the bug they exist to catch.
      it "derives the statement uuid from the control uuid" do
        ssp = described_class.new(profile).create

        statements = statements_for(ssp).to_a
        expect(statements.size).to eq(3)
        statements.each do |statement|
          expect(statement.uuid).to eq(
            OscalUuidService.derived(statement.ssp_control.uuid, "ssp-statement", statement.statement_id)
          )
        end
      end

      it "leaves implementation_prose blank — the author has written none yet" do
        ssp = described_class.new(profile).create

        prose = statements_for(ssp).pluck(:implementation_prose)
        expect(prose.size).to eq(3)
        expect(prose.compact).to be_empty
      end

      # Tagging is a system owner declaring a customer responsibility matrix.
      # Generating the tags would fabricate a CRM nobody authored.
      it "tags no statement provided or responsibility" do
        ssp = described_class.new(profile).create

        tags = statements_for(ssp).pluck(:set_parameters_data)
        expect(tags.size).to eq(3)
        expect(tags.flatten).to be_empty
      end

      it "makes the SSP leverageable once a statement is tagged provided" do
        leveraged = described_class.new(profile, name: "Leveraged").create
        leveraging = described_class.new(profile, name: "Leveraging").create
        b1 = create(:authorization_boundary)
        b2 = create(:authorization_boundary)
        leveraged.update!(authorization_boundary_id: b1.id)
        leveraging.update!(authorization_boundary_id: b2.id)

        statements_for(leveraged).find_by(statement_id: "ac-1_smt")
                                 .update!(set_parameters_data: [ { "tag" => "provided" } ])

        la = LeveragedAuthorization.create!(name: "LA", leveraging_boundary: b2,
                                            leveraged_boundary: b1, crm_type: "oscal_with_access")

        expect(la.inheritable_statements.count).to eq(1)
        expect(LeveragedAuthorizationService.populate_from_leveraged!(la)).to eq(1)
      end
    end

    it "raises error for unpublished profile" do
      unpublished = create(:profile_document, lifecycle_status: "in_progress")

      expect {
        described_class.new(unpublished).create
      }.to raise_error(ArgumentError, /must be published/)
    end

    it "raises error for profile without resolved catalog" do
      no_catalog = create(:profile_document, lifecycle_status: "published", resolved_catalog_json: nil)

      expect {
        described_class.new(no_catalog).create
      }.to raise_error(ArgumentError, /must have a resolved catalog/)
    end
  end

  describe "#populate" do
    # #628 — populate an existing empty SSP from a published profile.
    it "imports controls into an existing empty SSP" do
      ssp = create(:ssp_document, name: "My Shell")

      result = described_class.new(profile).populate(ssp)

      expect(result).to eq(ssp)
      expect(ssp.reload.ssp_controls.count).to be > 0
      expect(ssp.name).to eq("My Shell")
    end

    it "links the profile and scaffolds the this-system component" do
      ssp = create(:ssp_document)

      described_class.new(profile).populate(ssp)

      expect(ssp.reload.profile_document_id).to eq(profile.id)
      expect(ssp.ssp_components.find_by(component_type: "this-system")).to be_present
    end

    it "makes the SSP content-complete" do
      ssp = create(:ssp_document, system_id: "SYS-1")
      expect(ssp.content_complete?).to be(false)

      described_class.new(profile).populate(ssp)

      expect(ssp.reload.content_complete?).to be(true)
    end

    it "raises when the SSP already has controls" do
      ssp = create(:ssp_document)
      create(:ssp_control, ssp_document: ssp)

      expect {
        described_class.new(profile).populate(ssp)
      }.to raise_error(ArgumentError, /already has controls/)
    end

    it "raises for an unpublished profile" do
      unpublished = create(:profile_document, lifecycle_status: "in_progress")
      ssp = create(:ssp_document)

      expect {
        described_class.new(unpublished).populate(ssp)
      }.to raise_error(ArgumentError, /must be published/)
    end
  end
end
