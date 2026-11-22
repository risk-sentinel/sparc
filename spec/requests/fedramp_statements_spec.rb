# frozen_string_literal: true

require "rails_helper"

# #1390 — the boundary's FedRAMP page (FedrampStatementsController), the
# FedRAMP switch on the boundary, and what it hides until it is on.
RSpec.describe "Boundary FedRAMP page", type: :request do
  let(:boundary) { create(:authorization_boundary, :fedramp) }
  let(:page_path) { fedramp_authorization_boundary_path(boundary) }

  def user_with(permissions, on: boundary)
    user = create(:user)
    role = create(:role, :authorization_boundary_scoped, permissions: permissions)
    create(:user_role, user: user, role: role, authorization_boundary_id: on.id)
    user
  end

  def html = Nokogiri::HTML(response.body)

  before { allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true) }

  describe "GET the page" do
    it "lists the rules that apply to the profile, with their force, and the KSI count" do
      sign_in_as(user_with({ "evidence.read" => true }))
      get page_path
      expect(response).to have_http_status(:ok)
      rules = html.css("[data-testid='fedramp-entry']").map { |e| e["data-fedramp-rule"] }
      expect(rules).to match_array(boundary.fedramp_applicable_rules.map(&:id))
      expect(html.at_css("[data-testid='fedramp-tab-ksi']").text).to include("(46)")
      expect(html.at_css("[data-testid='fedramp-entry-form']")).to be_nil # read-only without evidence.write
    end

    it "lists the KSIs, with their controls" do
      sign_in_as(create(:user, :admin))
      get page_path, params: { kind: "ksi" }
      entry = html.at_css("[data-fedramp-rule='KSI-CED-RAT']")
      expect(entry.text).to include("Reviewing All Training", "at-2")
      expect(entry.at_css("textarea[name='fedramp_statement[tests_text]']")).to be_present
    end

    it "asks for the profile when it is incomplete" do
      boundary.update!(fedramp_package: { certification_class: "" })
      sign_in_as(create(:user, :admin))
      get page_path
      expect(html.at_css("[data-testid='fedramp-profile-incomplete']")).to be_present
      expect(html.css("[data-testid='fedramp-entry']")).to be_empty
    end

    it "sends the boundary back, saying why, while FedRAMP is off" do
      boundary.update!(fedramp_enabled: false)
      sign_in_as(create(:user, :admin))
      get page_path
      expect(response).to redirect_to(authorization_boundary_path(boundary))
      expect(flash[:error]).to include("FedRAMP is not enabled")
    end

    it "refuses a user without evidence.read on the boundary" do
      sign_in_as(user_with({ "evidence.read" => true }, on: create(:authorization_boundary)))
      get page_path
      expect(response).to redirect_to(root_path)
    end
  end

  describe "PATCH a statement" do
    let(:writer) { user_with({ "evidence.read" => true, "evidence.write" => true }) }
    let(:rule_id) { "SDR-CSO-FRR" }

    it "records it, audits it, counts up the SDR version and returns to the rule" do
      sign_in_as(writer)
      expect {
        patch fedramp_statement_authorization_boundary_path(boundary, kind: "frr", rule_id: rule_id),
              params: { fedramp_statement: { status: "Implemented", implementation: "SPARC writes it." } }
      }.to change { AuditEvent.where(action: "fedramp_statement_recorded").count }.by(1)
      expect(response).to redirect_to(fedramp_authorization_boundary_path(boundary, kind: "frr", anchor: "fedramp-#{rule_id}"))
      statement = boundary.fedramp_statements.find_by!(rule_id: rule_id)
      expect(statement).to have_attributes(status: "Implemented", implementation: "SPARC writes it.", updated_by: writer)
      expect(boundary.reload.fedramp_sdr_version).to eq(1)
    end

    it "takes a KSI's tests one per line and its evidence rows, and clears them when every row goes" do
      sign_in_as(writer)
      path = fedramp_statement_authorization_boundary_path(boundary, kind: "ksi", rule_id: "KSI-CED-RAT")
      patch path, params: { fedramp_statement: { tests_text: "quarterly review\n\nLMS report\n", evidence_listed: "1",
                                                 evidence: [ { evidence_type: "Report", description: "LMS", location: "",
                                                               last_updated: "2026-11-01", text: "" } ] } }
      statement = boundary.fedramp_statements.find_by!(kind: "ksi")
      expect(statement.tests).to eq([ "quarterly review", "LMS report" ])
      expect(statement.evidence).to eq([ { "evidence_type" => "Report", "description" => "LMS", "last_updated" => "2026-11-01" } ])

      patch path, params: { fedramp_statement: { tests_text: "", evidence_listed: "1" } }
      expect(statement.reload).to have_attributes(tests: [], evidence: [])
    end

    it "refuses a rule that does not apply to the profile, saying why" do
      sign_in_as(writer)
      patch fedramp_statement_authorization_boundary_path(boundary, kind: "frr", rule_id: "FRC-CSF-BSL"),
            params: { fedramp_statement: { status: "Implemented" } }
      expect(flash[:error]).to include("FRC-CSF-BSL not saved", "does not apply to a 20x Program Class B provider")
      expect(boundary.fedramp_statements).to be_empty
    end

    it "refuses a reader without evidence.write" do
      sign_in_as(user_with({ "evidence.read" => true }))
      patch fedramp_statement_authorization_boundary_path(boundary, kind: "frr", rule_id: rule_id),
            params: { fedramp_statement: { status: "Implemented" } }
      expect(boundary.fedramp_statements).to be_empty
    end
  end

  describe "the FedRAMP switch" do
    before { sign_in_as(create(:user, :admin)) }

    it "shows the FedRAMP menu entry only once FedRAMP is on" do
      get authorization_boundary_path(boundary)
      expect(html.at_css("[data-boundary-action='fedramp']")["href"]).to eq(page_path)
      boundary.update!(fedramp_enabled: false)
      get authorization_boundary_path(boundary)
      expect(html.at_css("[data-boundary-action='fedramp']")).to be_nil
    end

    it "hides the triage page's FedRAMP card and evaluation column while it is off" do
      boundary.update!(fedramp_enabled: false)
      get triage_authorization_boundary_path(boundary)
      expect(html.at_css("[data-testid='triage-fedramp-reports']")).to be_nil
      expect(html.css("th").map(&:text)).not_to include("FedRAMP evaluation")

      boundary.update!(fedramp_enabled: true)
      get triage_authorization_boundary_path(boundary)
      expect(html.at_css("[data-testid='triage-fedramp-reports']")).to be_present
      expect(html.css("th").map(&:text)).to include("FedRAMP evaluation")
    end

    it "is saved from the edit form with the profile" do
      plain = create(:authorization_boundary)
      patch authorization_boundary_path(plain),
            params: { authorization_boundary: { fedramp_enabled: "true",
                                                fedramp_package: { certification_type: "Rev5", certification_path: "Agency",
                                                                   certification_class: "C" } } }
      expect(plain.reload).to be_fedramp_enabled
      expect(plain.fedramp_profile).to eq(%w[Rev5 Agency C])
    end

    it "refuses a profile FedRAMP does not offer" do
      plain = create(:authorization_boundary)
      patch authorization_boundary_path(plain),
            params: { authorization_boundary: { fedramp_package: { certification_type: "Rev5", certification_path: "Program",
                                                                   certification_class: "A" } } }
      expect(response).to have_http_status(:unprocessable_content)
      expect(flash[:error]).to include("Class A is offered only as a 20x Program certification")

      patch authorization_boundary_path(plain),
            params: { authorization_boundary: { fedramp_package: { certification_type: "20x", certification_path: "Agency",
                                                                   certification_class: "B" } } }
      expect(flash[:error]).to include("The Agency path is offered only for Rev5")
    end
  end
end
