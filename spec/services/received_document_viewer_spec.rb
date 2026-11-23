# frozen_string_literal: true

require "rails_helper"

# #1390 part G — the received-document viewer, against the real sample
# package (samples/fedramp-package-demo) and a second version of each
# document (spec/fixtures/files/fedramp/viewer/*.v2.json).
#
# What it must get right: every recorded change lands on the place it is
# about; "Compare with" calculates a comparison with another version of the
# same document in the same boundary, never stores it, and never reaches
# across streams or boundaries; every top-level field a document carries is
# shown under some section.
#
# NIST SP 800-53: CA-7, SI-10, AC-4.
RSpec.describe ReceivedDocumentViewer do
  types = %w[vulnerability-detail-report security-decision-record certification-package-overview
             ongoing-certification-report incident-report significant-change-notifications
             historical-ver-activity accepted-vulnerability-info assessor-information advisor-information]

  def sample(name) = File.read(Rails.root.join("samples/fedramp-package-demo", name))
  def second(type) = File.read(Rails.root.join("spec/fixtures/files/fedramp/viewer", "#{type}.v2.json"))

  let(:boundary) { create(:authorization_boundary) }
  let(:reviewer) { create(:user) }

  def received_doc(bytes, into: boundary, name: "doc.json")
    ReceivedDocumentService.call(boundary: into, bytes: bytes, source: "upload", filename: name,
                                 content_type: "application/json", received_by: nil).document
  end

  def accept(doc) = ReceivedDocumentReviewService.accept(doc, user: reviewer)

  types.each do |type|
    describe type do
      let(:v1) { received_doc(sample("#{type}.json")).tap { |d| accept(d) } }
      let(:v2) { v1 && received_doc(second(type)) }

      it "records the version it was compared with, and places every recorded change in the document" do
        expect(v2.compared_with).to eq(v1)
        viewer = described_class.new(v2)

        expect(viewer).to be_recorded
        expect(viewer.compared).to eq(v1)
        expect(viewer.changes).not_to be_empty
        placed = viewer.changes.select(&:pointer)
        expect(placed.size).to eq(viewer.changes.size), "unplaced: #{(viewer.changes - placed).map(&:key)}"
        placed.each do |change|
          in_current = ExchangeDelta::JsonDiff.resolve(viewer.current_data, change.pointer)
          in_compared = ExchangeDelta::JsonDiff.resolve(viewer.compared_data, change.pointer)
          expect([ in_current, in_compared ]).not_to eq([ nil, nil ]), "#{change.pointer} is in neither version"
        end
      end

      it "shows every top-level field under some section" do
        viewer = described_class.new(v2)
        shown = viewer.sections.flat_map { |_, keys, _| keys }
        expect(shown).to match_array(viewer.current_data.keys - [ "$schema" ])
      end
    end
  end

  describe "compare with" do
    let(:sdr) { "security-decision-record" }
    let!(:v1) { received_doc(sample("#{sdr}.json")).tap { |d| accept(d) } }
    let!(:v2) { received_doc(second(sdr)).tap { |d| accept(d) } }
    let!(:v3) do
      doc = JSON.parse(second(sdr))
      doc["metadata"]["version"] = "1.4.0"
      received_doc(JSON.generate(doc))
    end

    it "compares with the recorded baseline by default and with any earlier version on request, storing nothing" do
      expect(v3.compared_with).to eq(v2)
      recorded = described_class.new(v3)
      expect(recorded).to be_recorded
      expect(recorded.changes.map(&:pointer)).to eq([ "/metadata/version" ])

      expect { @other = described_class.new(v3, compare_to: v1) }.not_to(change { v3.reload.delta })
      expect(@other).not_to be_recorded
      expect(@other.compared).to eq(v1)
      expect(@other.changes.size).to be > 1
      expect(@other.counts.values.sum).to eq(@other.changes.size)
      expect(@other.recorded_counts).to eq(recorded.counts)
    end

    it "numbers versions in the order the stream received them" do
      viewer = described_class.new(v3)
      expect([ v1, v2, v3 ].map { |v| viewer.version_number(v) }).to eq([ 1, 2, 3 ])
    end

    it "refuses a version of another document or another boundary, falling back to the recorded comparison" do
      other_stream = received_doc(sample("vulnerability-detail-report.json"))
      other_boundary = received_doc(sample("#{sdr}.json"), into: create(:authorization_boundary))

      [ other_stream, other_boundary ].each do |foreign|
        viewer = described_class.new(v3, compare_to: foreign)
        expect(viewer.compared).to eq(v2)
        expect(viewer.versions).not_to include(foreign)
      end
    end

    it "lists a version that failed validation but never compares with it" do
      bad = JSON.parse(sample("#{sdr}.json")).except("fedRampRequirements")
      invalid = received_doc(JSON.generate(bad))
      viewer = described_class.new(v3, compare_to: invalid)

      expect(viewer.versions).to include(invalid)
      expect(viewer.comparable?(invalid)).to be(false)
      expect(viewer.compared).to eq(v2)
    end
  end

  describe "a first version" do
    it "has nothing to compare with" do
      doc = received_doc(sample("certification-package-overview.json"))
      viewer = described_class.new(doc)
      expect(viewer).not_to be_compared
      expect(viewer.changes).to be_empty
      expect(viewer).to be_viewable
    end
  end

  describe "a version that failed validation" do
    it "is compared on request with the version in effect, since none is recorded" do
      v1 = received_doc(sample("vulnerability-detail-report.json")).tap { |d| accept(d) }
      bad = JSON.parse(sample("vulnerability-detail-report.json"))
      bad["vulnerabilities"][0]["vulnerabilityDescription"] = "   "
      invalid = received_doc(JSON.generate(bad))

      viewer = described_class.new(invalid)
      expect(invalid.state).to eq("invalid")
      expect(viewer.compared).to eq(v1)
      expect(viewer).not_to be_recorded
    end
  end

  describe ".pointer_label" do
    it "labels fields and keeps identifiers and positions" do
      expect(described_class.pointer_label("/vulnerabilities/ECW-VULN-0013/currentRating"))
        .to eq("Vulnerabilities › ECW-VULN-0013 › Current rating (N)")
      expect(described_class.pointer_label("/portsAndProtocols/0/portNumber")).to eq("Ports and protocols › #1 › Port number")
      expect(described_class.pointer_label("")).to eq("The document")
    end
  end
end
