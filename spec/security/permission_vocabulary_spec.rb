# frozen_string_literal: true

require "rails_helper"

# #919 — the second structural guard: keep the permission VOCABULARY honest.
#
# The controller sweep found 13 unguarded controllers. Auditing the vocabulary
# that backs those guards found something broader — 13 of 35 keys (37%) were
# anomalous:
#
#   * 11 were enforced by code but granted to NO role. Because
#     User#has_permission? returns true for admins, that silently made
#     back-matter authoring, promotion and catalog/profile/CDEF approval
#     admin-only out of the box. Nobody decided it; it fell out of the seeds.
#   * `converters.read` was granted to 7 roles and enforced by nothing —
#     advertising an access boundary that did not exist.
#   * `authorization_boundaries.manage_members` was documented in wiki/RBAC.md,
#     granted to nobody and enforced nowhere: the published RBAC documentation
#     described a capability the application did not implement.
#
# Each of those is invisible to a scanner and to any test that exercises a
# permitted path. They are only visible by DIFFING the four places a permission
# has to agree: defined, enforced, documented, granted.
#
# This spec covers the three STATIC dimensions. The fourth — what the seeds
# actually grant — needs the database and is pinned separately in
# spec/security/seeded_permission_grants_spec.rb.
#
# NIST 800-53: AC-3 (access enforcement), AC-6 (least privilege),
# CM-6 (configuration settings — the role catalog is configuration).
RSpec.describe "Permission vocabulary consistency (#919)" do
  # A key is "enforced" if it appears as a string literal anywhere under app/ —
  # in an authorize_permission! call, a boundary_scoped declaration, or a service
  # doing its own check. Intentionally broad: the question is whether any code
  # consults the key at all, not which helper it used.
  let(:app_source) do
    Dir.glob(Rails.root.join("app/**/*.rb")).map { |f| File.read(f) }.join("\n")
  end

  let(:defined_keys) { Role::PERMISSION_KEYS.sort }

  # Only rows of the permission table — `| `key` | description |` — so a key
  # mentioned in prose (explaining a removal, say) does not count as documenting
  # a live permission.
  let(:documented_keys) do
    File.read(Rails.root.join("wiki/RBAC.md"))
        .scan(/^\|\s*`([a-z_]+\.[a-z_]+)`\s*\|/).flatten.uniq.sort
  end

  it "defines only well-formed resource.action keys" do
    malformed = defined_keys.reject { |k| k.match?(/\A[a-z_]+\.[a-z_]+\z/) }

    expect(malformed).to be_empty,
      "PERMISSION_KEYS is a %w[] array, so a stray comment or typo becomes a KEY " \
      "rather than being ignored. Malformed entries: #{malformed.inspect}"
  end

  it "enforces every key it defines" do
    unenforced = defined_keys.reject { |k| app_source.include?(%("#{k}")) }

    expect(unenforced).to be_empty, <<~MSG
      These permission keys are defined but no code consults them:

        #{unenforced.join("\n  ")}

      A key that grants nothing is worse than no key, because the role catalog
      implies an access boundary that does not exist — an operator granting it
      believes they have restricted something. Either enforce it, or remove it
      (as #919 did with converters.read).
    MSG
  end

  it "documents every key it defines" do
    undocumented = defined_keys - documented_keys

    expect(undocumented).to be_empty,
      "Defined but missing from the wiki/RBAC.md permission table, so operators " \
      "cannot know the capability exists: #{undocumented.inspect}"
  end

  it "defines every key it documents" do
    phantom = documented_keys - defined_keys

    expect(phantom).to be_empty, <<~MSG
      wiki/RBAC.md documents permissions the application does not have:

        #{phantom.join("\n  ")}

      This is the `manage_members` failure in reverse and it is the more
      dangerous direction — published RBAC documentation describing a capability
      that does not exist. An assessor reading it cannot tell.
    MSG
  end

  # The specific keys #919 resolved. Named so a revert is loud rather than
  # merely returning the aggregate checks above to a state they once accepted.
  describe "the #919 resolutions hold" do
    it "converters.read stays removed" do
      expect(defined_keys).not_to include("converters.read"),
        "converters.read was removed in #919: any authenticated user may read " \
        "converters, so the absence of a check is correct and the key advertised " \
        "a restriction that did not exist. Re-adding it needs a real enforcement point."
    end

    it "authorization_boundaries.manage_members is defined AND enforced" do
      expect(defined_keys).to include("authorization_boundaries.manage_members")
      expect(app_source).to include(%("authorization_boundaries.manage_members")),
        "manage_members was documented, granted to nobody and enforced nowhere. " \
        "#919 wired it to the roster surfaces; if this fails, the published RBAC " \
        "documentation is describing a capability the app no longer implements."
    end
  end
end
