# frozen_string_literal: true

require "rails_helper"

# #1354 — a connection to another system's trust center: who it is, where SPARC
# pulls from, how it authenticates (credential encrypted at rest), and the
# trust pins ExchangeFetcher enforces.
RSpec.describe ExchangeConnection do
  let(:boundary) { create(:authorization_boundary) }

  def build_connection(**attrs) = build(:exchange_connection, authorization_boundary: boundary, **attrs)

  def errors_on(attribute, **attrs)
    connection = build_connection(**attrs)
    connection.validate
    connection.errors[attribute]
  end

  let(:pin_a) { "a" * 64 }
  let(:pin_b) { "b" * 64 }

  describe "validations" do
    it "is valid with a name, a boundary and an https root" do
      expect(build_connection).to be_valid
    end

    it "requires a unique name" do
      create(:exchange_connection, name: "Provider X", authorization_boundary: boundary)
      expect(errors_on(:name, name: "Provider X")).to include("has already been taken")
      expect(errors_on(:name, name: "")).to include("can't be blank")
    end

    it "allows no root address at all" do
      expect(build_connection(root_url: nil)).to be_valid
    end

    it "refuses a root that is not https, has no host, or carries a user name" do
      expect(errors_on(:root_url, root_url: "http://trust.provider.example/")).to include("must be an https:// address")
      expect(errors_on(:root_url, root_url: "ftp://trust.provider.example/")).to include("must be an https:// address")
      expect(errors_on(:root_url, root_url: "https://user:pw@trust.provider.example/")).to include("must be an https:// address")
      expect(errors_on(:root_url, root_url: "https:///nohost")).to include("must be an https:// address")
      expect(errors_on(:root_url, root_url: "https://exa mple.com/")).to include("is not a valid address")
    end

    describe "FedRAMP ID" do
      it "accepts GSA's forms and agency IDs" do
        %w[F2400000001 FR2400000001 FR2400000001AB AGENCYDHS01].each do |id|
          expect(build_connection(fedramp_id: id)).to be_valid, id
        end
      end

      it "upcases and strips before checking, and stores blank as nil" do
        connection = build_connection(fedramp_id: "  fr2400000001  ")
        expect(connection).to be_valid
        expect(connection.fedramp_id).to eq("FR2400000001")

        blank = build_connection(fedramp_id: "  ")
        expect(blank).to be_valid
        expect(blank.fedramp_id).to be_nil
      end

      it "refuses anything else" do
        %w[FR240000001 FX2400000001 2400000001 FR2400000001ABC].each do |id|
          expect(errors_on(:fedramp_id, fedramp_id: id)).to include("is not a FedRAMP ID (F or FR and ten digits)"), id
        end
      end
    end

    it "takes only the known certification classes and types" do
      expect(build_connection(certification_class: "B", certification_type: "20x")).to be_valid
      expect(build_connection(certification_class: "D", certification_type: "Rev5")).to be_valid
      expect(errors_on(:certification_class, certification_class: "E")).to be_present
      expect(errors_on(:certification_type, certification_type: "Rev4")).to be_present
      expect(build_connection(certification_class: "", certification_type: "")).to be_valid
    end

    it "takes only the known authentication schemes" do
      expect(errors_on(:auth_scheme, auth_scheme: "basic")).to be_present
    end

    it "requires a header name, of header characters, for the header scheme only" do
      expect(errors_on(:auth_header_name, auth_scheme: "header")).to include("can't be blank")
      expect(errors_on(:auth_header_name, auth_scheme: "header", auth_header_name: "X Api: Key")).to be_present
      expect(build_connection(auth_scheme: "header", auth_header_name: "X-Api-Key")).to be_valid
      expect(build_connection(auth_scheme: "bearer")).to be_valid
    end

    describe "TLS key pins" do
      it "holds at most two (the current key and the next)" do
        expect(build_connection(spki_sha256: [ pin_a, pin_b ])).to be_valid
        expect(errors_on(:spki_sha256, spki_sha256: [ pin_a, pin_b, "c" * 64 ]))
          .to include("holds at most 2 keys (the current one and the next)")
      end

      it "must be SHA-256 values in hex" do
        expect(errors_on(:spki_sha256, spki_sha256: [ "z" * 64 ]).first).to start_with("must be SHA-256 values in hex")
        expect(errors_on(:spki_sha256, spki_sha256: [ "a" * 63 ])).to be_present
      end

      it "normalises colon-separated, upper-case, space- or comma-separated input, and drops duplicates" do
        colon = ("AB" * 32).scan(/../).join(":")
        connection = build_connection(spki_sha256: [ "#{colon} #{pin_a}", "#{pin_a}," ])
        expect(connection).to be_valid
        expect(connection.spki_sha256).to eq([ "ab" * 32, pin_a ])
      end
    end

    describe "IP ranges" do
      it "accepts CIDR ranges and single addresses, split on spaces and commas" do
        connection = build_connection(allowed_cidrs: [ "203.0.113.0/24, 198.51.100.7", "2001:db8::/32" ])
        expect(connection).to be_valid
        expect(connection.allowed_cidrs).to eq([ "203.0.113.0/24", "198.51.100.7", "2001:db8::/32" ])
      end

      it "names a bad range" do
        expect(errors_on(:allowed_cidrs, allowed_cidrs: [ "203.0.113.0/24", "not-a-range" ]))
          .to include("has an invalid range: not-a-range")
        expect(errors_on(:allowed_cidrs, allowed_cidrs: [ "10.0.0.0/33" ])).to include("has an invalid range: 10.0.0.0/33")
      end
    end
  end

  describe "credential" do
    let(:secret) { "s3cr3t-bearer-value" }

    it "is encrypted at rest: the stored ciphertext never contains the plaintext" do
      connection = create(:exchange_connection, authorization_boundary: boundary, auth_scheme: "bearer", credential: secret)
      stored = ExchangeConnection.connection.select_value(
        ExchangeConnection.sanitize_sql([ "SELECT encrypted_credential FROM exchange_connections WHERE id = ?", connection.id ])
      )
      expect(stored).to be_present
      expect(stored).not_to include(secret)
      expect(stored).not_to include(Base64.strict_encode64(secret))
      expect(connection).to be_credential
    end

    it "round-trips through the database" do
      connection = create(:exchange_connection, authorization_boundary: boundary, credential: secret)
      expect(described_class.find(connection.id).credential).to eq(secret)
    end

    it "is cleared by a blank value" do
      connection = create(:exchange_connection, authorization_boundary: boundary, credential: secret)
      connection.update!(credential: "")
      expect(connection.reload.encrypted_credential).to be_nil
      expect(connection.credential).to be_nil
      expect(connection).not_to be_credential
    end

    it "reads as nil, not an exception, when the ciphertext is not SPARC's" do
      connection = create(:exchange_connection, authorization_boundary: boundary)
      connection.update_column(:encrypted_credential, "garbage--not-a-ciphertext")
      expect(connection.reload.credential).to be_nil
    end

    it "is encrypted under its own key purpose, not a federation peer's" do
      connection = create(:exchange_connection, authorization_boundary: boundary, credential: secret)
      peer_encryptor = FederationPeer.build_encryptor(FederationPeer::TOKEN_KEY_PURPOSE)
      expect { peer_encryptor.decrypt_and_verify(connection.encrypted_credential) }.to raise_error(StandardError)
    end

    describe "#request_headers" do
      it "sends nothing for the none scheme, even with a credential set" do
        expect(build_connection(auth_scheme: "none", credential: secret).request_headers).to eq({})
      end

      it "sends a bearer Authorization header" do
        expect(build_connection(auth_scheme: "bearer", credential: secret).request_headers)
          .to eq("Authorization" => "Bearer #{secret}")
      end

      it "sends the named header" do
        connection = build_connection(auth_scheme: "header", auth_header_name: "X-Api-Key", credential: secret)
        expect(connection.request_headers).to eq("X-Api-Key" => secret)
      end

      it "sends nothing when the scheme needs a credential and none is set" do
        expect(build_connection(auth_scheme: "bearer").request_headers).to eq({})
        expect(build_connection(auth_scheme: "header", auth_header_name: "X-Api-Key").request_headers).to eq({})
      end
    end
  end

  describe "#pinned_hosts" do
    it "is the hosts of the root and the registered documents, lower-cased, once each" do
      connection = create(:exchange_connection, authorization_boundary: boundary, root_url: "https://Trust.Provider.example/")
      create(:exchange_document_source, exchange_connection: connection, url: "https://trust.provider.example/a.json")
      create(:exchange_document_source, exchange_connection: connection, url: "https://CDN.provider.example/b.json")

      expect(connection.reload.pinned_hosts).to contain_exactly("trust.provider.example", "cdn.provider.example")
    end

    it "never includes a host from anywhere else (the stored allowed_hosts column is not consulted)" do
      connection = create(:exchange_connection, authorization_boundary: boundary)
      connection.update_column(:allowed_hosts, [ "elsewhere.example" ])
      expect(connection.reload.pinned_hosts).to eq([ "trust.provider.example" ])
    end

    it "is empty with no root and no documents" do
      expect(build_connection(root_url: nil).pinned_hosts).to eq([])
    end
  end

  describe "associations" do
    it "stops its boundary being destroyed while it exists" do
      connection = create(:exchange_connection, authorization_boundary: boundary)

      expect(boundary.destroy).to be(false)
      expect(boundary.errors.full_messages.join).to match(/exchange connections/i)
      expect(described_class.exists?(connection.id)).to be(true)
    end

    it "destroys its document sources and keeps its received versions" do
      connection = create(:exchange_connection, authorization_boundary: boundary)
      source = create(:exchange_document_source, exchange_connection: connection)
      version = create(:received_document, authorization_boundary: boundary, exchange_connection: connection,
                                           exchange_document_source: source, source: "pull")

      connection.destroy!

      expect(ExchangeDocumentSource.exists?(source.id)).to be(false)
      expect(version.reload.exchange_connection_id).to be_nil
    end
  end

  it ".enabled lists only enabled connections" do
    on = create(:exchange_connection, authorization_boundary: boundary)
    create(:exchange_connection, authorization_boundary: boundary, enabled: false)
    expect(described_class.enabled).to eq([ on ])
  end
end
