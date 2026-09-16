# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20260916120000_resolve_free_text_responsible_roles.rb")

# #1116 — the values free text left behind.
#
# Every example here asserts the same invariant from the other end:
# after the migration, every `role-id` stored anywhere on the document resolves
# to a role the document declares. That is the referential rule
# `OscalConformanceService` enforces (`role-id-unresolved`) and the one schema
# validation structurally cannot see.
RSpec.describe ResolveFreeTextResponsibleRoles do
  subject(:migration) { described_class.new }

  before { allow(migration).to receive(:say) }

  around do |example|
    DeferredDataMigration.executing!
    example.run
  ensure
    DeferredDataMigration.idle!
  end

  let(:document) { create(:ssp_document) }
  let(:control)  { create(:ssp_control, ssp_document: document) }

  def statement(roles)
    create(:ssp_control_statement, ssp_control: control, responsible_roles_data: roles)
  end

  def role_ids_on(record) = Array(record.reload.responsible_roles_data).map { |r| r["role-id"] }

  def declared(doc = document) = doc.reload.declared_role_ids

  # The invariant, stated once: nothing references a role the document does not
  # declare. Used as the closing assertion rather than a substitute for the
  # specific expectations above it.
  def expect_every_reference_to_resolve(doc = document)
    doc.reload
    referenced = SspControlStatement.joins(:ssp_control)
                                    .where(ssp_controls: { ssp_document_id: doc.id })
                                    .flat_map { |s| Array(s.responsible_roles_data) }
                                    .map { |r| r["role-id"] }
    expect(referenced).to all(be_in(doc.declared_role_ids))
  end

  describe "a reference that already resolves" do
    it "is left exactly as it was" do
      stmt = statement([ { "role-id" => "system-owner" } ])

      migration.resolve_free_text_roles

      expect(stmt.reload.responsible_roles_data).to eq([ { "role-id" => "system-owner" } ])
    end

    # A document that has authored no roles still DECLARES the defaults on
    # export. Writing them into metadata_extra here would turn an implicit
    # declaration into an authored one for no reason.
    it "does not author metadata.roles on a document that needed nothing" do
      statement([ { "role-id" => "prepared-by" } ])

      migration.resolve_free_text_roles

      expect(document.reload.metadata_extra).not_to have_key("roles")
    end
  end

  describe "a form variant of a role the document already declares" do
    it "rewrites the reference without declaring anything new" do
      stmt = statement([ { "role-id" => "System Owner" } ])

      migration.resolve_free_text_roles

      expect(role_ids_on(stmt)).to eq([ "system-owner" ])
      expect(document.reload.metadata_extra).not_to have_key("roles")
      expect_every_reference_to_resolve
    end

    it "normalises an underscored spelling onto the same id" do
      stmt = statement([ { "role-id" => "system_owner" } ])

      migration.resolve_free_text_roles

      expect(role_ids_on(stmt)).to eq([ "system-owner" ])
    end

    it "collapses two spellings of one role into a single reference" do
      stmt = statement([ { "role-id" => "System Owner" }, { "role-id" => "system-owner" } ])

      migration.resolve_free_text_roles

      expect(role_ids_on(stmt)).to eq([ "system-owner" ])
    end
  end

  describe "the acronym #1116 records authors typing" do
    it "maps isso onto NIST's information-system-security-officer" do
      stmt = statement([ { "role-id" => "isso" } ])

      migration.resolve_free_text_roles

      expect(role_ids_on(stmt)).to eq([ "information-system-security-officer" ])
      expect_every_reference_to_resolve
    end

    # The alias table is honoured only when NIST really names the target. `issm`
    # has no NIST id, so guessing one would mint a reference resolving to
    # nothing — the exact break this migration exists to remove.
    it "leaves issm as an organization-defined role, because NIST names no such id" do
      stmt = statement([ { "role-id" => "issm" } ])

      migration.resolve_free_text_roles

      expect(role_ids_on(stmt)).to eq([ "issm" ])
      expect(declared).to include("issm")
      expect(OscalRole.organization_defined?(document.reload.declared_roles.find { |r| r["id"] == "issm" }))
        .to be(true)
    end

    it "falls through to organization-defined if NIST renames the alias target" do
      allow(OscalRole).to receive(:suggested_ids).and_return(OscalRole::SSP_DEFAULT_IDS - [ "information-system-security-officer" ])
      stmt = statement([ { "role-id" => "isso" } ])

      migration.resolve_free_text_roles

      expect(role_ids_on(stmt)).to eq([ "isso" ])
      expect(declared).to include("isso")
    end
  end

  describe "a role NIST suggests but the document has not declared" do
    it "declares it with NIST's own id and title" do
      stmt = statement([ { "role-id" => "security-operations" } ])

      migration.resolve_free_text_roles

      expect(role_ids_on(stmt)).to eq([ "security-operations" ])
      role = document.reload.declared_roles.find { |r| r["id"] == "security-operations" }
      expect(role["title"]).to eq("Security Operations")
      expect(OscalRole.organization_defined?(role)).to be(false)
      expect_every_reference_to_resolve
    end

    # Adding the first custom role writes metadata.roles for the first time.
    # Reading only the AUTHORED list at that moment would drop the four defaults
    # the exporter was declaring implicitly.
    it "keeps the implicit defaults when it authors metadata.roles" do
      statement([ { "role-id" => "security-operations" } ])

      migration.resolve_free_text_roles

      expect(declared).to include(*OscalRole::SSP_DEFAULT_IDS)
    end
  end

  describe "a role nothing recognises" do
    it "declares it organization-defined, keeping the author's text as the title" do
      stmt = statement([ { "role-id" => "Policy Department" } ])

      migration.resolve_free_text_roles

      expect(role_ids_on(stmt)).to eq([ "policy-department" ])
      role = document.reload.declared_roles.find { |r| r["id"] == "policy-department" }
      expect(role["title"]).to eq("Policy Department")
      expect(role.dig("props", 0, "ns")).to eq(OscalNamespace.instance)
      expect_every_reference_to_resolve
    end

    it "humanises the title when the author typed an id-shaped token" do
      statement([ { "role-id" => "control-provider" } ])

      migration.resolve_free_text_roles

      expect(document.reload.declared_roles.find { |r| r["id"] == "control-provider" }["title"])
        .to eq("Control Provider")
    end

    # `role-id` is an NCName token and may not start with a digit.
    it "prefixes an id that would not be a legal NCName" do
      stmt = statement([ { "role-id" => "3rd Party Assessor" } ])

      migration.resolve_free_text_roles

      expect(role_ids_on(stmt)).to eq([ "role-3rd-party-assessor" ])
      expect(declared).to include("role-3rd-party-assessor")
    end

    it "declares a role named by two statements exactly once" do
      statement([ { "role-id" => "Policy Department" } ])
      statement([ { "role-id" => "policy_department" } ])

      migration.resolve_free_text_roles

      expect(declared.count { |id| id == "policy-department" }).to eq(1)
    end
  end

  describe "shapes free text could produce" do
    it "keeps party-uuids while rewriting the role-id" do
      uuid = SecureRandom.uuid
      stmt = statement([ { "role-id" => "System Owner", "party-uuids" => [ uuid ] } ])

      migration.resolve_free_text_roles

      expect(stmt.reload.responsible_roles_data)
        .to eq([ { "role-id" => "system-owner", "party-uuids" => [ uuid ] } ])
    end

    # The pre-#1100 permit was `responsible_roles_data: []` — a bare array of
    # scalars, which exports as `"responsible-roles": ["isso"]` and is
    # schema-invalid.
    it "gives a bare string the responsible-role assembly shape" do
      stmt = statement([ "isso" ])

      migration.resolve_free_text_roles

      expect(stmt.reload.responsible_roles_data)
        .to eq([ { "role-id" => "information-system-security-officer" } ])
    end

    it "removes a blank role-id and keeps its neighbours" do
      stmt = statement([ { "role-id" => "" }, { "role-id" => "system-owner" } ])

      migration.resolve_free_text_roles

      expect(role_ids_on(stmt)).to eq([ "system-owner" ])
    end

    # "---" normalises to nothing at all — there is no id in it to declare.
    it "removes a value that carries no id" do
      stmt = statement([ { "role-id" => "---" } ])

      migration.resolve_free_text_roles

      expect(stmt.reload.responsible_roles_data).to eq([])
    end
  end

  describe "every site that stores responsible roles" do
    it "resolves a component" do
      component = create(:ssp_component, ssp_document: document,
                                         responsible_roles_data: [ { "role-id" => "System Owner" } ])

      migration.resolve_free_text_roles

      expect(role_ids_on(component)).to eq([ "system-owner" ])
    end

    it "resolves a by-component" do
      component = create(:ssp_component, ssp_document: document)
      by_component = create(:ssp_by_component, ssp_control: control, ssp_component: component,
                                               responsible_roles_data: [ { "role-id" => "isso" } ])

      migration.resolve_free_text_roles

      expect(role_ids_on(by_component)).to eq([ "information-system-security-officer" ])
    end
  end

  describe "a document that declared no roles at all" do
    # `declared_roles` distinguishes "never authored" from "authored an empty
    # list". An author who removed every role has declared none, and the
    # migration must not resurrect the defaults on their behalf.
    it "does not resurrect the defaults it deliberately removed" do
      document.update!(metadata_extra: { "roles" => [] })
      stmt = statement([ { "role-id" => "system-owner" } ])

      migration.resolve_free_text_roles

      expect(role_ids_on(stmt)).to eq([ "system-owner" ])
      expect(declared).to eq([ "system-owner" ])
    end
  end

  describe "idempotency and resume-from-partial" do
    it "is a no-op on a second run" do
      stmt = statement([ { "role-id" => "isso" }, { "role-id" => "Policy Department" } ])

      migration.resolve_free_text_roles
      after_first = [ stmt.reload.responsible_roles_data, document.reload.metadata_extra ]

      migration.resolve_free_text_roles

      expect([ stmt.reload.responsible_roles_data, document.reload.metadata_extra ]).to eq(after_first)
    end

    it "leaves an already-resolved document alone and still processes its neighbour" do
      done = create(:ssp_document, metadata_extra: { "roles" => [ { "id" => "isso", "title" => "ISSO" } ] })
      done_stmt = create(:ssp_control_statement,
                         ssp_control: create(:ssp_control, ssp_document: done),
                         responsible_roles_data: [ { "role-id" => "isso" } ])
      pending_stmt = statement([ { "role-id" => "isso" } ])

      migration.resolve_free_text_roles

      expect(done_stmt.reload.responsible_roles_data).to eq([ { "role-id" => "isso" } ]),
        "a document that already declares the id it references is already migrated"
      expect(done.reload.declared_role_ids).to eq([ "isso" ])
      expect(role_ids_on(pending_stmt)).to eq([ "information-system-security-officer" ])
    end

    it "resolves the statements a halted run had not reached yet" do
      first  = statement([ { "role-id" => "Policy Department" } ])
      second = statement([ { "role-id" => "Policy Department" } ])
      # Simulate a run that got through `first` and died before `second`.
      first.update_columns(responsible_roles_data: [ { "role-id" => "policy-department" } ])
      document.update!(metadata_extra: { "roles" => document.declared_roles +
        [ OscalRole.organization_defined("policy-department", "Policy Department") ] })

      migration.resolve_free_text_roles

      expect(role_ids_on(first)).to eq([ "policy-department" ])
      expect(role_ids_on(second)).to eq([ "policy-department" ])
      expect(declared.count { |id| id == "policy-department" }).to eq(1)
    end
  end
end
