# frozen_string_literal: true

# #860 — turn a refused grant into the thing an administrator would go and make.
#
# The grant already says exactly what is missing, so asking an administrator to
# read a slug out of an error message and retype it into a form is work SPARC
# can do for them — and retyping is where the mismatch creeps in, because the
# record has to end up with the slug the IdP is asking for, not merely a
# similar name.
#
# The hint therefore carries the SLUG it must produce alongside the suggested
# name, so the administrator can see the two agree before saving.
class UnmatchedGrantResolutionHint
  Hint = Struct.new(:kind, :label, :suggested_name, :required_slug, :path, keyword_init: true)

  def initialize(raw_grant)
    @grant = IdpGrant.parse(raw_grant.to_s)
  end

  # nil when the grant is malformed, or when what it names already exists — in
  # which case the refusal was a conflict or a scope mismatch, and creating
  # something new is the wrong advice.
  def hint
    return nil if @grant.nil? || !@grant.valid?

    missing_organization || missing_boundary || missing_role
  end

  private

  def missing_organization
    slug = @grant.organization_slug
    return nil if slug.blank? || Organization.exists?(slug: slug)

    Hint.new(kind: :organization, label: "Create organization",
             suggested_name: humanize(slug), required_slug: slug,
             path: "/admin/organizations/new?name=#{CGI.escape(humanize(slug))}")
  end

  def missing_boundary
    slug = @grant.boundary_slug
    return nil if slug.blank? || AuthorizationBoundary.exists?(slug: slug)

    organization = Organization.find_by(slug: @grant.organization_slug)
    # The organization has to exist first, or the boundary form has nothing to
    # attach to. missing_organization above already offered that step.
    return nil if organization.nil?

    Hint.new(kind: :authorization_boundary, label: "Create boundary",
             suggested_name: humanize(slug), required_slug: slug,
             path: "/authorization_boundaries/new?name=#{CGI.escape(humanize(slug))}" \
                   "&organization_id=#{organization.id}")
  end

  def missing_role
    name = @grant.role_name
    return nil if name.blank? || Role.exists?(name: name)

    Hint.new(kind: :role, label: "Create role", suggested_name: name, required_slug: name,
             path: "/admin/roles/new?name=#{CGI.escape(name)}")
  end

  # "acme-prod" -> "Acme Prod". Round-trips through parameterize back to the
  # same slug for ordinary names, which is the whole point — but the caller is
  # shown `required_slug` regardless, because a name like "R&D" does not.
  def humanize(slug) = slug.to_s.tr("-", " ").split.map(&:capitalize).join(" ")
end
