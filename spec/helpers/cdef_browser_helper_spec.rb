# frozen_string_literal: true

require "rails_helper"

# #887 — presentation decisions for the CDEF browser, tested without rendering.
RSpec.describe CdefBrowserHelper, type: :helper do
  let(:summary) { CdefComponent.empty_summary.dup }

  describe "#cdef_display_name" do
    # The AWS importer bakes the version into the stored name and the card also
    # shows it as a badge, so the title repeated it. Stripped for DISPLAY only —
    # the stored name is what slugs derive from, so changing it would move every
    # existing URL.
    it "drops a trailing OSCAL version suffix" do
      document = build(:cdef_document, name: "AWS xray.oscal (oscal 1.2.1)")
      expect(helper.cdef_display_name(document)).to eq("AWS xray.oscal")
    end

    it "handles a two-part version" do
      document = build(:cdef_document, name: "AWS s3.oscal (oscal 1.1)")
      expect(helper.cdef_display_name(document)).to eq("AWS s3.oscal")
    end

    # A custom CDEF may legitimately have parentheses in its name; only a
    # version-shaped suffix is removed.
    it "leaves other parenthesised text alone" do
      document = build(:cdef_document, name: "Okta (Workforce Identity)")
      expect(helper.cdef_display_name(document)).to eq("Okta (Workforce Identity)")
    end

    it "leaves a version that is not at the end alone" do
      document = build(:cdef_document, name: "AWS (oscal 1.2.1) baseline")
      expect(helper.cdef_display_name(document)).to eq("AWS (oscal 1.2.1) baseline")
    end

    it "returns the name unchanged when there is no suffix" do
      document = build(:cdef_document, name: "Plain Name")
      expect(helper.cdef_display_name(document)).to eq("Plain Name")
    end
  end

  describe "#cdef_source_badge" do
    # Upstream AWS content is Apache-2.0 and explicitly experimental; curated
    # and org-provided definitions carry different warranties. The UI must never
    # blur them.
    it "marks upstream AWS content" do
      document = build(:cdef_document)
      allow(document).to receive(:aws_labs_source?).and_return(true)
      expect(helper.cdef_source_badge(document)[:text]).to eq("AWS")
    end

    it "marks organization-provided content" do
      document = build(:cdef_document, organization_id: 1)
      allow(document).to receive(:aws_labs_source?).and_return(false)
      expect(helper.cdef_source_badge(document)[:text]).to eq("Org")
    end

    it "falls back to local for a hand-authored definition" do
      document = build(:cdef_document)
      allow(document).to receive(:aws_labs_source?).and_return(false)
      expect(helper.cdef_source_badge(document)[:text]).to eq("Local")
    end
  end

  describe "#cdef_service_summary" do
    it "names the services a definition contains" do
      summary[:service_titles] = [ "Amazon WorkSpaces", "Amazon WorkSpaces Web" ]
      expect(helper.cdef_service_summary(summary)).to eq("Amazon WorkSpaces, Amazon WorkSpaces Web")
    end

    it "truncates a long family and says how many are hidden" do
      summary[:service_titles] = %w[One Two Three Four Five]
      expect(helper.cdef_service_summary(summary)).to eq("One, Two, Three +2 more")
    end

    it "is nil when there are no services to name" do
      expect(helper.cdef_service_summary(summary)).to be_nil
    end
  end

  describe "#cdef_partition_caveat" do
    # A unioned partition chip can claim GovCloud when only one of several
    # services is actually there — the most consequential thing on the card to
    # get wrong for a FedRAMP reader.
    it "warns when services disagree about availability" do
      summary[:partitions_uniform] = false
      expect(helper.cdef_partition_caveat(summary)).to match(/varies by service/i)
    end

    it "says nothing when they agree" do
      summary[:partitions_uniform] = true
      expect(helper.cdef_partition_caveat(summary)).to be_nil
    end
  end

  describe "#cdef_card_chips" do
    it "names partitions rather than showing raw identifiers" do
      summary[:partitions] = %w[aws aws-us-gov]
      expect(helper.cdef_card_chips(summary).map { |c| c[:text] })
        .to include("AWS Commercial", "AWS GovCloud")
    end

    # Emphasis is reserved for the declared-vs-derived distinction. Giving one
    # partition visual weight is the UI editorialising about which deployment
    # matters.
    it "gives no partition visual emphasis" do
      summary[:partitions] = %w[aws aws-us-gov aws-cn]
      partition_chips = helper.cdef_card_chips(summary).first(3)
      expect(partition_chips.map { |c| c[:class] }.compact).to be_empty
    end

    it "distinguishes a declared capability from a derived one" do
      summary[:declared_capabilities] = %w[MFA]
      summary[:derived_capabilities] = %w[Audit\ Logging]
      chips = helper.cdef_card_chips(summary)

      declared = chips.find { |c| c[:text] == "MFA" }
      derived  = chips.find { |c| c[:text] == "Audit Logging" }
      expect(declared[:class]).to eq("sparc-chip--strong")
      expect(derived[:class]).to eq("sparc-chip--derived")
    end

    # Flagging every GA service as GA is noise; only the exceptions matter.
    it "surfaces a non-GA lifecycle stage and stays quiet about GA" do
      summary[:lifecycle_stages] = %w[generally-available preview]
      texts = helper.cdef_card_chips(summary).map { |c| c[:text] }
      expect(texts).to include("preview")
      expect(texts).not_to include("generally available")
    end

    it "notes automated checks only when there are some" do
      expect(helper.cdef_card_chips(summary).map { |c| c[:text] }).not_to include("automated checks")
      summary[:check_count] = 3
      expect(helper.cdef_card_chips(summary).map { |c| c[:text] }).to include("automated checks")
    end
  end

  describe "#cdef_coverage_note" do
    # 163 of the 230 upstream AWS CDEFs assert nothing. Rendering an empty
    # region for the majority of the corpus would read as a broken screen.
    it "states plainly when nothing is asserted" do
      summary[:component_count] = 1
      expect(helper.cdef_coverage_note(summary)).to eq("No control coverage asserted.")
    end

    # "Nothing asserted upstream but SPARC derived some" and "nothing at all"
    # mean different things and must not read the same.
    it "distinguishes derived-only coverage" do
      summary[:component_count] = 1
      summary[:enriched_control_count] = 4
      expect(helper.cdef_coverage_note(summary)).to match(/4 derived by SPARC/)
    end

    it "distinguishes a document that was never indexed" do
      expect(helper.cdef_coverage_note(summary)).to eq("Not yet indexed.")
    end

    it "says nothing when the author asserted coverage" do
      summary[:native_control_count] = 2
      expect(helper.cdef_coverage_note(summary)).to be_nil
    end
  end

  describe "#cdef_mapping_note" do
    it "reports a one-hop lookup as direct" do
      summary[:mapping_sources] = %w[aws_direct]
      expect(helper.cdef_mapping_note(summary)).to eq("direct mapping")
    end

    it "reports a Config Rule hop as inferred" do
      summary[:mapping_sources] = %w[via_config_rule]
      expect(helper.cdef_mapping_note(summary)).to eq("inferred via Config Rule")
    end

    it "says nothing when nothing was mapped" do
      expect(helper.cdef_mapping_note(summary)).to be_nil
    end
  end
end
