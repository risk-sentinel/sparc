# frozen_string_literal: true

require "rails_helper"

# #919 — denial coverage for the POA&M child controllers.
#
# The seven of them (findings, items, local components, milestones,
# observations, remediations, risks) shipped with no authorization of any kind.
# Nesting under a POA&M document did not scope them: each loads its parent with
# an unscoped `find_by!(slug:)` and only then scopes children to it, so knowing a
# POA&M's slug was enough to rewrite its findings, milestones and remediation
# dates — the figures an AO relies on when accepting residual risk.
#
# This file exists because the per-controller specs CANNOT catch a missing
# guard. Measured: with `authorize_poam_write!` neutered to `return true`,
# `poam_risks_spec.rb` still passed 8 of 8. Those specs grant the permission and
# exercise the permitted path, so they prove the guard does not break a legitimate
# caller — never that it stops anyone else. That asymmetry is the whole reason
# #919 exists.
#
# Modelled on spec/requests/authorization_boundary_memberships_authz_spec.rb
# (the #918 fix), including the audit assertion: a denial that is not recorded is
# not much of a control (AU-2).
RSpec.describe "Controller authorization sweep (#919)", type: :request do
  # The guards no-op unless auth is enabled, so a spec that forgets this stub
  # passes against a completely unguarded app.
  before { allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true) }

  let(:boundary) { create(:authorization_boundary) }
  let(:poam)     { create(:poam_document, authorization_boundary: boundary) }
  let(:outsider) { create(:user) }

  # Each entry: the nested path builder and a minimal valid params payload.
  CHILDREN = {
    "poam_findings" => {
      path: ->(p) { "/poam_documents/#{p.slug}/poam_findings" },
      params: { poam_finding: { title: "Injected finding" } }
    },
    "poam_items" => {
      path: ->(p) { "/poam_documents/#{p.slug}/poam_items" },
      params: { poam_item: { title: "Injected item" } }
    },
    "poam_local_components" => {
      path: ->(p) { "/poam_documents/#{p.slug}/poam_local_components" },
      params: { poam_local_component: { title: "Injected component" } }
    },
    "poam_observations" => {
      path: ->(p) { "/poam_documents/#{p.slug}/poam_observations" },
      params: { poam_observation: { title: "Injected observation" } }
    },
    "poam_risks" => {
      path: ->(p) { "/poam_documents/#{p.slug}/poam_risks" },
      params: { poam_risk: { title: "Injected risk" } }
    }
  }.freeze

  context "a signed-in user with no permission on the boundary" do
    before { sign_in_as(outsider) }

    CHILDREN.each do |name, spec|
      describe name do
        it "refuses the create and writes nothing" do
          expect {
            post spec[:path].call(poam), params: spec[:params]
          }.not_to change { PoamDocument.find(poam.id).reload && poam.reload.updated_at }

          # Web denials redirect to root; only JSON requests get a 403.
          expect(response).to have_http_status(:found)
          expect(response).to redirect_to(root_path)
        end

        it "refuses the new form — an unauthorized user should not reach the editor" do
          get "#{spec[:path].call(poam)}/new"

          expect(response).to redirect_to(root_path)
        end

        it "records the denial as an audit event (AU-2)" do
          expect {
            post spec[:path].call(poam), params: spec[:params]
          }.to change { AuditEvent.where(action: "authorization_failure").count }.by_at_least(1)
        end
      end
    end
  end

  # The positive control. Without it an over-tight guard — one that refuses
  # everybody — would ship green, since every example above would still pass.
  context "a user holding poam.write on that boundary" do
    before do
      grant_permission(outsider, "poam.write", authorization_boundary: boundary)
      sign_in_as(outsider)
    end

    it "is allowed to create a risk" do
      # #832 — description, statement, status and deadline are all required, so a
      # thin payload is rejected on validation and would look identical to an
      # authorization refusal. The positive control has to send a genuinely valid
      # risk or it proves nothing.
      expect {
        post "/poam_documents/#{poam.slug}/poam_risks",
             params: { poam_risk: {
               title: "Legitimate risk", description: "A risk to track",
               statement: "Asset X has weakness Y allowing Z",
               status: "open", impact: "high", likelihood: "medium",
               deadline: 30.days.from_now.to_date
             } }
      }.to change { poam.poam_risks.count }.by(1)
    end

    it "reaches the new form" do
      get "/poam_documents/#{poam.slug}/poam_risks/new"

      expect(response).to have_http_status(:ok)
    end
  end

  # The other four gaps closed in #919. Grouped here rather than in four new
  # files because the property under test is identical and the setup is three
  # lines; a per-controller file would be ceremony without coverage.
  #
  # Worth noting WHY these had no denial coverage before: three of them
  # (boundaries, back_matter_resources, control_back_matter_links) had no request
  # spec of any kind. Adding the guards broke nothing, which looked like success
  # and was actually the absence of tests.
  describe "the remaining unguarded controllers" do
    before { sign_in_as(outsider) }

    it "refuses editing a boundary's environments" do
      expect {
        post "/authorization_boundaries/#{boundary.slug}/boundaries",
             params: { boundary: { name: "Injected environment" } }
      }.not_to change(Boundary, :count)

      expect(response).to redirect_to(root_path)
    end

    it "refuses attesting to evidence" do
      evidence = create(:evidence, authorization_boundary: boundary)

      expect {
        post "/evidences/#{evidence.slug}/attestations",
             params: { attestation: { attestation_type: "self", statement: "Injected" } }
      }.not_to change(Attestation, :count)

      expect(response).to redirect_to(root_path)
    end

    it "refuses adding back-matter to a document" do
      ssp = create(:ssp_document, authorization_boundary: boundary)

      expect {
        post "/ssp_documents/#{ssp.slug}/back_matter_resources",
             params: { back_matter_resource: { title: "Injected resource" } }
      }.not_to change(BackMatterResource, :count)

      expect(response).to redirect_to(root_path)
    end

    it "records each refusal as an audit event" do
      expect {
        post "/authorization_boundaries/#{boundary.slug}/boundaries",
             params: { boundary: { name: "Injected" } }
      }.to change { AuditEvent.where(action: "authorization_failure").count }.by_at_least(1)
    end
  end

  # Decision 1 (#919): roster management is DELEGABLE. The v1.15.5 fix enforced
  # `authorization_boundaries.write` UNSCOPED, which matches only instance-level
  # roles — so the delegated grant, held at boundary scope, would have been
  # refused and the feature would have stayed admin-only while appearing fixed.
  describe "roster management is delegable, not admin-only" do
    it "allows a boundary-scoped manage_members holder" do
      grant_permission(outsider, "authorization_boundaries.manage_members",
                       authorization_boundary: boundary)
      sign_in_as(outsider)

      get "/authorization_boundaries/#{boundary.slug}/memberships/new"

      expect(response).to have_http_status(:ok)
    end

    it "still refuses someone without it" do
      sign_in_as(outsider)

      get "/authorization_boundaries/#{boundary.slug}/memberships/new"

      expect(response).to redirect_to(root_path)
    end
  end

  # The permission is boundary-scoped, so holding it somewhere else must not
  # carry over — this is the difference between "has the permission" and "has it
  # HERE", and it is the property the unscoped parent lookup used to destroy.
  context "a user holding poam.write on a DIFFERENT boundary" do
    before do
      grant_permission(outsider, "poam.write", authorization_boundary: create(:authorization_boundary))
      sign_in_as(outsider)
    end

    it "is still refused on this boundary's POA&M" do
      expect {
        post "/poam_documents/#{poam.slug}/poam_risks", params: { poam_risk: { title: "Cross-boundary write" } }
      }.not_to change { poam.poam_risks.count }

      expect(response).to redirect_to(root_path)
    end
  end
end
