# frozen_string_literal: true

require "rails_helper"

# #887 — search and the card summaries.
RSpec.describe CdefComponent, "search and summaries", type: :model do
  let(:document) { create(:cdef_document) }

  def component(**attrs)
    attrs = { cdef_document: document, component_uuid: SecureRandom.uuid }.merge(attrs)
    attrs[:search_blob] ||= described_class.build_search_blob(attrs)
    described_class.create!(attrs)
  end

  describe ".search" do
    # The document-level scope only sees name and description, so `us-east`
    # matched nothing even though most components are available there. These
    # facts live on the component, not the document.
    it "finds a component by a partial region id" do
      subject = component(region_ids: %w[us-east-1 eu-west-2])
      expect(described_class.search("us-east")).to contain_exactly(subject)
    end

    it "finds a component by a partial control id" do
      subject = component(native_control_ids: %w[AC-2.1])
      expect(described_class.search("AC-2")).to contain_exactly(subject)
    end

    it "finds a component by capability" do
      subject = component(declared_capabilities: %w[MFA])
      expect(described_class.search("mfa")).to contain_exactly(subject)
    end

    it "finds a component by automated check id" do
      subject = component(check_ids: %w[S3_BUCKET_VERSIONING_ENABLED])
      expect(described_class.search("BUCKET_VERSION")).to contain_exactly(subject)
    end

    it "finds a component by service id and by title" do
      subject = component(service_id: "XRay", title: "AWS X-Ray")
      expect(described_class.search("xray")).to contain_exactly(subject)
      expect(described_class.search("X-Ray")).to contain_exactly(subject)
    end

    it "is case insensitive" do
      subject = component(partitions: %w[aws-us-gov])
      expect(described_class.search("AWS-US-GOV")).to contain_exactly(subject)
    end

    # Negative control: a search that matches everything is as useless as one
    # that matches nothing.
    it "returns nothing for a term that appears nowhere" do
      component(region_ids: %w[us-east-1])
      expect(described_class.search("no-such-value-zzz")).to be_empty
    end

    it "returns nothing for a blank term rather than everything" do
      component(region_ids: %w[us-east-1])
      expect(described_class.search("")).to be_empty
      expect(described_class.search(nil)).to be_empty
    end

    # The term goes into a LIKE pattern; `%` must be matched literally rather
    # than acting as a wildcard that matches every row.
    it "treats LIKE metacharacters in the term as literal" do
      component(title: "plain")
      expect(described_class.search("%")).to be_empty
    end
  end

  describe ".build_search_blob" do
    it "includes both text columns and every array column" do
      blob = described_class.build_search_blob(
        title: "AWS X-Ray", service_id: "XRay", region_ids: %w[us-gov-west-1],
        native_control_ids: %w[AC-2], check_ids: %w[SOME_RULE]
      )

      expect(blob).to include("AWS X-Ray", "XRay", "us-gov-west-1", "AC-2", "SOME_RULE")
    end

    it "skips blanks rather than emitting empty separators" do
      expect(described_class.build_search_blob(title: "only", description: nil, region_ids: [])).to eq("only")
    end
  end

  describe ".summary_for" do
    # An upstream file is a service FAMILY: workspaces.oscal carries four
    # services with different region sets (17 / 0 / 7 / 10).
    let!(:wide)   { component(component_type: "service", title: "Amazon WorkSpaces", partitions: %w[aws aws-us-gov], region_ids: %w[us-east-1 us-gov-west-1]) }
    let!(:narrow) { component(component_type: "service", title: "Amazon WorkSpaces Web", partitions: %w[aws], region_ids: %w[us-east-1]) }
    let!(:rule)   { component(component_type: "software", title: "a-config-rule", check_ids: %w[RULE_ONE]) }

    it "names the services rather than only counting them" do
      summary = described_class.summary_for([ document.id ])[document.id]
      expect(summary[:service_titles]).to eq([ "Amazon WorkSpaces", "Amazon WorkSpaces Web" ])
      expect(summary[:service_count]).to eq(2)
    end

    # A unioned partition chip can say GovCloud when only one of several
    # services is actually there. The card has to be able to say so.
    it "flags when services do not share a partition set" do
      summary = described_class.summary_for([ document.id ])[document.id]
      expect(summary[:partitions]).to contain_exactly("aws", "aws-us-gov")
      expect(summary[:partitions_uniform]).to be false
    end

    it "does not flag when every service agrees" do
      narrow.update!(partitions: %w[aws aws-us-gov])
      summary = described_class.summary_for([ document.id ])[document.id]
      expect(summary[:partitions_uniform]).to be true
    end

    it "treats a single service as uniform" do
      narrow.destroy!
      summary = described_class.summary_for([ document.id ])[document.id]
      expect(summary[:partitions_uniform]).to be true
    end

    it "prefers a service description for the card" do
      wide.update!(description: "Managed desktops.")
      summary = described_class.summary_for([ document.id ])[document.id]
      expect(summary[:primary_description]).to eq("Managed desktops.")
    end

    # check_ids repeat across a document's components because a service rolls
    # up its siblings', so the count must be of distinct rules.
    it "counts distinct checks, not occurrences" do
      wide.update!(check_ids: %w[RULE_ONE])
      summary = described_class.summary_for([ document.id ])[document.id]
      expect(summary[:check_count]).to eq(1)
    end

    it "returns nothing for no ids rather than querying the whole table" do
      expect(described_class.summary_for([])).to eq({})
    end

    it "scopes each summary to its own document" do
      other = create(:cdef_document)
      described_class.create!(cdef_document: other, component_uuid: SecureRandom.uuid,
                              component_type: "service", title: "Elsewhere")

      summaries = described_class.summary_for([ document.id, other.id ])
      expect(summaries[other.id][:service_titles]).to eq([ "Elsewhere" ])
      expect(summaries[document.id][:service_titles]).not_to include("Elsewhere")
    end
  end

  describe ".partition_label" do
    it "names each partition rather than showing its identifier" do
      expect(described_class.partition_label("aws")).to eq("AWS Commercial")
      expect(described_class.partition_label("aws-us-gov")).to eq("AWS GovCloud")
      expect(described_class.partition_label("aws-cn")).to eq("AWS China")
    end

    it "falls back to the raw value for anything unrecognised" do
      expect(described_class.partition_label("aws-iso-b")).to eq("aws-iso-b")
    end
  end
end
