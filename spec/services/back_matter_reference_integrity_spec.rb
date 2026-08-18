# frozen_string_literal: true

require "rails_helper"

# #959 — the invariant that makes scoping back-matter safe.
#
# An OSCAL document refers to a back-matter resource by `{"href" => "#<uuid>"}`.
# The resource must be present in that document's own `back-matter`, or the
# reference dangles and the export is invalid.
#
# Before #959 the builder embedded EVERY authoritative resource in the instance
# into EVERY export, which made dangling references impossible by brute force —
# and leaked unrelated instance state into every document as the price. Measured
# on a dev estate: 12 authoritative resources, all of them UI-smoke residue,
# embedded into all 12 artifacts of the #845 reference estate.
#
# Scoping the builder to what a document actually references removes the leak
# and introduces the opposite risk: under-inclusion. **This file is that guard,
# and it is deliberately written before the narrowing.** Both directions are
# asserted — nothing referenced is missing, and nothing unreferenced is carried.
RSpec.describe "Back-matter reference integrity (#959)" do
  # Pull every "#uuid" href out of an exported OSCAL hash, wherever it appears.
  def referenced_uuids(node, found = Set.new)
    case node
    when Hash
      href = node["href"]
      found << href.delete_prefix("#") if href.is_a?(String) && href.start_with?("#") && href.length > 1
      node.each_value { |v| referenced_uuids(v, found) }
    when Array
      node.each { |v| referenced_uuids(v, found) }
    end
    found
  end

  def embedded_uuids(export)
    resources = export.dig("back-matter", "resources") ||
                export.values.first&.dig("back-matter", "resources") || []
    resources.filter_map { |r| r["uuid"] }.to_set
  end

  let(:boundary) { create(:authorization_boundary) }

  # #911 — an export is REFUSED when a control resolves to no loaded catalog, so
  # the control has to exist before any of this is about back-matter at all.
  before { ensure_control("AC-2", title: "Account Management") }

  # An authoritative resource nothing points at. Under the old builder it
  # appeared in every export; it must now appear in none.
  let!(:unreferenced_authoritative) do
    create(:back_matter_resource, source: "authoritative", globally_available: true,
           title: "Unrelated Provider Source", resourceable: nil)
  end

  describe "an SSP that links a control to an authoritative resource" do
    let(:ssp) { create(:ssp_document, authorization_boundary: boundary) }
    let(:control) { create(:ssp_control, ssp_document: ssp, control_id: "AC-2", title: "Account Management") }
    let!(:linked) do
      resource = create(:back_matter_resource, source: "authoritative", globally_available: true,
                        title: "Provider Policy", resourceable: nil)
      ControlBackMatterLink.create!(linkable: control, back_matter_resource: resource)
      resource
    end

    it "embeds the resource its controls reference" do
      export = JSON.parse(OscalSspExportService.new(ssp).export)

      expect(embedded_uuids(export)).to include(linked.uuid),
        "a referenced authoritative resource is missing from back-matter — the export has a dangling href"
    end

    it "does NOT embed an authoritative resource nothing references (#959)" do
      export = JSON.parse(OscalSspExportService.new(ssp).export)

      expect(embedded_uuids(export)).not_to include(unreferenced_authoritative.uuid),
        "an unrelated authoritative resource leaked into this document's export"
    end

    # The invariant proper. This is what must never break, whatever the scoping
    # rule becomes: every reference resolves.
    it "leaves no dangling reference" do
      export = JSON.parse(OscalSspExportService.new(ssp).export)
      dangling = referenced_uuids(export) - embedded_uuids(export)

      expect(dangling).to be_empty,
        "export references back-matter that is not embedded: #{dangling.to_a.join(', ')}"
    end
  end

  describe "a CDEF that links a control to an authoritative resource" do
    let(:cdef) { create(:cdef_document) }
    let(:control) { create(:cdef_control, cdef_document: cdef, control_id: "AC-2", title: "Account Management") }
    let!(:linked) do
      resource = create(:back_matter_resource, source: "authoritative", globally_available: true,
                        title: "Component Provider Source", resourceable: nil)
      ControlBackMatterLink.create!(linkable: control, back_matter_resource: resource)
      resource
    end

    it "embeds what it references and nothing more" do
      export = JSON.parse(OscalComponentDefinitionExportService.new(cdef).export)
      embedded = embedded_uuids(export)

      expect(embedded).to include(linked.uuid)
      expect(embedded).not_to include(unreferenced_authoritative.uuid)
      expect(referenced_uuids(export) - embedded).to be_empty
    end
  end

  describe "a document that references nothing" do
    let(:ssp) { create(:ssp_document, authorization_boundary: boundary) }

    # A control with no back-matter link: the document is a valid, exportable
    # SSP that simply points at no resources. Without it the export is refused
    # by OSCAL schema validation (implemented-requirements needs at least one),
    # which would fail these examples for a reason unrelated to back-matter.
    before { create(:ssp_control, ssp_document: ssp, control_id: "AC-2", title: "Account Management") }

    it "carries no authoritative resources at all" do
      export = JSON.parse(OscalSspExportService.new(ssp).export)

      expect(embedded_uuids(export)).not_to include(unreferenced_authoritative.uuid)
    end

    # The reproducibility claim in #959: an export depends on the document, not
    # on unrelated instance state. #845 assumes this to regenerate committed
    # artifacts byte-identically.
    it "exports identically before and after an unrelated authoritative resource is added" do
      before_export = OscalSspExportService.new(ssp).export

      create(:back_matter_resource, source: "authoritative", globally_available: true,
             title: "Added Later By Someone Else", resourceable: nil)

      after_export = OscalSspExportService.new(ssp.reload).export

      expect(after_export).to eq(before_export),
        "adding an unrelated authoritative resource changed this document's export"
    end
  end
end
