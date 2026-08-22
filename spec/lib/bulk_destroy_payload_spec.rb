# frozen_string_literal: true

require "rails_helper"

# #1018 — the parser exists so "nothing to do" and "I did not understand you"
# stop sharing a response. Both halves are asserted: a malformed body is
# refused, and an EMPTY array still succeeds, because that distinction is the
# entire reason the class exists.
RSpec.describe BulkDestroyPayload do
  def parse(hash)
    described_class.parse(ActionController::Parameters.new(hash))
  end

  describe "bodies it accepts" do
    it "accepts an array of integer ids" do
      payload = parse(ids: [ 1, 2, 3 ])

      expect(payload).to be_valid
      expect(payload.ids).to eq([ 1, 2, 3 ])
    end

    it "accepts an array of string ids, which is what JSON clients send" do
      payload = parse(ids: %w[abc def])

      expect(payload).to be_valid
      expect(payload.ids).to eq(%w[abc def])
    end

    it "accepts an EMPTY array — that genuinely is nothing to do" do
      payload = parse(ids: [])

      expect(payload).to be_valid
      expect(payload.ids).to eq([])
    end
  end

  describe "bodies it refuses" do
    it "refuses a missing `ids` key, which is the defect this was filed for" do
      payload = parse(a_field_this_endpoint_does_not_accept: "x")

      expect(payload).not_to be_valid
      expect(payload.errors.join).to match(/`ids` is required/)
    end

    it "refuses an object where an array is expected, naming what it received" do
      payload = parse(ids: { "1" => true })

      expect(payload).not_to be_valid
      expect(payload.errors.join).to match(/must be an ARRAY/)
      expect(payload.errors.join).to match(/an object/)
    end

    it "refuses a bare string" do
      payload = parse(ids: "1,2,3")

      expect(payload).not_to be_valid
      expect(payload.errors.join).to match(/a string/)
    end

    it "refuses an array containing something that is not an id" do
      payload = parse(ids: [ 1, { "nested" => "object" } ])

      expect(payload).not_to be_valid
      expect(payload.errors.join).to match(/only record ids/)
      expect(payload.ids).to eq([]), "a refused payload must not carry a partial id list"
    end
  end

  it "quotes back the shape it expects, as data rather than prose" do
    expect(described_class::EXPECTED).to eq(ids: [ "string-or-integer" ])
  end
end
