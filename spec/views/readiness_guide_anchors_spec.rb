# frozen_string_literal: true

require "rails_helper"

# #940 — every Boundary Completeness row links into the Adopting OSCAL wiki
# page. A row whose anchor names no heading lands the reader at the top of the
# page with no explanation, which is indistinguishable from the page being wrong.
#
# The owner caught exactly this shape during review: the linked page was blank,
# because it had not been published yet. That half is a release-ordering matter
# (publish-wiki.yml fires on push to main when wiki/** changes). THIS half — the
# anchors matching real headings — is checkable here, and is checked.
RSpec.describe "readiness guide anchors" do
  let(:guide) { Rails.root.join("wiki/Adopting-OSCAL.md") }

  # GitHub's heading-slug rule: downcase, strip anything that is not word /
  # space / hyphen, then hyphenate the spaces.
  def guide_anchors
    guide.read.scan(/^##+\s+(.+)$/).flatten.map do |heading|
      heading.downcase.gsub(/[^\w\s-]/, "").strip.gsub(/\s+/, "-")
    end.to_set
  end

  it "the guide exists — the card links to it from every row" do
    expect(guide).to exist
  end

  it "every section anchor names a real heading in the guide" do
    boundary = create(:authorization_boundary)
    anchors = guide_anchors

    broken = BoundaryReadinessService.new(boundary).sections
                                     .reject { |s| anchors.include?(s.guide_anchor) }

    expect(broken).to be_empty, <<~MSG
      These readiness sections link to a heading that does not exist in
      wiki/Adopting-OSCAL.md, so the reader lands nowhere:

        #{broken.map { |s| "#{s.key} -> ##{s.guide_anchor}" }.join("\n  ")}

      Headings available: #{anchors.to_a.sort.join(', ')}
    MSG
  end
end
