# frozen_string_literal: true

require "rails_helper"

# The leveraged-POA&M demo fixture must be EXPORTABLE, not merely present.
#
# `db/seeds/collection_screens.rb` created it with no POA&M items. OSCAL
# requires at least one, so `download_oscal_validated`, `download_xml` and
# `download_yaml` all answered a 302 back to the show page carrying
# `?oscal_validation_failed=1` — three broken exports on every demo instance.
#
# This is the second time this fixture has broken an export by omitting a
# required OSCAL field. The first was `date_authorized` on the leveraged
# authorization, and the comment recording it sits directly above the POA&M
# block that then shipped without items. A comment did not prevent the repeat,
# so this is the assertion that does.
#
# Both were found by the ui-smoke export gate and were invisible to rspec,
# because rspec never seeds the demo estate. The gap this closes is exactly
# that: the rule is now checked where the fixture is defined rather than only
# where it is rendered.
RSpec.describe "db/seeds/collection_screens.rb — the leveraged POA&M exports" do
  let(:seed_path) { Rails.root.join("db/seeds/collection_screens.rb") }

  def run_seed
    # The seed prints progress; silence it so the suite output stays readable.
    original = $stdout
    $stdout = StringIO.new
    load seed_path
  ensure
    $stdout = original
  end

  before do
    # The fixture is skipped entirely when no authorization boundary exists, so
    # the estate it hangs off has to be there or this spec proves nothing.
    create(:authorization_boundary, name: "Seeded Boundary")
    run_seed
  end

  let(:leveraged_poam) do
    PoamDocument.find_by(name: "Shared Platform Services — Plan of Action & Milestones")
  end

  it "seeds the fixture at all" do
    expect(leveraged_poam).to be_present,
      "the leveraged-POA&M fixture did not seed, so the assertions below would be vacuous"
  end

  it "gives it at least one POA&M item" do
    # The specific defect. An empty POA&M is a valid database row and an
    # invalid OSCAL document, which is why "the fixture exists" was not enough.
    expect(leveraged_poam.poam_items.count).to be >= 1,
      "a POA&M with no items cannot be exported as OSCAL — the schema requires at least one"
  end

  it "exports as OSCAL that conforms to the schema" do
    # The property the item exists to satisfy, asserted directly rather than
    # inferred from the count — a future change could add an item and still
    # produce a document that does not validate for some other reason.
    result = OscalPoamExportService.new(leveraged_poam).validation_result

    expect(result.valid?).to be(true),
      "the seeded POA&M does not export valid OSCAL: #{result.errors.first(3).join('; ')}"
  end

  it "is idempotent — re-seeding does not duplicate the item" do
    # `find_or_create_by!` guards the document; the item is created only when
    # there are none, so a second run must not stack another one up.
    expect { run_seed }.not_to change { leveraged_poam.reload.poam_items.count }
  end

  it "heals an instance that was seeded before the item existed" do
    # The reason the item is created outside the `find_or_create_by!` block.
    # A demo instance seeded earlier already has the document and no items, and
    # would otherwise keep exporting an invalid POA&M forever.
    leveraged_poam.poam_items.destroy_all
    expect(leveraged_poam.reload.poam_items.count).to eq(0)

    run_seed

    expect(leveraged_poam.reload.poam_items.count).to be >= 1
  end
end
