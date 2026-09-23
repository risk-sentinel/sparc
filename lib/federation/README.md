# Federation object-key grammar

The UUIDv5 grammar every object identity in the federation is derived under, its
reference implementations, and the vectors all three runtimes assert against.

`key-grammar.v1.json` is the **source of truth**. Ruby, Python and Go build keys
by reading it, so the field lists exist once rather than three times.

| File | What it is |
| --- | --- |
| `key-grammar.v1.json` | The grammar: namespace, field lists, types, normalisers, dedup rule, vectors |
| `key.rb` | Ruby reference implementation (`Federation::Key`) |
| `python/` | Python reference implementation (`sparc_federation`), its own package |

## The grammar

```
namespace  = 9f434272-f796-589b-b972-954790395630      (registered, #1155)
grammar    = "v1"
uuid(obj)  = uuidv5(namespace, grammar + "\x1f" + join(fields(obj), "\x1f"))
```

The namespace is **derived, not invented** — `uuidv5(url, "https://sparc.risk-sentinel.org/ns")` —
so any peer recomputes it from the namespace URI rather than being told it.

## Four details that decide whether two runtimes agree

Each one is a place a reimplementation drifts *without failing*, so each is pinned
by vectors:

1. **The separator is `\x1f`, not a printable character.** With `|`, the tuples
   `("a|b","c")` and `("a","b|c")` produce identical input and therefore identical
   UUIDs. An implementation **rejects** a field containing the separator rather
   than escaping it — an escape sequence is itself a value a field could contain.
2. **The grammar version is part of the hashed input.** A field-list change
   changes every identifier derived under it, which is as breaking as changing the
   namespace. A grammar change is a v2, never an edit to v1.
3. **The vocabulary decides how a scoped identifier is normalised, per
   identifier kind.** `vocabulary-normalisers` is keyed by vocabulary and then
   by the field's type:

   | | `control-id` | `family-id` |
   |---|---|---|
   | `nist-sp800-53` | canonicalised via `ControlId.canonical` | lowercased |
   | `opaque` | unchanged | unchanged |

   A NIST *family* is merely lowercased, not canonicalised as a control id —
   it is not one, and claiming otherwise is a rule the grammar cannot support.
   Under an opaque vocabulary neither is touched: `ACM.1` and `acm.1` are two
   AWS Security Hub controls, and `ACM` and `acm` two Security Hub families,
   not two spellings of one.

   The vocabulary is **never hashed** — it is context — and it is **required**,
   because guessing NIST would fold a foreign identifier into something that
   validates and names nothing.

   **`family-id` was lowercased unconditionally until sparc#1175.** Every
   family vector used a NIST family, where lowercasing and the scoped rule
   agree, so no vector caught it and the two runtimes derived different
   identifiers for the same projection cell with neither erroring. The vectors
   now cover a foreign family in both cases.
4. **Strings are NFC, with no trimming and no case folding** beyond the
   normaliser named for the field. Ruby and Python differ from Go by default, so
   each port does it explicitly.

## What an object UUID means

**An object UUID identifies a thing, not an assertion about a thing.** The
asserting party is never folded into the key — that is what lets two peers
recognise the same object without coordinating.

The cost is that the grammar is public and the namespace shared, so **any peer
can compute any boundary's identifiers**. Determinism is being used as an
addressing scheme, and addressing needs an owner. So deduplication scopes on
the pair **(object UUID, originating party)**, and two parties asserting one
UUID is a **conflict to surface, never a duplicate to collapse** — keeping one
silently is the failure mode whichever one it keeps (#1159).

The originating party must come from bundle **verification**, not from the
payload: a party asserted inside a document it also signs is the same claim
twice, not a second fact.

## Running the checks

```bash
bundle exec rspec spec/lib/federation/key_spec.rb        # Ruby, incl. cross-runtime agreement
cd lib/federation/python && PYTHONPATH=. pytest tests    # Python
```

The Ruby spec **runs the Python port for real** and compares every UUID. Three
independent implementations of a hashing grammar will disagree eventually; that
comparison is the thing which catches it.

## Provenance, and the Horizon side

The vectors originated in `risk-sentinel/sparc-horizon`,
`fixtures/key-vectors.v1.json`, and were adopted here on 2026-09-21 (#1161).
SPARC is now the source of truth and Horizon consumes this file.

Two things changed in the adoption:

- **Every UUID was regenerated.** The upstream file derived them from the
  provisional namespace `d051648c-1ae1-569e-8569-b679a9aaf142`, taken from the
  placeholder URI `https://risk-sentinel.org/ns/sparc`. The registered URI is
  SPARC's, so the namespace — and therefore every identifier — differs.
  Horizon's own `docs/03-data-model.md` anticipated this regeneration.
- **The field lists became machine-readable.** Upstream they were *implied* by
  each vector's `canonical-fields`. Here they are declared, and every
  `canonical-fields` in the file is regenerated from that declaration, so the
  rule and the vectors cannot drift apart.

The normative prose remains Horizon's `docs/03-data-model.md`, section
*Deterministic UUIDs*. Where this file and that document disagree, that document
is the specification and this one has a bug.

## Scope

Nothing in SPARC derives object UUIDs through these ports yet. They are
reference implementations and their vectors; wiring the grammar into
attestations, observations and findings is separate work with its own migration
posture.
