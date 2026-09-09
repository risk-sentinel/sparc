# frozen_string_literal: true

require "rails_helper"

# #1088 — the CDEF screen lists the SERVICE's controls, not every component's.
#
# Owner review: "AWS Elastic BeanStalk owns the service and software outright and
# the capabilities … are all required to achieve those controls on AWS Elastic
# Beanstalk the service. No reason to display anything other than the service
# level."
#
# An AWS Labs definition carries one `service` component asserting the service's
# controls, plus one `software` component per Config Rule re-asserting the one
# control its check delivers. Both are real OSCAL and both are EXPORTED; the
# screen showing both turned 3 controls into 6 rows differing only by which check
# named them.
RSpec.describe "CDEF service-level control list", type: :request do
  let(:document) { create(:cdef_document) }
  let(:service_uuid) { SecureRandom.uuid }
  let(:check_uuid)   { SecureRandom.uuid }

  before do
    sign_in_as(create(:user, :admin))

    document.cdef_components.create!(component_uuid: service_uuid, title: "AWS Elastic Beanstalk",
                                     component_type: "service")
    document.cdef_components.create!(component_uuid: check_uuid, title: "beanstalk-managed-updates",
                                     component_type: "software")

    document.cdef_controls.create!(control_id: "ca-7", title: "ca-7", row_order: 0,
                                   component_uuid: service_uuid,
                                   implementation_source: "https://example.test/cat")
    document.cdef_controls.create!(control_id: "si-2", title: "si-2", row_order: 1,
                                   component_uuid: service_uuid,
                                   implementation_source: "https://example.test/cat")
    # The check re-asserting one of the service's controls.
    document.cdef_controls.create!(control_id: "ca-7", title: "ca-7", row_order: 2,
                                   component_uuid: check_uuid,
                                   implementation_source: "https://example.test/cat")
  end

  # Asserted on the RENDERED page, not on an ivar: what the reader sees is the
  # thing under test, and a count that agrees with an instance variable while
  # disagreeing with the rows would be exactly the defect this guards.
  def rendered_control_cards
    response.body.scan(/class="control-card/).size
  end

  it "lists only the service's controls" do
    get cdef_document_path(document)

    expect(response).to have_http_status(:ok)
    expect(rendered_control_cards).to eq(2)
  end

  # The trap this bundle already hit once on the SSP heatmap: a header count
  # taken from a different set than the rows beneath it.
  it "counts what it lists" do
    get cdef_document_path(document)

    # Read the figure the header actually prints, rather than any string that
    # happens to contain a 2.
    printed = response.body[/sparc-score[^"]*">\s*(\d+)\s*<\/div>\s*<div class="sparc-score-label">Total Controls/m, 1]
    expect(printed).to eq("2"), "header printed #{printed.inspect} controls"
    expect(rendered_control_cards).to eq(2)
  end

  # A definition with no service component must not render an empty list.
  it "falls back to every control when there is no service component" do
    document.cdef_components.where(component_type: "service").destroy_all

    get cdef_document_path(document)

    expect(rendered_control_cards).to eq(3)
  end

  # Documents imported before #1088 carry no attribution at all.
  it "falls back to every control when nothing is attributed" do
    document.cdef_controls.update_all(component_uuid: nil)

    get cdef_document_path(document)

    expect(rendered_control_cards).to eq(3)
  end

  # #1088 — the severity pill read "(Unknown)" on every control of every
  # OSCAL-sourced CDEF, because severity is an XCCDF/STIG field an OSCAL
  # component definition does not carry. Owner: "meaningless without context".
  describe "the severity pill" do
    it "is absent when the control carries no severity" do
      get cdef_document_path(document)

      expect(response.body).not_to include("(Unknown)")
      expect(response.body).not_to match(/sparc-status-pill/)
    end

    # Still shown where it is real — a STIG-sourced CDEF populates it.
    it "is shown when the control does carry one" do
      document.cdef_controls.where(component_uuid: service_uuid).first.update!(severity: "high")

      get cdef_document_path(document)

      expect(response.body).to match(/sparc-status-pill/)
      expect(response.body).to include("high")
    end
  end

  # #1088 — scoping the list to the service removed the check components as
  # rows, and with them the control -> check linkage. Owner: "This is misleading
  # in how the rule can be checked is it not?" It was: the card named a Security
  # Hub id and a mapping source, and nothing said what actually verifies the
  # control.
  describe "the verifying check" do
    before do
      document.cdef_components.find_by(component_uuid: check_uuid)
              .update!(native_control_ids: [ "ELASTICBEANSTALK.1" ],
                       check_ids: [ "ELASTIC_BEANSTALK_MANAGED_UPDATES_ENABLED" ])
      document.cdef_controls.where(component_uuid: service_uuid, control_id: "ca-7").first
              .cdef_control_fields.create!(field_name: "aws_security_hub_id",
                                           field_value: "ElasticBeanstalk.1", editable: false)
    end

    it "names the check and its AWS Config Rule on the control it verifies" do
      get cdef_document_path(document)

      expect(response.body).to include("verified by")
      expect(response.body).to include("beanstalk-managed-updates")
      expect(response.body).to include("ELASTIC_BEANSTALK_MANAGED_UPDATES_ENABLED")
    end

    # `native_control_ids` is stored upcased by the indexer while the control's
    # field keeps AWS's own casing, so a raw comparison matches nothing and the
    # row silently never renders.
    it "matches despite the casing difference between the two stores" do
      document.cdef_controls.where(component_uuid: service_uuid, control_id: "ca-7").first
              .cdef_control_fields.find_by(field_name: "aws_security_hub_id")
              .update!(field_value: "elasticbeanstalk.1")

      get cdef_document_path(document)

      expect(response.body).to include("ELASTIC_BEANSTALK_MANAGED_UPDATES_ENABLED")
    end

    it "says nothing for a control no check covers" do
      get cdef_document_path(document)

      si2 = response.body[/si-2.*?(?=class="control-card|\z)/m]
      expect(si2).not_to include("verified by") if si2
    end
  end

  # Screen scoping must not reach the artifact: OSCAL fidelity requires every
  # component and its own implemented-requirements.
  it "still exports every component, including the checks" do
    raw = OscalComponentDefinitionExportService.new(document).export_unvalidated
    comps = (raw.is_a?(String) ? JSON.parse(raw) : raw.deep_stringify_keys)
              .dig("component-definition", "components")

    expect(comps.map { |c| c["title"] })
      .to match_array([ "AWS Elastic Beanstalk", "beanstalk-managed-updates" ])
  end
end
