# frozen_string_literal: true

require "rails_helper"

# #1100 — the statements table rendered a Responsible Roles column that no screen
# could write. Owner review: "Not sure why Responsible Roles is not able to be
# edited or why it is there if I cannot edit it."
#
# `update_statement` had permitted `responsible_roles_data` all along; nothing
# ever sent it, because no form offered the field. That permit is
# `responsible_roles_data: []` — a bare array of SCALARS — so the first thing to
# send it would have stored `["isso"]`, and `OscalSspExportService` writes this
# column straight into the document's `responsible-roles`, where the OSCAL schema
# requires objects carrying a `role-id`.
#
# The inline editor therefore sends role ids and the controller builds the shape.
#
# ── Updated for #1116 ──────────────────────────────────────────────────────
#
# The editor now PICKS from declared roles instead of accepting free text, and
# the controller REFUSES an id that resolves to no declared role. `isso` — the
# value these examples originally used — is exactly the defect #1116 names: it
# mints a private id for a role NIST already defines as
# `information-system-security-officer`, producing a document that validates
# cleanly and whose reference resolves to nothing.
#
# So the ids here change to declared ones, and a new example asserts the refusal.
# This is strictly stronger than before: the shape is still asserted, and the
# document can no longer reach a referentially broken state at all.
RSpec.describe "SSP statement responsible roles", type: :request do
  let(:user)     { create(:user, :admin) }
  let(:document) { create(:ssp_document) }
  let(:control)  { document.ssp_controls.create!(control_id: "ac-1", title: "Policy") }
  let(:statement) do
    control.ssp_control_statements.create!(statement_id: "ac-1_smt", row_order: 0,
                                           uuid: SecureRandom.uuid)
  end

  before { sign_in_as(user) }

  def update_roles(value)
    patch update_statement_ssp_document_path(document),
          params: { statement_id: statement.id,
                    ssp_control_statement: { responsible_role_ids: value } }
  end

  it "stores role ids as OSCAL objects, not bare strings" do
    update_roles([ "system-owner", "information-system-security-officer" ])

    expect(statement.reload.responsible_roles_data)
      .to eq([ { "role-id" => "system-owner" },
               { "role-id" => "information-system-security-officer" } ])
  end

  # The #1116 guarantee: a document cannot reach a broken state through this
  # path. Refused at the WRITE, not merely reported at export.
  it "refuses a role id that resolves to no declared role" do
    update_roles([ "isso" ])

    expect(response).to have_http_status(:unprocessable_content)
    expect(JSON.parse(response.body)["error"]).to match(/not declared/)
    expect(statement.reload.responsible_roles_data).to eq([])
  end

  it "still accepts a comma-separated string, for a pre-#1116 shaped caller" do
    update_roles("system-owner, information-system-security-officer")

    expect(statement.reload.responsible_roles_data.map { |r| r["role-id"] })
      .to eq(%w[system-owner information-system-security-officer])
  end

  # The point of the shape: what lands in the exported document must be what the
  # OSCAL schema expects. A bare string array is the failure this guards.
  it "exports those roles as OSCAL responsible-roles" do
    update_roles([ "information-system-security-officer" ])

    raw = OscalSspExportService.new(document.reload).export_unvalidated
    doc = raw.is_a?(String) ? JSON.parse(raw) : raw.deep_stringify_keys

    statements = doc.dig("system-security-plan", "control-implementation",
                         "implemented-requirements")
                    .flat_map { |ir| Array(ir["statements"]) }
    expect(statements).not_to be_empty, "the export produced no statements to carry roles"

    roles = statements.filter_map { |s| s["responsible-roles"] }.flatten
    expect(roles).to include("role-id" => "information-system-security-officer")
  end

  it "tolerates spacing and drops empties" do
    update_roles("  system-owner ,, information-system-security-officer ,  ")

    expect(statement.reload.responsible_roles_data.map { |r| r["role-id"] })
      .to eq(%w[system-owner information-system-security-officer])
  end

  it "clears the roles when the field is emptied" do
    statement.update!(responsible_roles_data: [ { "role-id" => "system-owner" } ])

    update_roles("")

    expect(statement.reload.responsible_roles_data).to eq([])
  end

  # Sending no roles field at all must leave what is stored alone — the editor
  # is one form among several that PATCH this action.
  it "leaves stored roles untouched when the field is not submitted" do
    statement.update!(responsible_roles_data: [ { "role-id" => "system-owner" } ])

    patch update_statement_ssp_document_path(document),
          params: { statement_id: statement.id,
                    ssp_control_statement: { implementation_prose: "prose only" } }

    expect(statement.reload.responsible_roles_data).to eq([ { "role-id" => "system-owner" } ])
    expect(statement.implementation_prose).to eq("prose only")
  end
end
