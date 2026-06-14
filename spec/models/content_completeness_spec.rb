# frozen_string_literal: true

require "rails_helper"

# #627/#628 — content-completeness is a first-class concept, distinct from the
# parse `status` enum and the authoring `lifecycle_status`. A metadata-only API
# create resolves to `status: completed` yet must read as content-incomplete.
RSpec.describe ContentCompleteness do
  describe SspDocument do
    it "is incomplete with no system characteristics and no controls" do
      ssp = create(:ssp_document)

      expect(ssp.content_complete?).to be(false)
      expect(ssp.content_completeness_gaps)
        .to contain_exactly("System characteristics", "At least one control")
    end

    it "still needs a control once system characteristics are present" do
      ssp = create(:ssp_document, security_sensitivity_level: "fips-199-moderate")

      expect(ssp.content_complete?).to be(false)
      expect(ssp.content_completeness_gaps).to eq([ "At least one control" ])
    end

    it "is complete with system characteristics and at least one control" do
      ssp = create(:ssp_document, system_id: "SYS-1")
      create(:ssp_control, ssp_document: ssp)

      expect(ssp.content_complete?).to be(true)
      expect(ssp.content_completeness_gaps).to be_empty
    end
  end

  describe CdefDocument do
    it "is incomplete with no controls" do
      cdef = create(:cdef_document)

      expect(cdef.content_complete?).to be(false)
      expect(cdef.content_completeness_gaps).to eq([ "At least one control" ])
    end

    it "is complete with at least one control" do
      cdef = create(:cdef_document)
      create(:cdef_control, cdef_document: cdef)

      expect(cdef.content_complete?).to be(true)
    end
  end

  describe ProfileDocument do
    it "is incomplete with no catalog and no controls" do
      profile = create(:profile_document)

      expect(profile.content_complete?).to be(false)
      expect(profile.content_completeness_gaps)
        .to contain_exactly("A linked control catalog", "At least one control")
    end

    it "is complete with a linked catalog and at least one control" do
      profile = create(:profile_document, control_catalog: create(:control_catalog))
      create(:profile_control, profile_document: profile)

      expect(profile.content_complete?).to be(true)
    end
  end

  it "keeps requirement definitions isolated per model" do
    expect(CdefDocument.content_requirement_defs.size).to eq(1)
    expect(SspDocument.content_requirement_defs.size).to eq(2)
    expect(ProfileDocument.content_requirement_defs.size).to eq(2)
  end
end
