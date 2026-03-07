require "rails_helper"

RSpec.describe SapGeneratorService do
  describe "#generate" do
    context "with an SSP document" do
      let(:ssp) { create(:ssp_document, name: "Test SSP") }

      before do
        ctrl = ssp.ssp_controls.create!(control_id: "AC-1", title: "Access Control Policy")
        ctrl.ssp_control_fields.create!(field_name: "status", field_value: "Implemented")
        ctrl.ssp_control_fields.create!(field_name: "private_implementation", field_value: "AC-1 is implemented via LDAP.")

        ctrl2 = ssp.ssp_controls.create!(control_id: "AT-1", title: "Awareness Training Policy")
        ctrl2.ssp_control_fields.create!(field_name: "status", field_value: "Implemented")
      end

      it "creates a SAP document with controls from the SSP" do
        sap = described_class.new(
          name: "FY26 Assessment",
          ssp_document: ssp,
          assessment_type: "annual"
        ).generate

        expect(sap).to be_a(SapDocument)
        expect(sap).to be_completed
        expect(sap.sap_controls.count).to eq(2)
        expect(sap.ssp_document).to eq(ssp)
      end

      it "assigns default assessment methods by control family" do
        sap = described_class.new(
          name: "Test",
          ssp_document: ssp
        ).generate

        ac_control = sap.sap_controls.find_by(control_id: "AC-1")
        at_control = sap.sap_controls.find_by(control_id: "AT-1")

        expect(ac_control.assessment_method).to eq("test")
        expect(at_control.assessment_method).to eq("interview")
      end

      it "filters controls when selected_control_ids is provided" do
        sap = described_class.new(
          name: "Test",
          ssp_document: ssp,
          selected_control_ids: [ "AC-1" ]
        ).generate

        expect(sap.sap_controls.count).to eq(1)
        expect(sap.sap_controls.first.control_id).to eq("AC-1")
      end

      it "carries over implementation data as control fields" do
        sap = described_class.new(
          name: "Test",
          ssp_document: ssp
        ).generate

        ac_control = sap.sap_controls.find_by(control_id: "AC-1")
        impl_field = ac_control.sap_control_fields.find_by(field_name: "implementation_description")
        expect(impl_field.field_value).to include("LDAP")
      end
    end

    context "with a Profile document" do
      let(:profile) { create(:profile_document) }

      before do
        profile.profile_controls.create!(control_id: "SC-1", title: "System and Communications Protection Policy")
        profile.profile_controls.create!(control_id: "PE-1", title: "Physical and Environmental Protection Policy")
      end

      it "creates a SAP document with controls from the Profile" do
        sap = described_class.new(
          name: "Profile Assessment",
          profile_document: profile
        ).generate

        expect(sap.sap_controls.count).to eq(2)
        expect(sap.profile_document).to eq(profile)
      end
    end

    context "with method overrides" do
      let(:ssp) { create(:ssp_document) }

      before do
        ssp.ssp_controls.create!(control_id: "AC-1", title: "Access Control Policy")
      end

      it "applies method overrides" do
        sap = described_class.new(
          name: "Test",
          ssp_document: ssp,
          assessment_methods: { "AC-1" => "interview" }
        ).generate

        control = sap.sap_controls.find_by(control_id: "AC-1")
        expect(control.assessment_method).to eq("interview")
      end
    end
  end
end
