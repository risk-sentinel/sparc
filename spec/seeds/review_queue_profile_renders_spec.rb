# frozen_string_literal: true

require "rails_helper"

# The review-queue demo profile must be a document someone can OPEN, not merely
# a row the queue can list.
#
# `db/seeds/collection_screens.rb` created "… Profile (proposed revision)" at
# the import default, `status: pending`. A seeded profile is never parsed, so
# nothing moved it, and `profile_documents/show` renders only the "processing"
# banner for anything not `completed`: no controls, no UUID badge, no exports.
#
# It shipped that way because nothing looked at the page on a FRESH instance.
# rspec never seeds the demo estate, and the local browser gate ran against a
# database that had been in use, where this row was already `completed`. The
# v1.17.0 release gate, which does seed a fresh database, failed on it and the
# image was not published.
#
# So the rule is checked here, where the fixture is defined: after the seed,
# the page renders the document.
RSpec.describe "db/seeds/collection_screens.rb — the review-queue profile opens", type: :request do
  let(:seed_path) { Rails.root.join("db/seeds/collection_screens.rb") }
  let(:name)      { "Cloud Web Application ATO — Profile (proposed revision)" }
  let(:revision)  { ProfileDocument.find_by(name: name) }

  def run_seed
    original = $stdout
    $stdout = StringIO.new
    load seed_path
  ensure
    $stdout = original
  end

  before do
    # The fixture hangs off a catalog and is skipped without one; the rest of
    # the file needs a boundary. Without both this spec would prove nothing.
    create(:authorization_boundary, name: "Seeded Boundary")
    create(:control_catalog)
  end

  it "seeds the profile as completed, awaiting review" do
    run_seed

    expect(revision).to be_present, "the review-queue fixture did not seed, so the assertions below would be vacuous"
    expect(revision.status).to eq("completed")
    expect(revision.approval_status).to eq("pending_review")
  end

  it "renders the document, with its UUID, rather than the processing banner" do
    run_seed
    sign_in_as(create(:user, :admin))

    get profile_document_path(revision)

    expect(response).to have_http_status(:ok)
    badge = Nokogiri::HTML(response.body).css(".sparc-uuid .sparc-uuid__value").map { |n| n.text.strip }
    expect(badge).to include(revision.uuid)
  end

  it "heals a row an earlier seed left pending" do
    # What every instance seeded before this fix holds.
    stale = create(:profile_document, name: name, status: "pending", control_catalog: ControlCatalog.first)

    run_seed

    expect(stale.reload.status).to eq("completed")
    expect(ProfileDocument.where(name: name).count).to eq(1)
  end
end
