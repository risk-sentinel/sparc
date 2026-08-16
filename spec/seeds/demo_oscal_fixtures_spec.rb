# frozen_string_literal: true

require "rails_helper"

# #946 — the committed demo SSP fixtures name the demo profile by UUID.
#
# That href is only useful if the seeded profile actually carries that UUID, and
# nothing in the unit suite connects the two: the fixture is a file, the pin is
# a line in `db/seeds.rb`, and they drift silently. This bug shipped past a full
# green suite once already — the pin was set at create and then destroyed
# moments later by `ProfileControlSelectionService#update`, which regenerates
# the root UUID because OSCAL requires a content change to produce a new one.
# It was only caught by booting the production image and looking.
#
# These assertions are cheap and they close that gap: if either side moves, the
# suite fails instead of the demo estate quietly coming up unlinked.
RSpec.describe "committed demo OSCAL fixtures (#946)" do
  FIXTURE_DIR = Rails.root.join("db/seeds/oscal")

  # Must match `DEMO_PROFILE_UUID` in db/seeds.rb.
  let(:demo_profile_uuid) do
    OscalUuidService.derived("demo-published-profile", "Demo LOW Baseline")
  end

  let(:fixtures) do
    %w[demo_acme_cloud_platform_ssp_rev5.json demo_acme_hr_portal_ssp_rev4.json]
  end

  it "ships both demo SSP fixtures" do
    fixtures.each do |name|
      expect(FIXTURE_DIR.join(name)).to exist, "#{name} is missing; the demo seed imports it"
    end
  end

  it "points every fixture's import-profile at the pinned demo profile UUID" do
    fixtures.each do |name|
      data = JSON.parse(File.read(FIXTURE_DIR.join(name)))
      href = data.dig("system-security-plan", "import-profile", "href")

      expect(href).to eq("uuid:#{demo_profile_uuid}"),
        "#{name} imports #{href.inspect}, which will not resolve to the seeded " \
        "demo profile. Either the fixture or DEMO_PROFILE_UUID has drifted."
    end
  end

  it "keeps the seed's pinned UUID in step with the fixtures" do
    seeds = File.read(Rails.root.join("db/seeds.rb"))

    expect(seeds).to include('OscalUuidService.derived("demo-published-profile", "Demo LOW Baseline")'),
      "db/seeds.rb no longer derives DEMO_PROFILE_UUID the way these fixtures assume"
  end

  # The pin has to happen AFTER control selection. Asserting the ordering in
  # prose would rot; asserting the behaviour that forces it does not.
  it "documents why the pin cannot be set at create" do
    catalog = create(:control_catalog)
    family  = create(:control_family, control_catalog: catalog, code: "AC")
    family.catalog_controls.create!(control_id: "ac-1", title: "Policy")

    profile = ProfileDocument.create!(name: "Pin ordering probe", control_catalog: catalog,
                                      status: "completed", uuid: demo_profile_uuid)
    expect(profile.uuid).to eq(demo_profile_uuid)

    ProfileControlSelectionService.new(profile).update([ "ac-1" ])

    expect(profile.reload.uuid).not_to eq(demo_profile_uuid),
      "ProfileControlSelectionService no longer regenerates the root UUID. If that " \
      "is deliberate, the seed can pin at create again and this test should go."
  end

  it "validates each fixture against the baked-in OSCAL SSP schema" do
    fixtures.each do |name|
      data = JSON.parse(File.read(FIXTURE_DIR.join(name)))

      expect { OscalSchemaValidationService.validate!(:ssp, data) }
        .not_to raise_error, "#{name} is not schema-valid OSCAL"
    end
  end
end
