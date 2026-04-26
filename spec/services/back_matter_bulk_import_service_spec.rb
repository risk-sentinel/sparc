require "rails_helper"

RSpec.describe BackMatterBulkImportService do
  let(:actor) { create(:user, :admin) }
  let(:org)   { Organization.first || create(:organization) }

  it "imports valid entries and skips duplicates by (org, href, title)" do
    BackMatterResource.create!(uuid: SecureRandom.uuid, title: "Existing",
                               href: "https://x.gov/policy.pdf", source: "managed",
                               organization: org)

    entries = [
      { "title" => "New A",   "href" => "https://x.gov/a.pdf" },
      { "title" => "New B",   "href" => "https://x.gov/b.pdf" },
      { "title" => "Existing", "href" => "https://x.gov/policy.pdf" }
    ]

    result = described_class.new(entries: entries, actor: actor, organization: org).call

    expect(result).to be_success
    expect(result.imported.size).to eq(2)
    expect(result.skipped.size).to eq(1)
    expect(result.errors).to be_empty
    expect(result.imported.first.organization).to eq(org)
  end

  it "writes a create change row tagged with the batch uuid" do
    entries = [ { "title" => "Tagged", "href" => "https://x.gov/t.pdf" } ]
    result  = described_class.new(entries: entries, actor: actor, organization: org).call

    expect(result.imported.size).to eq(1)
    change = result.imported.first.changes_log.find_by(change_type: "create")
    expect(change).to be_present
    expect(change.batch_uuid).to eq(result.batch_uuid)
    expect(change.changed_by_user).to eq(actor)
  end

  it "captures per-row errors without aborting the batch" do
    entries = [
      { "title" => "OK",  "href" => "https://x.gov/ok.pdf" },
      { "title" => "",    "href" => "https://x.gov/blank.pdf" },
      { "title" => "OK2", "rel" => "not-a-valid-rel" }
    ]

    result = described_class.new(entries: entries, actor: actor, organization: org).call

    expect(result.imported.size).to eq(1)
    expect(result.errors.size).to eq(2)
    expect(result.errors.first[:index]).to eq(1)
  end

  it "rejects empty input" do
    result = described_class.new(entries: [], actor: actor, organization: org).call
    expect(result).not_to be_success
    expect(result.status_code).to eq(:unprocessable_entity)
  end

  it "rejects oversize batches" do
    entries = Array.new(described_class::MAX_ENTRIES_INLINE + 1) do |i|
      { "title" => "Row #{i}" }
    end
    result = described_class.new(entries: entries, actor: actor, organization: org).call

    expect(result).not_to be_success
    expect(result.error).to match(/limited to/i)
  end
end
