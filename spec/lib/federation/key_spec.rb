# frozen_string_literal: true

require "rails_helper"
require "open3"

# #1161 — the Ruby reference implementation of the UUIDv5 object-key grammar,
# asserted against the shared vectors.
#
# The vectors are read rather than restated. A spec that hard-coded its own
# expectations would prove the port self-consistent and say nothing about
# AGREEMENT, which is the only property the file exists to have: identifiers are
# exchanged between instances, so two implementations disagreeing is a silent
# data-integrity fault rather than a bug someone notices.
RSpec.describe Federation::Key do
  let(:spec_data) { JSON.parse(File.read(described_class::GRAMMAR_PATH)) }

  describe "the registered namespace" do
    it "is no longer provisional" do
      expect(spec_data.dig("namespace", "provisional")).to be false
    end

    it "is the UUIDv5 of the registered URI, recomputed rather than repeated" do
      recomputed = Digest::UUID.uuid_v5(Digest::UUID::URL_NAMESPACE, OscalNamespace.uri(:sparc))

      expect(described_class.namespace).to eq(recomputed)
      expect(described_class.namespace).to eq(OscalNamespace::FEDERATION_NAMESPACE)
    end

    it "uses the unit separator, not a printable delimiter" do
      expect(described_class.separator).to eq("\x1f")
    end
  end

  describe "the published vectors" do
    it "derives every vector's uuid" do
      failures = spec_data["vectors"].filter_map do |v|
        got = described_class.derive(v["kind"], v["args"])
        "#{v['name']}: expected #{v['uuid']} got #{got}" unless got == v["uuid"]
      end

      expect(failures).to be_empty, failures.join("\n")
    end

    # The field lists must GENERATE the published fields, not merely land on a
    # matching UUID — that is what makes the declaration the source of truth.
    it "reproduces every vector's canonical fields from the declared field lists" do
      failures = spec_data["vectors"].filter_map do |v|
        got = described_class.canonical_fields(v["kind"], v["args"])
        "#{v['name']}:\n  expected #{v['canonical-fields'].inspect}\n  got      #{got.inspect}" unless got == v["canonical-fields"]
      end

      expect(failures).to be_empty, failures.join("\n")
    end

    it "covers all nine object kinds" do
      expect(described_class.kinds.sort).to eq(spec_data["vectors"].map { |v| v["kind"] }.uniq.sort)
    end

    it "has vectors to check, so the assertions above cannot be vacuous" do
      expect(spec_data["vectors"].length).to be >= 26
    end
  end

  describe "the declared relations" do
    it "holds every assertion in the file" do
      by_name = spec_data["vectors"].index_by { |v| v["name"] }

      failures = spec_data["assertions"].filter_map do |assertion|
        uuids = assertion["vectors"].map { |n| described_class.derive(by_name[n]["kind"], by_name[n]["args"]) }

        case assertion["relation"]
        when "distinct" then "#{assertion['name']}: expected distinct, got #{uuids.inspect}" unless uuids.uniq.length == uuids.length
        when "same"     then "#{assertion['name']}: expected identical, got #{uuids.inspect}" unless uuids.uniq.one?
        else "#{assertion['name']}: unknown relation #{assertion['relation'].inspect}"
        end
      end

      expect(failures).to be_empty, failures.join("\n")
    end
  end

  describe "join ambiguity" do
    it "gives ('a|b','c') and ('a','b|c') different uuids" do
      derived = spec_data["join-cases"].map do |c|
        input = spec_data["grammar"] + described_class.separator + c["fields"].join(described_class.separator)
        got = Digest::UUID.uuid_v5(described_class.namespace, input)
        expect(got).to eq(c["uuid"]), "#{c['name']}: expected #{c['uuid']} got #{got}"
        got
      end

      expect(derived.uniq.length).to eq(derived.length)
    end
  end

  describe "rejections" do
    it "refuses every case the file declares must be refused" do
      failures = spec_data["rejections"].filter_map do |r|
        described_class.derive(r["kind"], r["args"])
        "#{r['name']}: was NOT rejected — #{r['why']}"
      rescue Federation::Key::MissingField, Federation::Key::InvalidField, Federation::Key::SeparatorInField
        nil
      rescue StandardError => e
        "#{r['name']}: wrong error #{e.class}: #{e.message}"
      end

      expect(failures).to be_empty, failures.join("\n")
    end

    it "rejects an unknown object kind rather than deriving something" do
      expect { described_class.derive("not-a-kind", {}) }.to raise_error(Federation::Key::UnknownKind)
    end
  end

  # The single most consequential rule, and the one a reimplementation gets
  # wrong silently: 23 of the 26 vectors carry a `vocabulary` that is never
  # hashed, and it decides whether the control identifier may be canonicalised.
  describe "vocabulary governs normalisation" do
    let(:base) do
      { "parent-ssp-uuid" => "3fa85f64-5717-4562-b3fc-2c963f66afa6",
        "source-uuid" => "b7e21d90-4c1a-4f55-9e33-0a6d2c118f44",
        "component-uuid" => "9f1c0f4e-2b7a-4d61-8f52-1c9a3b7d4e60",
        "period" => "2026-Q3" }
    end

    it "never hashes the vocabulary itself" do
      fields = described_class.canonical_fields("observation", base.merge("vocabulary" => "nist-sp800-53", "control-id" => "cp-4"))

      expect(fields).not_to include("nist-sp800-53")
    end

    it "converges NIST spellings on one identifier" do
      a = described_class.derive("observation", base.merge("vocabulary" => "nist-sp800-53", "control-id" => "AC-2 (1)"))
      b = described_class.derive("observation", base.merge("vocabulary" => "nist-sp800-53", "control-id" => "ac-2.1"))

      expect(a).to eq(b)
    end

    it "keeps an opaque identifier's case, so ACM.1 and acm.1 stay two objects" do
      upper = described_class.derive("observation", base.merge("vocabulary" => "opaque", "control-id" => "ACM.1"))
      lower = described_class.derive("observation", base.merge("vocabulary" => "opaque", "control-id" => "acm.1"))

      expect(upper).not_to eq(lower)
    end

    it "requires a vocabulary rather than defaulting to NIST" do
      expect { described_class.derive("observation", base.merge("control-id" => "cp-4")) }
        .to raise_error(Federation::Key::MissingField, /vocabulary is required/)
    end

    it "uses SPARC's own canonicaliser for the NIST form" do
      expect(ControlId.canonical("AC-2 (1)")).to eq("ac-2.1")
    end
  end

  describe "unicode" do
    it "treats composed and decomposed forms as one object" do
      base = { "parent-ssp-uuid" => "3fa85f64-5717-4562-b3fc-2c963f66afa6",
               "source-uuid" => "b7e21d90-4c1a-4f55-9e33-0a6d2c118f44",
               "component-uuid" => "9f1c0f4e-2b7a-4d61-8f52-1c9a3b7d4e60",
               "period" => "2026-Q3", "vocabulary" => "opaque" }

      composed   = described_class.derive("observation", base.merge("control-id" => "étape"))
      decomposed = described_class.derive("observation", base.merge("control-id" => "étape"))

      expect(composed).to eq(decomposed)
    end
  end

  # The property the whole artifact exists to have. Three independent
  # implementations of a hashing grammar WILL disagree eventually; this is the
  # thing that catches it, and it runs both runtimes for real rather than
  # comparing each against its own expectations.
  describe "cross-runtime agreement with the Python port" do
    it "derives identical uuids for every vector" do
      script = <<~PYTHON
        import json, sys
        sys.path.insert(0, #{Rails.root.join('lib/federation/python').to_s.dump})
        from sparc_federation import key as K
        spec = json.loads(K.GRAMMAR_PATH.read_text())
        print(json.dumps({v["name"]: K.derive(v["kind"], v["args"]) for v in spec["vectors"]}))
      PYTHON

      stdout, status = Open3.capture2e("python3", "-c", script)
      skip "python3 unavailable in this environment" unless status.success?

      python_uuids = JSON.parse(stdout.lines.last)
      ruby_uuids = spec_data["vectors"].to_h { |v| [ v["name"], described_class.derive(v["kind"], v["args"]) ] }

      expect(python_uuids).to eq(ruby_uuids)
      expect(python_uuids.length).to eq(spec_data["vectors"].length)
    end
  end
end
