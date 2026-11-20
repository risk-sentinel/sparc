# frozen_string_literal: true

require "rails_helper"

# #1354 — completeness by the schema's own definitions: a required field must
# be filled in, not merely present.
RSpec.describe SchemaCompleteness do
  def check(schema, doc, **opts) = described_class.new(schema, **opts).check(doc)
  def pointers(findings) = findings.map(&:pointer)

  let(:schema) do
    {
      "type" => "object",
      "required" => %w[name contacts],
      "properties" => {
        "name" => { "type" => "string" },
        "nickname" => { "type" => "string" },
        "contacts" => { "type" => "array", "items" => { "$ref" => "#/$defs/contact" } },
        "everything" => { "type" => "object", "additionalProperties" => false },
        "note" => { "type" => %w[string null] }
      },
      "$defs" => {
        "contact" => { "type" => "object", "required" => %w[email], "properties" => { "email" => { "type" => "string" } } }
      }
    }
  end

  it "reports a required field that is only whitespace" do
    report = check(schema, { "name" => "  ", "contacts" => [] })
    expect(pointers(report.errors)).to eq([ "/name" ])
  end

  it "does not repeat a missing required field (the schema check reports it)" do
    expect(check(schema, { "contacts" => [] }).errors).to be_empty
  end

  it "follows $ref into array items" do
    report = check(schema, { "name" => "a", "contacts" => [ { "email" => "" }, { "email" => "x@example.com" } ] })
    expect(pointers(report.errors)).to eq([ "/contacts/0/email" ])
  end

  it "does not call an empty array blank: the schema's minItems decides" do
    expect(check(schema, { "name" => "a", "contacts" => [] }).errors).to be_empty
  end

  it "does not call an empty object blank when its schema gives it no fields" do
    schema["required"] << "everything"
    expect(check(schema, { "name" => "a", "contacts" => [], "everything" => {} }).errors).to be_empty
  end

  it "calls an empty object blank when its schema gives it fields" do
    schema["properties"]["owner"] = { "$ref" => "#/$defs/contact" }
    schema["required"] << "owner"
    expect(pointers(check(schema, { "name" => "a", "contacts" => [], "owner" => {} }).errors)).to eq([ "/owner" ])
  end

  it "allows null where the schema does" do
    schema["required"] << "note"
    expect(check(schema, { "name" => "a", "contacts" => [], "note" => nil }).errors).to be_empty
  end

  it "warns about optional fields only when asked to" do
    doc = { "name" => "a", "contacts" => [], "nickname" => "" }
    expect(check(schema, doc).warnings).to be_empty

    warned = check(schema, doc, warn_optional: true)
    expect(pointers(warned.warnings)).to include("/nickname", "/everything", "/note")
    expect(warned.warnings_total).to eq(warned.warnings.size)
  end

  it "applies the branch an if/then selects" do
    conditional = {
      "type" => "object",
      "properties" => { "kind" => { "type" => "string" }, "resolution" => { "type" => "string" } },
      "if" => { "properties" => { "kind" => { "const" => "final" } }, "required" => [ "kind" ] },
      "then" => { "required" => [ "resolution" ] }
    }
    expect(pointers(check(conditional, { "kind" => "final", "resolution" => "" }).errors)).to eq([ "/resolution" ])
    expect(check(conditional, { "kind" => "initial", "resolution" => "" }).errors).to be_empty
  end

  it "resolves OSCAL-style $id anchors" do
    oscal_style = {
      "definitions" => {
        "party" => { "$id" => "#party", "type" => "object", "required" => [ "name" ],
                     "properties" => { "name" => { "type" => "string" } } }
      },
      "type" => "object",
      "properties" => { "party" => { "$ref" => "#party" } }
    }
    expect(pointers(check(oscal_style, { "party" => { "name" => "" } }).errors)).to eq([ "/party/name" ])
  end

  it "resolves another document through the resolver" do
    other = { "$defs" => { "id" => { "type" => "object", "required" => [ "value" ],
                                     "properties" => { "value" => { "type" => "string" } } } } }
    root = { "type" => "object", "properties" => { "ref" => { "$ref" => "https://example.test/other.json#/$defs/id" } } }
    resolver = ->(uri) { uri.to_s == "https://example.test/other.json" ? other : raise("unexpected #{uri}") }
    expect(pointers(check(root, { "ref" => { "value" => " " } }, resolver: resolver).errors)).to eq([ "/ref/value" ])
  end

  it "escapes JSON Pointer tokens" do
    weird = { "type" => "object", "required" => [ "a/b" ], "properties" => { "a/b" => { "type" => "string" } } }
    expect(pointers(check(weird, { "a/b" => "" }).errors)).to eq([ "/a~1b" ])
  end
end
