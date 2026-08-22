# frozen_string_literal: true

require "rails_helper"

# #951 — narrowing evidence to a boundary INCLUDES global (leveraged) evidence.
#
# The default facet narrow is `WHERE authorization_boundary_id = X`, which
# answers "evidence OWNED by this boundary". The question the boundary view asks
# is "what evidence is this boundary using", and a system uses leveraged
# evidence it does not own — an inherited control implementation, a provider's
# artifact — carried here as a NULL boundary, the same global fallback
# `boundary_scoped_document` applies when deciding who may see what.
#
# Excluding it made the boundary view claim a system had LESS evidence than it
# does, which for an assessment view is the wrong direction to be wrong in.
#
# Both directions are pinned: widening must not become "shows everything".
RSpec.describe EvidenceBrowseQuery, "boundary scoping" do
  let(:boundary) { create(:authorization_boundary) }
  let(:other_boundary) { create(:authorization_boundary) }

  def evidence_for(boundary_id)
    described_class.new({ authorization_boundary_id: boundary_id }, scope: Evidence.all).records
  end

  it "includes evidence the boundary owns" do
    owned = create(:evidence, authorization_boundary: boundary)

    expect(evidence_for(boundary.id)).to include(owned)
  end

  it "includes global evidence the boundary leverages but does not own" do
    leveraged = create(:evidence, authorization_boundary: nil)

    expect(evidence_for(boundary.id)).to include(leveraged)
  end

  it "still excludes another boundary's evidence" do
    theirs = create(:evidence, authorization_boundary: other_boundary)

    expect(evidence_for(boundary.id)).not_to include(theirs)
  end

  it "does not become an unfiltered list" do
    create(:evidence, authorization_boundary: other_boundary)
    mine = create(:evidence, authorization_boundary: boundary)

    expect(evidence_for(boundary.id)).to contain_exactly(mine)
  end

  it "leaves the collection alone when no boundary is named" do
    mine = create(:evidence, authorization_boundary: boundary)
    theirs = create(:evidence, authorization_boundary: other_boundary)

    all = described_class.new({}, scope: Evidence.all).records

    expect(all).to include(mine, theirs)
  end
end
