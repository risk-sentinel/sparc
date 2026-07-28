# frozen_string_literal: true

require "rails_helper"

# #830 — every blob SPARC stores used to land in a flat namespace with a random
# key, so a user avatar, an SSP upload, a scan result and a WORM-retained
# evidence artifact were indistinguishable and belonged to no visible tenant.
#
# The acceptance criterion that matters most is the one these specs lead with:
# prefix-scoped IAM must become possible, which means a policy scoped to one
# organization or boundary can read that scope and NOTHING else.
RSpec.describe StorageKeyService do
  let(:organization) { create(:organization, name: "Acme Corp") }
  let(:boundary)     { create(:authorization_boundary, name: "Cloud ATO", organization: organization) }

  def key_for(record, name: :file, token: "tok123")
    described_class.key_for(record: record, name: name, token: token)
  end

  describe "the acceptance criterion: prefix-scoped IAM" do
    it "puts one organization's artifacts under a single prefix" do
      other_org = create(:organization, name: "Globex")
      other_boundary = create(:authorization_boundary, name: "Other ATO", organization: other_org)

      ours   = key_for(create(:evidence, authorization_boundary: boundary))
      theirs = key_for(create(:evidence, authorization_boundary: other_boundary))

      expect(ours).to start_with("org/acme-corp/")
      expect(theirs).to start_with("org/globex/")
      # The whole point: a policy on one prefix cannot reach the other.
      expect(theirs).not_to start_with("org/acme-corp/")
    end

    it "nests boundary inside organization, so either scope is one prefix" do
      key = key_for(create(:evidence, authorization_boundary: boundary))

      expect(key).to start_with("org/acme-corp/boundary/cloud-ato/")
    end

    it "never writes to the bucket root" do
      records = [
        create(:evidence, authorization_boundary: boundary),
        create(:ssp_document, authorization_boundary: boundary),
        create(:scan_run, authorization_boundary: boundary),
        create(:user)
      ]

      records.each do |record|
        name = record.is_a?(User) ? :avatar : :file
        expect(key_for(record, name: name)).to include("/"), "#{record.class} landed at the root"
      end
    end
  end

  describe "artifact classes are separable for lifecycle and retention" do
    it "distinguishes evidence from an uploaded document" do
      evidence = key_for(create(:evidence, authorization_boundary: boundary))
      ssp      = key_for(create(:ssp_document, authorization_boundary: boundary))

      expect(evidence).to include("/evidence/")
      expect(ssp).to include("/documents/ssp/")
    end

    it "keys each boundary-scoped document type separately" do
      {
        SarDocument => "/documents/sar/", SapDocument => "/documents/sap/",
        PoamDocument => "/documents/poam/"
      }.each do |klass, expected|
        record = create(klass.name.underscore.to_sym, authorization_boundary: boundary)
        expect(key_for(record)).to include(expected)
      end
    end

    # A CdefDocument links to MANY boundaries through a join table and belongs
    # to an organization; a ProfileDocument is a shared baseline with neither.
    # Filing either under one boundary's prefix would lie about ownership, so
    # they get an org-level `shared` tier that an org-scoped IAM policy still
    # covers while a boundary-scoped one correctly does not.
    describe "shared, org-owned artifacts" do
      it "puts an organization's CDEF under org/<org>/shared" do
        cdef = create(:cdef_document, organization: organization)

        key = key_for(cdef)
        expect(key).to start_with("org/acme-corp/shared/")
        expect(key).to include("/documents/cdef/")
        expect(key).not_to include("/boundary/")
      end

      it "is reachable by an org-scoped policy but not a boundary-scoped one" do
        cdef = create(:cdef_document, organization: organization)
        evidence = create(:evidence, authorization_boundary: boundary)

        expect(key_for(cdef)).to start_with("org/acme-corp/")
        expect(key_for(evidence)).to start_with("org/acme-corp/boundary/cloud-ato/")
        expect(key_for(cdef)).not_to start_with("org/acme-corp/boundary/")
      end

      it "falls back to instance/unscoped when there is no organization either" do
        expect(key_for(create(:cdef_document, organization: nil))).to start_with("instance/unscoped/")
      end
    end

    it "separates scan runs" do
      expect(key_for(create(:scan_run, authorization_boundary: boundary))).to include("/scans/")
    end
  end

  describe "artifacts with no boundary have an explicit documented home" do
    it "puts a user avatar under instance/users, not the root" do
      user = create(:user)

      key = key_for(user, name: :avatar)
      expect(key).to eq("instance/users/#{user.id}/avatar/tok123")
    end

    it "puts a boundary-less document under instance/unscoped rather than the root" do
      key = key_for(create(:ssp_document, authorization_boundary: nil))

      expect(key).to start_with("instance/unscoped/")
    end
  end

  describe "artifact versions" do
    let(:evidence) { create(:evidence, authorization_boundary: boundary) }

    # Nested under the evidence so "everything for this artifact" is one prefix,
    # while a per-version Object Lock rule can still target a single immutable
    # copy — which is what copy-per-version mode exists to enable.
    it "nests under the evidence it versions" do
      version = ArtifactVersion.create!(evidence: evidence, fingerprint: SecureRandom.hex(8))

      key = key_for(version, name: :content)
      expect(key).to start_with("org/acme-corp/boundary/cloud-ato/evidence/")
      expect(key).to include("/versions/#{version.id}/")
    end

    it "shares the evidence prefix, so one policy covers artifact and versions" do
      version = ArtifactVersion.create!(evidence: evidence, fingerprint: SecureRandom.hex(8))

      evidence_prefix = key_for(evidence).rpartition("/").first
      expect(key_for(version, name: :content)).to start_with(evidence_prefix)
    end
  end

  describe "keys are derived and reproducible" do
    it "produces the same path for the same record" do
      evidence = create(:evidence, authorization_boundary: boundary)

      first  = key_for(evidence, token: "a")
      second = key_for(evidence, token: "b")

      expect(first.rpartition("/").first).to eq(second.rpartition("/").first)
    end

    it "keeps the unguessable token as the leaf" do
      # Structure buys IAM scoping; the token keeps that from costing
      # confidentiality where a proxy trusts the key.
      key = key_for(create(:evidence, authorization_boundary: boundary), token: "secret-token")

      expect(key).to end_with("/secret-token")
    end
  end

  describe "path safety" do
    it "slugifies names that would otherwise break IAM policies and CLI args" do
      messy_org = create(:organization, name: "Acme / Corp & Sons (Ltd.)")
      messy_boundary = create(:authorization_boundary, name: "Prod  ATO!", organization: messy_org)

      key = key_for(create(:evidence, authorization_boundary: messy_boundary))

      expect(key).to match(%r{\Aorg/[a-z0-9._-]+/boundary/[a-z0-9._-]+/}), key
      expect(key).not_to include(" ")
      expect(key).not_to include("//")
    end

    # Exercised against the slug directly. Going through a factory cannot test
    # this — an AuthorizationBoundary named ".." fails its own slug validation
    # and never persists, so the earlier version of this spec proved nothing.
    it "cannot be made to traverse out of its prefix" do
      hostile = [ "../../etc", "..", "../", "a/../../b", "....//....//", "/absolute/path" ]

      hostile.each do |value|
        produced = described_class.send(:slug, value)
        next if produced.nil? # rejected outright is also a pass

        expect(produced).not_to include(".."), "#{value.inspect} produced #{produced.inspect}"
        expect(produced).not_to include("/"), "#{value.inspect} produced #{produced.inspect}"
        expect(produced).not_to start_with("."), "#{value.inspect} produced #{produced.inspect}"
      end
    end

    it "strips a path separator rather than letting it create a segment" do
      # This is the invariant traversal actually depends on: no caller-supplied
      # value can introduce a "/" and therefore a new path segment.
      expect(described_class.send(:slug, "acme/../../root")).not_to include("/")
    end
  end

  describe "SPARC_STORAGE_PREFIX" do
    around do |example|
      original = ENV["SPARC_STORAGE_PREFIX"]
      example.run
      original.nil? ? ENV.delete("SPARC_STORAGE_PREFIX") : ENV["SPARC_STORAGE_PREFIX"] = original
    end

    it "prepends a deployment prefix when a bucket is shared between instances" do
      ENV["SPARC_STORAGE_PREFIX"] = "staging"

      expect(key_for(create(:evidence, authorization_boundary: boundary))).to start_with("staging/org/")
    end

    it "is absent by default" do
      ENV.delete("SPARC_STORAGE_PREFIX")

      expect(key_for(create(:evidence, authorization_boundary: boundary))).to start_with("org/")
    end
  end
end
