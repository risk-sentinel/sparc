require "rails_helper"

RSpec.describe BoundaryMetadataSyncJob, type: :job do
  it "is enqueued in the default queue" do
    expect(described_class.new.queue_name).to eq("default")
  end

  it "delegates to BoundaryMetadataSyncService#propagate!" do
    boundary = create(:authorization_boundary,
                      boundary_metadata: { "system_title" => "Synced" })
    create(:ssp_document, authorization_boundary: boundary, name: "Old")
    described_class.new.perform(boundary.id)
    expect(boundary.ssp_document.reload.name).to eq("Synced")
  end

  it "no-ops on missing boundary" do
    expect { described_class.new.perform(999_999) }.not_to raise_error
  end
end
