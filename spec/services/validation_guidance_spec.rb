# frozen_string_literal: true

require "rails_helper"

# #1390 part G — each error of a version that failed validation says where it
# is, what is wrong and what the provider needs to send, from FedRAMP's own
# schema. Driven by the sample package's invalid variants
# (samples/fedramp-package-demo/invalid), whose manifest lists the exact error
# each must produce.
#
# NIST SP 800-53: SI-10, CA-2.
RSpec.describe ValidationGuidance do
  let(:boundary) { create(:authorization_boundary) }

  def received_doc(file)
    ReceivedDocumentService.call(boundary: boundary, bytes: File.read(Rails.root.join("samples/fedramp-package-demo/invalid", file)), source: "upload",
                                 filename: file, content_type: "application/json", received_by: nil).document
  end

  def item_for(file) = described_class.new(received_doc(file)).items.first

  it "explains a blank required field, with what the schema says the field is" do
    item = item_for("vdr-blank-required-field.json")
    expect(item.check).to eq("completeness")
    expect(item.location).to eq("/vulnerabilities/ECW-VULN-0012/vulnerabilityDescription")
    expect(item.label).to eq("Vulnerabilities › ECW-VULN-0012 › Vulnerability description")
    expect(item.wrong).to eq("Vulnerability description is blank.")
    expect(item.needed).to end_with("FedRAMP's schema requires it.")
    expect(item.message).to eq("required field is blank")
  end

  it "lists the allowed values for a value outside them" do
    item = item_for("cpo-bad-enum.json")
    expect(item.wrong).to eq("Certification type is “Rev6”, which is not an allowed value.")
    expect(item.needed).to start_with("One of: 20x, Rev5.")
  end

  it "names a missing required field" do
    item = item_for("sdr-missing-required-field.json")
    expect(item.wrong).to eq("The document is missing FedRAMP requirements.")
    expect(item.needed).to end_with("FedRAMP's schema requires it.")
  end

  it "says what type a value must be" do
    item = item_for("ocr-wrong-type.json")
    expect(item.wrong).to eq("Active agencies is text, not a list.")
    expect(item.needed).to start_with("A list.")
  end

  it "gives an example of a valid date-time" do
    item = item_for("incident-bad-date-time.json")
    expect(item.wrong).to eq("Detected at is “2026-09-14 03:20”, which is not a valid date-time.")
    expect(item.needed).to eq("A date-time value, for example 2026-11-23T14:00:00Z.")
  end

  it "keeps the validator's own message for a document SPARC could not read" do
    doc = ReceivedDocumentService.call(boundary: boundary, bytes: '{"oops": ', source: "upload", filename: "x.json",
                                       format: "fedramp", received_by: nil).document
    item = described_class.new(doc).items.first
    expect(doc.state).to eq("invalid")
    expect(item.check).to eq("readable")
    expect(item.wrong).to eq(item.message)
    expect(item.needed).to be_nil
  end
end
