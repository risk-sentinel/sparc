# frozen_string_literal: true

require "rails_helper"

# #942 — the owner-specified construction rule for `{{ insert: param, <id> }}`.
RSpec.describe OscalParameterResolver do
  # AC-20 verbatim from the Rev 5 catalog. Two levels: the statement references
  # odp.01, whose CHOICES reference odp.02 / odp.03.
  let(:params) do
    [
      { "id" => "ac-20_odp.01",
        "select" => { "how-many" => "one-or-more",
                      "choice" => [ "establish {{ insert: param, ac-20_odp.02 }} ",
                                    "identify {{ insert: param, ac-20_odp.03 }} " ] } },
      { "id" => "ac-20_odp.02",
        "label" => "terms and conditions",
        "guidelines" => [ { "prose" => "terms and conditions consistent with the trust relationships " \
                                       "established with other organizations owning, operating, and/or " \
                                       "maintaining external systems are defined (if selected);" } ] },
      { "id" => "ac-20_odp.03",
        "label" => "controls asserted",
        "guidelines" => [ { "prose" => "controls asserted to be implemented on external systems consistent " \
                                       "with the trust relationships established with other organizations " \
                                       "owning, operating, and/or maintaining external systems are defined " \
                                       "(if selected);" } ] }
    ]
  end

  let(:statement) do
    "{{ insert: param, ac-20_odp.01 }} , consistent with the trust relationships established with " \
    "other organizations owning, operating, and/or maintaining external systems, allowing " \
    "authorized individuals to:"
  end

  def resolver(values = {}) = described_class.new(params, values)

  # The exact string the owner specified, assembled from both selected branches.
  describe "the construction rule" do
    it "assembles both selected branches into the statement" do
      both = ParameterValueList.join([ "establish {{ insert: param, ac-20_odp.02 }}",
                                       "identify {{ insert: param, ac-20_odp.03 }}" ])

      expect(resolver("ac-20_odp.01" => both).resolve_text(statement)).to eq(
        "establish terms and conditions consistent with the trust relationships established with " \
        "other organizations owning, operating, and/or maintaining external systems are defined " \
        "(if selected); identify controls asserted to be implemented on external systems consistent " \
        "with the trust relationships established with other organizations owning, operating, and/or " \
        "maintaining external systems are defined (if selected); , consistent with the trust " \
        "relationships established with other organizations owning, operating, and/or maintaining " \
        "external systems, allowing authorized individuals to:"
      )
    end

    # Each branch keeps its own verb; only the reference inside it is replaced.
    it "keeps the choice's own wording around the substituted reference" do
      one = ParameterValueList.join([ "establish {{ insert: param, ac-20_odp.02 }}" ])

      expect(resolver("ac-20_odp.01" => one).resolve_text(statement))
        .to start_with("establish terms and conditions consistent with")
    end

    it "assembles only the branches actually selected" do
      one = ParameterValueList.join([ "identify {{ insert: param, ac-20_odp.03 }}" ])
      result = resolver("ac-20_odp.01" => one).resolve_text(statement)

      expect(result).to start_with("identify controls asserted")
      expect(result).not_to include("establish terms and conditions")
    end

    # Substituting odp.01 yields text that still contains a reference. A single
    # pass would leave "establish {{ insert: param, ac-20_odp.02 }}" standing.
    it "resolves recursively rather than in one pass" do
      one = ParameterValueList.join([ "establish {{ insert: param, ac-20_odp.02 }}" ])

      expect(resolver("ac-20_odp.01" => one).resolve_text(statement)).not_to include("insert: param")
    end
  end

  describe "precedence for a value parameter" do
    it "prefers the operator's set value over the catalog wording" do
      expect(resolver("ac-20_odp.02" => "our negotiated terms")
               .resolve_text("establish {{ insert: param, ac-20_odp.02 }}"))
        .to eq("establish our negotiated terms")
    end

    it "falls back to the guidelines prose, not the terse label" do
      expect(resolver.resolve_text("establish {{ insert: param, ac-20_odp.02 }}"))
        .to eq("establish terms and conditions consistent with the trust relationships established " \
               "with other organizations owning, operating, and/or maintaining external systems are " \
               "defined (if selected);")
    end

    it "falls back to the label when there is no guidelines prose" do
      bare = described_class.new([ { "id" => "x_odp.01", "label" => "a frequency" } ])

      expect(bare.resolve_text("at {{ insert: param, x_odp.01 }}")).to eq("at a frequency")
    end

    # A gap in the catalog must look like a gap. Blanking it produces prose that
    # reads as finished but has had a requirement quietly removed.
    it "leaves the markup standing when the parameter is unknown" do
      text = "at {{ insert: param, nowhere_odp.99 }}"

      expect(resolver.resolve_text(text)).to eq(text)
    end
  end

  describe "a selection with nothing chosen" do
    # Rendering nothing would silently delete the requirement from the prose.
    it "falls back to the options so the choice is still visible" do
      result = resolver.resolve_text(statement)

      expect(result).to include("establish terms and conditions")
      expect(result).to include("identify controls asserted")
    end
  end

  describe "safety" do
    it "does not recurse forever on a parameter cycle" do
      cyclic = [
        { "id" => "a", "guidelines" => [ { "prose" => "{{ insert: param, b }}" } ] },
        { "id" => "b", "guidelines" => [ { "prose" => "{{ insert: param, a }}" } ] }
      ]

      expect {
        Timeout.timeout(5) { described_class.new(cyclic).resolve_text("{{ insert: param, a }}") }
      }.not_to raise_error
    end

    it "returns blank text unchanged" do
      expect(resolver.resolve_text("")).to eq("")
      expect(resolver.resolve_text(nil)).to eq("")
    end
  end

  # #1241 — a catalog that ASSIGNS a parameter carries it in `values`. Order:
  # a set value (SSP or profile), then the catalog's values, then aggregate,
  # guidelines and label. Values are invented.
  describe "the catalog's own values (#1241)" do
    let(:params) do
      [
        { "id" => "ex-01_odp.01", "label" => "personnel or roles",
          "guidelines" => [ { "prose" => "personnel or roles are defined;" } ],
          "values" => [ "Example Agency personnel" ] },
        { "id" => "ex-01_odp.02", "label" => "personnel or roles", "values" => [ "Example auditors" ] },
        { "id" => "ex-1_prm_1", "label" => "organization-defined personnel or roles",
          "props" => [ { "name" => "aggregates", "ns" => "http://csrc.nist.gov/ns/rmf", "value" => "ex-01_odp.01" },
                       { "name" => "aggregates", "ns" => "http://csrc.nist.gov/ns/rmf", "value" => "ex-01_odp.02" } ] },
        { "id" => "ex-01_odp.03",
          "select" => { "how-many" => "one-or-more", "choice" => [ "organization-level", "system-level" ] },
          "values" => [ "system-level" ] },
        { "id" => "ex-01_odp.04",
          "select" => { "how-many" => "one", "choice" => [ "daily", "weekly" ] } }
      ]
    end

    it "uses the catalog's value when nothing is set, ahead of guidelines and label" do
      expect(resolver.resolve_param("ex-01_odp.01")).to eq("Example Agency personnel")
    end

    it "lets a set value win over the catalog's" do
      expect(resolver("ex-01_odp.01" => "Invented ISSO").resolve_param("ex-01_odp.01")).to eq("Invented ISSO")
    end

    it "resolves an aggregate from its parts' catalog values" do
      expect(resolver.resolve_param("ex-1_prm_1")).to eq("Example Agency personnel, Example auditors")
    end

    it "prefers a set part over that part's catalog value inside an aggregate" do
      expect(resolver("ex-01_odp.02" => "Invented assessors").resolve_param("ex-1_prm_1"))
        .to eq("Example Agency personnel, Invented assessors")
    end

    it "takes a select's catalog values instead of listing every choice" do
      expect(resolver.resolve_param("ex-01_odp.03")).to eq("system-level")
    end

    it "still lists every choice for a select nobody answered" do
      expect(resolver.resolve_param("ex-01_odp.04")).to eq("daily weekly")
    end

    it "lets a set selection win over the catalog's" do
      expect(resolver("ex-01_odp.03" => "organization-level").resolve_param("ex-01_odp.03")).to eq("organization-level")
    end
  end
end
