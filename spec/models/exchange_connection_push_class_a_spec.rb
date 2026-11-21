# frozen_string_literal: true

require "rails_helper"

# #1354 — a connection's pinned push keys and its Class A certification.
RSpec.describe ExchangeConnection do
  let(:key) { OpenSSL::PKey.generate_key("ED25519") }
  let(:raw_b64) { Base64.strict_encode64(key.raw_public_key) }
  let(:connection) { create(:exchange_connection) }

  describe "push keys" do
    it "stores a pasted PEM key as the base64 of its 32 raw bytes" do
      connection.update!(push_public_keys: [ key.public_to_pem ])

      expect(connection.push_public_keys).to eq([ raw_b64 ])
      expect(connection).to be_push_enabled
    end

    it "takes two PEM keys pasted in one box, and base64 keys one per line" do
      other = OpenSSL::PKey.generate_key("ED25519")
      connection.update!(push_public_keys: [ "#{key.public_to_pem}\n#{other.public_to_pem}" ])
      expect(connection.push_public_keys.size).to eq(2)

      connection.update!(push_public_keys: [ "#{raw_b64}\n#{raw_b64}" ])
      expect(connection.push_public_keys).to eq([ raw_b64 ])
    end

    it "refuses a third key, and a key that is not Ed25519" do
      three = Array.new(3) { Base64.strict_encode64(OpenSSL::PKey.generate_key("ED25519").raw_public_key) }
      connection.push_public_keys = three
      expect(connection).not_to be_valid
      expect(connection.errors[:push_public_keys].join).to include("at most 2")

      rsa = OpenSSL::PKey::RSA.new(2048)
      connection.push_public_keys = [ rsa.public_to_pem ]
      expect(connection).not_to be_valid
      expect(connection.errors[:push_public_keys].join).to include("Ed25519")

      connection.push_public_keys = [ Base64.strict_encode64("short") ]
      expect(connection).not_to be_valid
    end

    it "takes no pushes without a key, or while disabled" do
      expect(connection).not_to be_push_enabled
      connection.update!(push_public_keys: [ raw_b64 ], enabled: false)
      expect(connection).not_to be_push_enabled
    end

    it "names a key by a short SHA-256 fingerprint of its raw bytes" do
      expect(described_class.key_fingerprint(raw_b64)).to eq(Digest::SHA256.hexdigest(key.raw_public_key).first(16))
      expect(described_class.key_fingerprint("not base64!")).to be_nil
    end
  end

  describe "Class A" do
    let(:class_a) { create(:exchange_connection, certification_class: "A") }

    it "expires 12 months after the certification date (FRC-CLA-ASF)" do
      class_a.update!(class_a_framework: "soc2_type2", class_a_certified_on: Date.new(2026, 3, 15))

      expect(class_a.class_a_expires_on).to eq(Date.new(2027, 3, 15))
      expect(class_a).to be_class_a_recorded
      expect(class_a.class_a_framework_label).to eq("SOC 2 Type II")
    end

    it "is expired on and after its expiry date, with the days left before it" do
      class_a.update!(class_a_framework: "govramp", class_a_certified_on: Date.new(2025, 11, 21))

      expect(class_a.class_a_expired?(Date.new(2026, 11, 20))).to be(false)
      expect(class_a.class_a_days_left(Date.new(2026, 11, 20))).to eq(1)
      expect(class_a.class_a_expired?(Date.new(2026, 11, 21))).to be(true)
    end

    it "needs a date with a framework, a known framework, and no future date" do
      class_a.class_a_framework = "fedramp_rev5"
      expect(class_a).not_to be_valid
      expect(class_a.errors[:class_a_certified_on]).to be_present

      class_a.assign_attributes(class_a_framework: "iso27001", class_a_certified_on: Date.current)
      expect(class_a).not_to be_valid

      class_a.assign_attributes(class_a_framework: "fedramp_ready", class_a_certified_on: Date.current + 1)
      expect(class_a.errors.tap { class_a.valid? }[:class_a_certified_on].join).to include("future")
    end

    it "is recorded only on a Class A connection" do
      connection.update(certification_class: "B", class_a_framework: "soc2_type2", class_a_certified_on: Date.current)

      expect(connection.errors[:class_a_framework].join).to include("only for a Class A")
    end

    it "drops the Class A record when the connection moves to another class" do
      class_a.update!(class_a_framework: "soc2_type2", class_a_certified_on: Date.new(2026, 3, 15))

      class_a.update!(certification_class: "B", class_a_framework: "soc2_type2", class_a_certified_on: Date.new(2026, 3, 15))

      expect(class_a.reload).to have_attributes(class_a_framework: nil, class_a_certified_on: nil, class_a_expires_on: nil)
    end

    it "is not recorded until both framework and date are set" do
      expect(class_a).not_to be_class_a_recorded
      expect(class_a.class_a_expires_on).to be_nil
      expect(class_a).not_to be_class_a_expired
    end
  end
end
