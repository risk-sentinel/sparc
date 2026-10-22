# frozen_string_literal: true

require "rails_helper"

# #1259 — an instance administrator's edit to a built-in role, made in Admin ->
# Roles or through /api/v1/roles, survives the roles seed section. Both
# surfaces record the administrator's choices through the same model method
# (Role#record_admin_choices); these specs drive each surface end to end and
# then run the section (BuiltInRoleSeeder, which is the whole of its body in
# db/seeds.rb).
RSpec.describe "Built-in role overrides (#1259)", type: :request do
  let(:admin)     { create(:user, :admin) }
  let(:non_admin) { create(:user) }

  before do
    allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true)
    allow(SparcConfig).to receive(:enable_local_login?).and_return(true)
    BuiltInRoleSeeder.call
  end

  def role(name) = Role.find_by!(name: name)

  def run_roles_section = BuiltInRoleSeeder.call

  # The web form submits every checkbox that is ticked; an unticked one is
  # absent. Starting from what the role holds keeps the edit to one key.
  def form_permissions(role, changes = {})
    granted = Role::PERMISSION_KEYS.select { |key| role.has_permission?(key) }.to_h { |key| [ key, "1" ] }
    changes.each { |key, value| value ? granted[key] = "1" : granted.delete(key) }
    granted
  end

  def web_update(role, attrs = {}, permissions: {})
    patch admin_role_path(role), params: {
      role: { display_name: role.display_name, scope: role.scope, sort_order: role.sort_order,
              description: role.description }.merge(attrs)
              .merge(permissions: form_permissions(role, permissions))
    }
  end

  def api_headers(user)
    { "Authorization" => "Bearer #{ApiToken.generate!(user: user, name: 'T').plaintext_token}" }
  end

  def api_update(role, user: admin, **body)
    patch api_v1_role_path(role), params: { role: body }, headers: api_headers(user), as: :json
  end

  def api_permissions(role, changes = {})
    Role::PERMISSION_KEYS.to_h { |key| [ key, role.has_permission?(key) ] }.merge(changes)
  end

  describe "web: Admin -> Roles" do
    before { sign_in_as(admin) }

    it "keeps an administrator's grant through a roles-section run" do
      web_update(role("view_only"), permissions: { "ssp.write" => true })
      expect(response).to redirect_to(admin_role_path(role("view_only")))

      run_roles_section

      expect(role("view_only").has_permission?("ssp.write")).to be(true)
      expect(role("view_only").admin_overrides.keys).to eq([ "ssp.write" ])
    end

    it "keeps an administrator's revoke through a roles-section run" do
      web_update(role("isso"), permissions: { "ssp.write" => false })

      run_roles_section

      expect(role("isso").has_permission?("ssp.write")).to be(false)
    end

    it "keeps an administrator's display name through a roles-section run" do
      web_update(role("view_only"), { display_name: "Read-only Reviewer" })

      run_roles_section

      expect(role("view_only").display_name).to eq("Read-only Reviewer")
    end

    it "records nothing for a save that leaves every value at its default" do
      web_update(role("isso"))

      expect(role("isso").admin_overrides).to eq({})
    end

    it "resets a key to its default, after which the shipped default applies again" do
      web_update(role("view_only"), permissions: { "ssp.write" => true })
      web_update(role("view_only"), permissions: { "ssp.write" => false }) # Reset to default, saved

      expect(role("view_only").admin_overrides).to eq({})
      # With the override released, the seeds own the key again.
      r = role("view_only")
      r.update!(permissions: r.permissions.merge("ssp.write" => true))
      run_roles_section
      expect(role("view_only").has_permission?("ssp.write")).to be(false)
    end

    it "audits the overrides a save leaves in place" do
      web_update(role("view_only"), permissions: { "ssp.write" => true })

      event = AuditEvent.where(action: "role_updated").last
      expect(event.metadata["admin_overrides"]).to eq([ "ssp.write" ])
    end

    it "marks a value that differs from the shipped default and offers to reset it" do
      web_update(role("view_only"), permissions: { "ssp.write" => true })

      get edit_admin_role_path(role("view_only"))

      expect(response.body).to include(%(data-controller="role-defaults"))
      page = Nokogiri::HTML(response.body)
      marker = page.at_css("[data-testid='role-default-marker-ssp.write']")
      reset = page.at_css("[data-testid='role-default-reset-ssp.write']")
      expect(marker["hidden"]).to be_nil
      expect(reset["data-action"]).to eq("role-defaults#reset")
      expect(marker.ancestors("[data-role-defaults-target='field']").first["data-role-defaults-shipped-value"])
        .to eq("false")
      # A value at its default carries the (hidden) control only.
      expect(page.at_css("[data-testid='role-default-marker-ssp.read']")["hidden"]).not_to be_nil
      expect(response.body).not_to match(/\son[a-z]+=/i) # CSP: no inline handlers

      get admin_role_path(role("view_only"))
      expect(Nokogiri::HTML(response.body).at_css("[data-testid='role-default-marker-ssp.write']")).to be_present
      expect(Nokogiri::HTML(response.body).at_css("[data-testid='role-default-marker-ssp.read']")).to be_nil
    end

    it "shows no default markers on a role an administrator created" do
      custom = create(:role, name: "custom_reviewer", display_name: "Custom", permissions: { "ssp.write" => true })

      get admin_role_path(custom)
      expect(response.body).not_to include("role-default-marker")

      get edit_admin_role_path(custom)

      expect(response.body).not_to include("role-default-marker")
      expect(response.body).not_to include(%(data-controller="role-defaults"))
    end

    it "refuses a user who is not an instance administrator, and records nothing" do
      sign_in_as(non_admin)

      web_update(role("view_only"), permissions: { "ssp.write" => true })

      expect(response).to redirect_to(root_path)
      expect(role("view_only").has_permission?("ssp.write")).to be(false)
      expect(role("view_only").admin_overrides).to eq({})
    end
  end

  describe "API: /api/v1/roles" do
    it "keeps an administrator's grant through a roles-section run" do
      api_update(role("view_only"), permissions: api_permissions(role("view_only"), "ssp.write" => true))
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig("data", "admin_overrides")).to eq([ "ssp.write" ])

      run_roles_section

      expect(role("view_only").has_permission?("ssp.write")).to be(true)
    end

    it "keeps an administrator's revoke through a roles-section run" do
      api_update(role("isso"), permissions: api_permissions(role("isso"), "ssp.write" => false))

      run_roles_section

      expect(role("isso").has_permission?("ssp.write")).to be(false)
    end

    it "keeps an administrator's description through a roles-section run" do
      api_update(role("view_only"), description: "Local wording.")

      run_roles_section

      expect(role("view_only").description).to eq("Local wording.")
    end

    it "does not reconsider permissions on an update that sent none" do
      # A value away from its default that nobody chose: a release whose roles
      # section has not run yet looks like this.
      r = role("view_only")
      r.update!(permissions: r.permissions.merge("ssp.write" => true))

      api_update(role("view_only"), sort_order: 77)

      expect(role("view_only").admin_overrides.keys).to eq([ "sort_order" ])
    end

    it "records nothing on a role an administrator created" do
      custom = create(:role, name: "custom_reviewer", display_name: "Custom")

      api_update(custom, permissions: { "ssp.write" => true }, display_name: "Custom Two")

      expect(response).to have_http_status(:ok)
      expect(custom.reload.admin_overrides).to eq({})
      expect(response.parsed_body.dig("data", "admin_overrides")).to eq([])
    end

    it "releases a key set back to its shipped default" do
      api_update(role("view_only"), permissions: api_permissions(role("view_only"), "ssp.write" => true))
      api_update(role("view_only"), permissions: api_permissions(role("view_only"), "ssp.write" => false))

      expect(role("view_only").admin_overrides).to eq({})
    end

    it "reports the shipped defaults and the overrides of a built-in role" do
      api_update(role("view_only"), permissions: api_permissions(role("view_only"), "ssp.write" => true))

      get api_v1_role_path(role("view_only")), headers: api_headers(admin)

      data = response.parsed_body["data"]
      expect(data["built_in"]).to be(true)
      expect(data["admin_overrides"]).to eq([ "ssp.write" ])
      expect(data.dig("shipped_defaults", "permissions")).to include("ssp.read")
      expect(data.dig("shipped_defaults", "permissions")).not_to include("ssp.write")
      expect(data.dig("shipped_defaults", "display_name")).to eq("View Only")
    end

    it "reports no shipped defaults for a role an administrator created" do
      custom = create(:role, name: "custom_reviewer", display_name: "Custom")

      get api_v1_role_path(custom), headers: api_headers(admin)

      expect(response.parsed_body.dig("data", "built_in")).to be(false)
      expect(response.parsed_body.dig("data", "shipped_defaults")).to be_nil
    end

    it "refuses a user who is not an instance administrator, and records nothing" do
      api_update(role("view_only"), user: non_admin,
                 permissions: api_permissions(role("view_only"), "ssp.write" => true))

      expect(response).to have_http_status(:forbidden)
      expect(role("view_only").has_permission?("ssp.write")).to be(false)
      expect(role("view_only").admin_overrides).to eq({})
    end
  end
end
