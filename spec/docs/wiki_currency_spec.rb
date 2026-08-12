# frozen_string_literal: true

require "rails_helper"

# The wiki is the canonical, kept-current home for public documentation
# (CLAUDE.md, `docs/dev/issue_rules.md`). "Kept current" was an instruction with
# nothing enforcing it, and it drifted the way unenforced instructions do:
# `wiki/Home.md` advertised **v1.13.0** as the current version for roughly
# twelve releases, while the Changelog beside it was up to date. Nobody was
# careless — the two facts simply live in different files and only one of them
# is touched during a release.
#
# So the version claim gets a test, in the same shape as the structural specs
# added in #919: the drift itself fails a build rather than waiting to be
# spotted by a reader.
#
# ── What this deliberately does NOT check ───────────────────────────────────
#
# Whether the PUBLISHED wiki matches this source tree. The published wiki is a
# separate git repo, mirrored by `wiki/PUSH_TO_WIKI.sh`, and reaching it needs
# the network — which a unit spec must not depend on. That gap is real (the
# mirror was 3 releases behind when this was written) and is covered by an
# explicit step in `docs/dev/release_checklist.md` instead.
RSpec.describe "Wiki currency", type: :model do
  let(:wiki_root)  { Rails.root.join("wiki") }
  let(:home)       { wiki_root.join("Home.md").read }
  let(:changelog)  { wiki_root.join("Changelog.md").read }
  let(:version)    { SparcConfig::VERSION }

  # The current release line only.
  #
  # The Changelog deliberately retains the project's pre-reset v2.x-v3.x
  # numbering below a `# Legacy history` marker, for traceability. Those
  # entries sort ABOVE the v1.x line by version number while sitting below it
  # on the page, so any ordering rule has to stop at the marker or it reports
  # the archive as a defect.
  LEGACY_MARKER = /^#\s+Legacy history/

  def changelog_versions(text)
    current_line = text.split(LEGACY_MARKER).first
    current_line.scan(/^##\s+v(\d+\.\d+\.\d+)/).flatten
  end

  describe "Home.md" do
    it "advertises the shipping version" do
      # Matches the `| Current Version | **v1.15.5** |` table row.
      claimed = home[/\|\s*Current Version\s*\|\s*\*\*v([\d.]+)\*\*\s*\|/, 1]

      expect(claimed).to eq(version),
        "wiki/Home.md advertises v#{claimed || '(no version row found)'} but " \
        "SparcConfig::VERSION is #{version}. Update the Current Version row."
    end

    it "does not repeat a stale version in the prose beside the table" do
      # The versioning note restates the number, so fixing only the table row
      # leaves the page disagreeing with itself — which is how this survived.
      claimed = home[/public release line is \*\*v\d+\.x\*\*\s*\(current:\s*v([\d.]+)\)/, 1]

      expect(claimed).to eq(version),
        "The versioning note in wiki/Home.md says v#{claimed || '(not found)'}, " \
        "not #{version}. Both places state the version; both have to move."
    end
  end

  describe "Changelog.md" do
    # Pinning the NEWEST entry (rather than merely "an entry exists") is what
    # makes new gaps impossible: ship v1.16.1 without writing its entry and the
    # newest heading is still v1.16.0 while VERSION has moved, so this fails.
    #
    # It cannot heal the gaps that predate it — v1.0.0 through v1.4.1 have no
    # entries, and reconstructing them needs `gh release list`, which a unit
    # spec must not reach for. Everything from v1.5.0 forward is complete.
    it "leads with the shipping version" do
      newest = changelog_versions(changelog).first

      expect(newest).to eq(version),
        "wiki/Changelog.md's newest entry is v#{newest || '(none)'} but " \
        "SparcConfig::VERSION is #{version}. Every version that ships gets an " \
        "entry, checked against `gh release list` rather than memory."
    end

    it "lists versions newest-first" do
      # A release appended in the wrong place reads as current to anyone
      # scanning from the top, and hides the entry it was filed under.
      versions = changelog_versions(changelog)
      sorted = versions.sort_by { |v| Gem::Version.new(v) }.reverse

      expect(versions).to eq(sorted),
        "wiki/Changelog.md entries are out of order. Newest first."
    end

    it "has no duplicate entries for one version" do
      versions = changelog_versions(changelog)
      duplicated = versions.tally.select { |_, count| count > 1 }.keys

      expect(duplicated).to be_empty,
        "wiki/Changelog.md has more than one entry for: #{duplicated.join(', ')}"
    end
  end
end
