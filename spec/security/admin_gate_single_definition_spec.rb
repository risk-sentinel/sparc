# frozen_string_literal: true

require "rails_helper"

# #1044 — the authority check may have exactly ONE definition.
#
# Four API controllers — organizations, service_accounts, roles and api_tokens,
# four of the most sensitive endpoints in the app — each carried a private
# `authorize_admin!` that SHADOWED the shared one in concerns/authorization.rb.
# Editing the shared gate silently missed all four.
#
# That is not a tidiness problem. #1044 adds an `instance.administer` permission
# to this gate so an IdP can grant a time-boxed administrator; had the copies
# survived, the permission would have opened 21 controllers and not those four —
# a half-open door, which is worse than a closed one because it looks like it
# works.
#
# The copies existed only to change the REFUSAL WORDING. That is why the concern
# exposes `admin_required_message` as the override point: a controller can say
# something more specific without owning a copy of the authority logic. This spec
# is what stops the next one from being written.
RSpec.describe "the admin authority gate has one definition" do
  it "is defined only in concerns/authorization.rb" do
    definitions = Dir.glob(Rails.root.join("app/**/*.rb")).sort.filter_map do |path|
      next unless File.read(path).match?(/^\s*def authorize_admin!/)

      path.sub("#{Rails.root}/", "")
    end

    expect(definitions).to eq([ "app/controllers/concerns/authorization.rb" ]), <<~MSG
      `authorize_admin!` must have exactly one definition. Found #{definitions.size}:

        #{definitions.join("\n  ")}

      A second definition SHADOWS the shared gate, so a change to the authority
      check silently skips that controller. To change only the refusal wording,
      override `admin_required_message` instead.
    MSG
  end

  it "lets a controller change the wording without owning the authority check" do
    expect(Api::V1::OrganizationsController.new.send(:admin_required_message))
      .to eq("Not authorized to manage organizations")
    expect(Api::V1::RolesController.new.send(:admin_required_message))
      .to eq("Not authorized to manage roles")
  end

  it "falls back to a generic message for controllers that do not override it" do
    expect(Api::V1::UsersController.new.send(:admin_required_message))
      .to eq("Admin access required")
  end
end
