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
  # NOT a top-level constant: `FIXTURE_DIR = ...` at file scope is global in
  # Ruby, and this one collided with the constant of the same name in
  # spec/lib/xml_security_spec.rb. Whichever file loaded last won, and five
  # unrelated XML security examples went looking for their fixtures in
  # db/seeds/oscal. A `let` cannot be redefined across files.
  let(:fixture_dir) { Rails.root.join("db/seeds/oscal") }

  # Must match DEMO_MODERATE_PROFILE_UUID / DEMO_LOW_PROFILE_UUID in db/seeds.rb.
  # Two baselines, both Rev 5: the estate models a MODERATE system and a LOW
  # one, because a Rev 4 document cannot descend from a Rev 5 profile.
  let(:fixtures) do
    {
      "demo_acme_cloud_platform_ssp_rev5.json" =>
        OscalUuidService.derived("demo-published-profile", "NIST SP 800-53 Rev 5 MODERATE Baseline"),
      "demo_acme_hr_portal_ssp_rev5.json" =>
        OscalUuidService.derived("demo-published-profile", "NIST SP 800-53 Rev 5 LOW Baseline")
    }
  end

  it "ships both demo SSP fixtures" do
    fixtures.each_key do |name|
      expect(fixture_dir.join(name)).to exist, "#{name} is missing; the demo seed imports it"
    end
  end

  it "points every fixture's import-profile at the pinned demo profile UUID" do
    fixtures.each do |name, uuid|
      data = JSON.parse(File.read(fixture_dir.join(name)))
      href = data.dig("system-security-plan", "import-profile", "href")

      expect(href).to eq("uuid:#{uuid}"),
        "#{name} imports #{href.inspect}, which will not resolve to the seeded " \
        "demo profile. Either the fixture or DEMO_PROFILE_UUID has drifted."
    end
  end

  it "keeps the seed's pinned UUIDs in step with the fixtures" do
    seeds = File.read(Rails.root.join("db/seeds.rb"))

    [ "NIST SP 800-53 Rev 5 MODERATE Baseline", "NIST SP 800-53 Rev 5 LOW Baseline" ].each do |name|
      expect(seeds).to include(%(OscalUuidService.derived("demo-published-profile", "#{name}"))),
        "db/seeds.rb no longer derives the #{name} UUID the way these fixtures assume"
    end
  end

  # The vendored NIST baselines are what make the estate real: a demo that
  # invents its own ten-control "baseline" cannot show a system measured
  # against anything.
  it "ships the real NIST baseline profiles the seed selects from" do
    { "nist_rev5_low_baseline_profile.json" => 149,
      "nist_rev5_moderate_baseline_profile.json" => 287 }.each do |name, expected|
      path = fixture_dir.join(name)
      expect(path).to exist, "#{name} is missing; the demo baselines are seeded from it"

      ids = JSON.parse(File.read(path)).dig("profile", "imports").to_a.flat_map do |import|
        (import["include-controls"] || []).flat_map { |inc| inc["with-ids"] || [] }
      end.uniq

      expect(ids.length).to eq(expected),
        "#{name} selects #{ids.length} controls, not the #{expected} the estate is sized around"
    end
  end

  # The pin has to happen AFTER control selection. Asserting the ordering in
  # prose would rot; asserting the behaviour that forces it does not.
  it "documents why the pin cannot be set at create" do
    catalog = create(:control_catalog)
    family  = create(:control_family, control_catalog: catalog, code: "AC")
    family.catalog_controls.create!(control_id: "ac-1", title: "Policy")

    pinned  = fixtures.values.first
    profile = ProfileDocument.create!(name: "Pin ordering probe", control_catalog: catalog,
                                      status: "completed", uuid: pinned)
    expect(profile.uuid).to eq(pinned)

    ProfileControlSelectionService.new(profile).update([ "ac-1" ])

    expect(profile.reload.uuid).not_to eq(pinned),
      "ProfileControlSelectionService no longer regenerates the root UUID. If that " \
      "is deliberate, the seed can pin at create again and this test should go."
  end

  it "validates each fixture against the baked-in OSCAL SSP schema" do
    fixtures.each_key do |name|
      data = JSON.parse(File.read(fixture_dir.join(name)))

      expect { OscalSchemaValidationService.validate!(:ssp, data) }
        .not_to raise_error, "#{name} is not schema-valid OSCAL"
    end
  end
end
