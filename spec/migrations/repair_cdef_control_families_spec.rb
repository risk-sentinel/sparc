# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20260908160000_repair_cdef_control_families.rb")

# #1088 CDEF screen review — the heatmap grouped by AWS Security Hub rule
# instead of NIST family, because `AwsLabsCdefImportService#write_enrichment!`
# rewrote `control_id` to the resolved NIST control and left `control_family`
# holding the rule it was parsed from.
RSpec.describe RepairCdefControlFamilies do
  subject(:migration) { described_class.new }

  before { allow(migration).to receive(:say) }

  around do |example|
    DeferredDataMigration.executing!
    example.run
  ensure
    DeferredDataMigration.idle!
  end

  let(:document) { create(:cdef_document) }

  def control(control_id:, control_family:, source: "ElasticBeanstalk.1")
    document.cdef_controls.create!(control_id: control_id, title: "t",
                                   control_family: control_family,
                                   source_control_id: source)
  end

  it "re-derives the family from the resolved NIST id" do
    c = control(control_id: "ca-7", control_family: "ELASTICBEANSTALK.1")

    migration.up

    expect(c.reload.control_family).to eq("CA")
  end

  # The provenance the family column was wrongly carrying lives on
  # source_control_id, and must survive the repair.
  it "keeps the Security Hub rule as provenance" do
    c = control(control_id: "si-2", control_family: "ELASTICBEANSTALK.2",
                source: "ElasticBeanstalk.2")

    migration.up

    expect(c.reload.source_control_id).to eq("ElasticBeanstalk.2")
  end

  # An unmapped rule has no NIST family. Leaving the rule id there put unmapped
  # rows on the heatmap as though they were a control family of their own.
  it "clears the family on a row the converter could not resolve" do
    c = control(control_id: nil, control_family: "ELASTICBEANSTALK.3")

    migration.up

    expect(c.reload.control_family).to be_nil
  end

  it "leaves a row that already satisfies the invariant untouched" do
    c = control(control_id: "ac-2", control_family: "AC")

    expect { migration.up }.not_to change { c.reload.updated_at }
  end

  it "repairs enhancements to their base family" do
    c = control(control_id: "ac-2.7", control_family: "ELASTICBEANSTALK.9")

    migration.up

    expect(c.reload.control_family).to eq("AC")
  end

  it "is idempotent" do
    c = control(control_id: "ca-7", control_family: "ELASTICBEANSTALK.1")
    migration.up

    expect { migration.up }.not_to change { c.reload.control_family }
  end
end
