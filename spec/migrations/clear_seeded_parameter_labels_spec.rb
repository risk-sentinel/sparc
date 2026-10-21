# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20261021120000_clear_seeded_parameter_labels.rb")

# Baselines built from a catalog stored each parameter's catalog LABEL as its
# value. Driven through `defer_data_migration` with the executing flag set the
# way the runner sets it, so a body that only registers fails here.
RSpec.describe ClearSeededParameterLabels do
  subject(:migration) { described_class.new }

  before { allow(migration).to receive(:say) }

  around do |example|
    DeferredDataMigration.executing!
    example.run
  ensure
    DeferredDataMigration.idle!
  end

  let(:control) { create(:profile_control, control_id: "ac-1") }

  def field(name, value) = control.profile_control_fields.create!(field_name: name, field_value: value)
  def value_of(id) = control.profile_control_fields.find_by(field_name: "parameter:#{id}").reload.field_value

  before do
    field("parameter_label:ac-01_odp.01", "personnel or roles")
    field("parameter:ac-01_odp.01", "personnel or roles")          # seeded label
    field("parameter_label:ac-01_odp.05", "frequency")
    field("parameter:ac-01_odp.05", "365")                         # an answer
    field("parameter_label:ac-01_odp.06", "events")
    field("parameter:ac-01_odp.06", "")                            # already unset
  end

  it "clears a value that is only the catalog's label and keeps every answer" do
    migration.up

    expect(value_of("ac-01_odp.01")).to eq("")
    expect(value_of("ac-01_odp.05")).to eq("365")
    expect(value_of("ac-01_odp.06")).to eq("")
    expect(control.profile_control_fields.find_by(field_name: "parameter_label:ac-01_odp.01").field_value)
      .to eq("personnel or roles")
  end

  it "does not match a label from another control or another parameter" do
    other = create(:profile_control, control_id: "ac-2")
    other.profile_control_fields.create!(field_name: "parameter_label:ac-01_odp.05", field_value: "365")
    field("parameter_label:ac-01_odp.07", "personnel or roles")
    field("parameter:ac-01_odp.07", "the ISSO")

    migration.up

    expect(value_of("ac-01_odp.05")).to eq("365")
    expect(value_of("ac-01_odp.07")).to eq("the ISSO")
  end

  it "is a no-op the second time, so a run stopped part-way resumes cleanly" do
    migration.up
    expect { migration.up }.not_to(change { control.profile_control_fields.order(:id).pluck(:field_value) })
  end

  it "stops the baseline exporting the label as tailoring" do
    profile = control.profile_document
    migration.up

    exported = Array(JSON.parse(OscalProfileExportService.new(profile.reload).export_unvalidated)
                         .dig("profile", "modify", "set-parameters")).map { |p| p["param-id"] }
    expect(exported).to eq([ "ac-01_odp.05" ])
  end
end
