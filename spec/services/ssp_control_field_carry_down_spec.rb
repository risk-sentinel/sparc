# frozen_string_literal: true

require "rails_helper"

# #1312 — an SSP from before v1.17.5 answered status, control type, responsible
# entities and expected completion once per control. Each item that takes a
# response now answers for itself; the carry-down copies the control's values
# onto those items, mapped onto OSCAL's terms, and notes what does not map.
RSpec.describe SspControlFieldCarryDown do
  let(:ssp) do
    create(:ssp_document).tap do |doc|
      doc.update!(metadata_extra: (doc.metadata_extra || {}).merge(
        "roles" => [ { "id" => "isso", "title" => "Information System Security Officer" },
                     { "id" => "system-owner", "title" => "System Owner" } ]
      ))
    end
  end
  let(:control) { ssp.ssp_controls.create!(control_id: "ac-2", title: "Account Management") }

  def field!(name, value) = control.ssp_control_fields.create!(field_name: name, field_value: value)

  def item!(statement_id, parent: nil, **attrs)
    control.ssp_control_statements.create!(statement_id: statement_id, parent_statement_id: parent,
                                           uuid: SecureRandom.uuid, **attrs)
  end

  def carry! = described_class.new(ssp).carry!

  def notes = control.ssp_control_fields.find_by(field_name: "notes")&.field_value.to_s

  {
    "Implemented" => "implemented", "Deferred" => "planned", "Will Not Implement" => "alternative",
    "Not Applicable" => "not-applicable", "Partially Implemented" => "partial", "planned" => "planned"
  }.each do |old, new|
    it "maps a control-level status of #{old.inspect} to #{new.inspect} on every item that takes a response" do
      item!("ac-2_smt")
      item!("ac-2_smt.d", parent: "ac-2_smt")
      leaf1 = item!("ac-2_smt.d.1", parent: "ac-2_smt.d")
      leaf2 = item!("ac-2_smt.a", parent: "ac-2_smt")
      field!("status", old)

      carry!

      expect([ leaf1, leaf2 ].map { _1.reload.implementation_status }).to eq([ new, new ])
      expect(control.ssp_control_statements.find_by(statement_id: "ac-2_smt.d").implementation_status).to be_nil
    end
  end

  it "maps control type onto OSCAL's origination, and leaves a hybrid for the author with a note" do
    leaf = item!("ac-2_smt")
    field!("control_type", "Inherited from provider")
    carry!
    expect(leaf.reload.control_origination).to eq(%w[inherited])

    other = ssp.ssp_controls.create!(control_id: "ac-3", title: "Access Enforcement")
    hybrid = other.ssp_control_statements.create!(statement_id: "ac-3_smt", uuid: SecureRandom.uuid)
    other.ssp_control_fields.create!(field_name: "control_type", field_value: "Hybrid — partially inherited")
    carry!
    expect(hybrid.reload.control_origination).to eq([])
    expect(other.ssp_control_fields.find_by(field_name: "notes").field_value)
      .to include("Control type: Hybrid — partially inherited (set each item's origination)")
  end

  it "treats a control type of Not Applicable as a status" do
    leaf = item!("ac-2_smt")
    field!("control_type", "Not Applicable")
    carry!
    expect(leaf.reload).to have_attributes(implementation_status: "not-applicable", control_origination: [])
  end

  it "links responsible entities to the roles the document declares, and notes the rest" do
    leaf = item!("ac-2_smt")
    field!("responsible_entities", "ISSO; System Owner, Facilities team")
    carry!
    expect(leaf.reload.responsible_roles_data).to eq([ { "role-id" => "isso" }, { "role-id" => "system-owner" } ])
    expect(notes).to include("Responsible entities: Facilities team")
  end

  it "takes an ISO expected completion as the item's date, and notes anything else" do
    leaf = item!("ac-2_smt")
    field!("expected_completion", "2027-04-30")
    carry!
    expect(leaf.reload.expected_completion).to eq(Date.new(2027, 4, 30))

    other = ssp.ssp_controls.create!(control_id: "ac-4", title: "Information Flow")
    other.ssp_control_statements.create!(statement_id: "ac-4_smt", uuid: SecureRandom.uuid)
    other.ssp_control_fields.create!(field_name: "expected_completion", field_value: "Q3 FY27")
    carry!
    expect(other.ssp_control_fields.find_by(field_name: "notes").field_value).to include("Expected completion: Q3 FY27")
  end

  it "notes the retired control application and coverage level, after any notes already there" do
    item!("ac-2_smt")
    field!("notes", "Reviewed in March.")
    field!("control_application", "Hybrid")
    field!("coverage_level", "Documented")
    carry!
    expect(notes).to eq("Reviewed in March.\n\n#{described_class::NOTE_MARKER}\nControl application: Hybrid\nCoverage level: Documented")
  end

  it "never overwrites an item's own answer" do
    leaf = item!("ac-2_smt", implementation_status: "partial", control_origination: %w[organization])
    field!("status", "Implemented")
    field!("control_type", "System Specific")
    carry!
    expect(leaf.reload).to have_attributes(implementation_status: "partial", control_origination: %w[organization])
  end

  it "gives a control with no items its whole-control item, so the answer has a home" do
    field!("status", "Deferred")
    carry!
    item = control.ssp_control_statements.sole
    expect(item).to have_attributes(statement_id: "ac-2_smt", implementation_status: "planned")
    expect(item.uuid).to eq(OscalUuidService.derived(control.uuid, "ssp-statement", "ac-2_smt"))
  end

  it "changes nothing when run twice, and keeps the control-level rows for a rollback" do
    leaf = item!("ac-2_smt")
    field!("status", "Deferred")
    field!("coverage_level", "Documented")
    carry!
    before = [ leaf.reload.attributes, notes ]

    result = carry!

    expect([ leaf.reload.attributes, notes ]).to eq(before)
    expect(result.items).to eq(0)
    expect(control.ssp_control_fields.find_by(field_name: "status").field_value).to eq("Deferred")
  end

  # The deferred data migration runs this over every SSP.
  it "runs from the upgrade's data migration" do
    leaf = item!("ac-2_smt")
    field!("status", "Will Not Implement")
    require Rails.root.join("db/migrate/20261027120100_carry_ssp_control_fields_to_items.rb")

    begin
      DeferredDataMigration.executing!
      CarrySspControlFieldsToItems.new.up
    ensure
      DeferredDataMigration.idle!
    end

    expect(leaf.reload.implementation_status).to eq("alternative")
  end
end
