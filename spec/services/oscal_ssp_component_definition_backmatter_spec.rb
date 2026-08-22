# frozen_string_literal: true

require "rails_helper"

# #1004 — an exported SSP now carries the trail back to the component
# definitions its components came from.
#
# `ssp_components.cdef_document_id` recorded the link and the export dropped it,
# so a reader of the OSCAL saw a component uuid and a title and the trail
# stopped there: the boundary's component definitions were invisible in the
# package. Measured before the fix on a component built from a CDEF — the
# COMPONENT uuid appeared in the export, the CDEF uuid appeared nowhere, and
# back-matter held no resource for it.
#
# This is the same gap #999 closed for catalogs, where control-level links were
# discarded at import and back-matter resources were left inert instead of
# being promoted to rows an emitted `#uuid` href could resolve to. The SSP side
# never happened.
RSpec.describe "OSCAL SSP export: component definition back-matter" do
  let(:boundary) { create(:authorization_boundary) }
  let(:cdef) { create(:cdef_document, description: "The component definition") }
  let(:ssp) { create(:ssp_document, authorization_boundary: boundary) }

  def export_of(document)
    raw = OscalSspExportService.new(document.reload).export_unvalidated
    body = raw.is_a?(String) ? JSON.parse(raw) : raw
    body["system-security-plan"] || body
  end

  def component_from_cdef
    ssp.ssp_components.create!(uuid: SecureRandom.uuid, title: "Probe Component",
                               description: "d", component_type: "software",
                               cdef_document: cdef)
  end

  describe "a component built from a CDEF" do
    it "emits a back-matter resource for that component definition" do
      component_from_cdef

      resources = export_of(ssp).dig("back-matter", "resources")

      expect(resources.map { |r| r["uuid"] }).to include(cdef.uuid)
      resource = resources.find { |r| r["uuid"] == cdef.uuid }
      expect(resource["title"]).to eq(cdef.name)
    end

    it "links the component to that resource, so the href resolves inside the document" do
      component = component_from_cdef

      exported = export_of(ssp)
      entry = exported.dig("system-implementation", "components")
                      .find { |c| c["uuid"] == component.uuid }

      expect(entry["links"]).to include(
        a_hash_including("href" => "##{cdef.uuid}", "rel" => "component-definition")
      )
      # The reference must resolve to something the document carries — an href
      # pointing at a resource that is not in back-matter is a dangling
      # citation, which is what #1004 is about.
      resource_uuids = exported.dig("back-matter", "resources").map { |r| r["uuid"] }
      expect(resource_uuids).to include(cdef.uuid)
    end

    it "uses the same resource uuid on every export" do
      # Per-subject UUID rule: an export must never mint or change a uuid. A
      # resource whose identifier moves between exports is not a citation, and a
      # regenerated document presents as a different subject rather than a new
      # revision.
      component_from_cdef

      first = export_of(ssp).dig("back-matter", "resources").map { |r| r["uuid"] }
      second = export_of(ssp).dig("back-matter", "resources").map { |r| r["uuid"] }

      expect(first).to eq(second)
      expect(first).to include(cdef.uuid)
    end
  end

  describe "scoping" do
    it "carries only the CDEFs a component references, not every CDEF on the boundary" do
      component_from_cdef
      unreferenced = create(:cdef_document)

      resources = export_of(ssp).dig("back-matter", "resources").map { |r| r["uuid"] }

      expect(resources).to include(cdef.uuid)
      expect(resources).not_to include(unreferenced.uuid),
        "back-matter exists to resolve references the document makes (#959)"
    end

    it "adds nothing when no component came from a CDEF" do
      ssp.ssp_components.create!(uuid: SecureRandom.uuid, title: "Hand-written",
                                 description: "d", component_type: "software")

      exported = export_of(ssp)
      entry = exported.dig("system-implementation", "components").first

      expect(Array(entry["links"])).not_to include(a_hash_including("rel" => "component-definition"))
    end

    it "does not duplicate the resource when two components share one CDEF" do
      2.times do |i|
        ssp.ssp_components.create!(uuid: SecureRandom.uuid, title: "Component #{i}",
                                   description: "d", component_type: "software",
                                   cdef_document: cdef)
      end

      resources = export_of(ssp).dig("back-matter", "resources").map { |r| r["uuid"] }

      expect(resources.count(cdef.uuid)).to eq(1)
    end
  end

  it "still validates against the OSCAL SSP schema" do
    component_from_cdef
    ssp.ssp_controls.create!(control_id: "ac-2", title: "Account Management")

    result = OscalSspExportService.new(ssp.reload).validation_result

    expect(result.valid?).to be(true),
      "export no longer conforms: #{result.errors.first(3).join('; ')}"
  end
end
