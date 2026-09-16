# frozen_string_literal: true

require "rails_helper"

# #1134 — the one place a boundary-membership role becomes a DECLARED OSCAL
# role. The import, the API and the migration all go through it.
RSpec.describe OscalMetadata, "#declare_membership_roles" do
  let(:ssp) { create(:ssp_document) }

  it "maps each membership role to the role-id it declares" do
    ids = ssp.declare_membership_roles(%w[isso ciso isso])

    expect(ids).to eq("isso" => "information-system-security-officer", "ciso" => "ciso")
  end

  it "declares each new role once, keeping the defaults" do
    ssp.declare_membership_roles(%w[ciso assessor ciso])

    expect(ssp.declared_role_ids).to eq(OscalRole::SSP_DEFAULT_IDS + %w[ciso assessor])
  end

  it "assigns nothing when every role is already declared" do
    ssp.declare_membership_roles(%w[system_owner authorizing_official])

    expect(ssp.metadata_extra.to_h).not_to have_key("roles")
  end

  it "ignores blank membership roles" do
    expect(ssp.declare_membership_roles([ nil, "" ])).to eq({})
  end

  # A document imported at a version we ship no dataset for must not push every
  # NIST-named role onto organization-defined.
  it "resolves against the default vocabulary when the document's version has no dataset" do
    ssp.update_columns(oscal_version: "1.0.0")
    expect(OscalRole.suggested_ids("1.0.0")).to be_empty # precondition, or this example is vacuous

    ids = ssp.declare_membership_roles(%w[isso])

    expect(ids).to eq("isso" => "information-system-security-officer")
    expect(ssp.metadata_extra.to_h).not_to have_key("roles")
  end
end
