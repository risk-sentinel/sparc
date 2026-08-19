# frozen_string_literal: true

require "rails_helper"

RSpec.describe AuditEvent, type: :model do
  describe "validations" do
    it { is_expected.to validate_presence_of(:action) }
    it { is_expected.to validate_inclusion_of(:action).in_array(AuditEvent::ACTIONS) }
  end

  describe "associations" do
    it { is_expected.to belong_to(:user).optional }
  end

  describe "ACTIONS" do
    it "includes auth actions" do
      expect(AuditEvent::ACTIONS).to include("login_success", "login_failure", "logout", "password_change")
    end

    it "includes resource CRUD actions" do
      expect(AuditEvent::ACTIONS).to include(
        "ssp_document_created", "ssp_document_updated", "ssp_document_deleted", "ssp_document_exported",
        "sar_document_created", "control_catalog_imported", "control_mapping_published"
      )
    end

    it "includes authorization_failure" do
      expect(AuditEvent::ACTIONS).to include("authorization_failure")
    end
  end

  describe "ACTION_CATEGORIES" do
    it "covers all actions" do
      categorized = AuditEvent::ACTION_CATEGORIES.values.flatten
      uncategorized = AuditEvent::ACTIONS - categorized
      expect(uncategorized).to be_empty,
        "These actions are not in any category: #{uncategorized.join(', ')}"
    end

    it "has no orphan actions in categories" do
      categorized = AuditEvent::ACTION_CATEGORIES.values.flatten
      orphans = categorized - AuditEvent::ACTIONS
      expect(orphans).to be_empty,
        "These category actions are not in ACTIONS: #{orphans.join(', ')}"
    end
  end

  # #982 — the registry trap, caught as a CLASS rather than an instance.
  #
  # `AuditEvent` validates `action` against ACTIONS, and `AuditEvent.log` rescues
  # RecordInvalid *internally* (logging and returning nil). Because the rescue is
  # inside `.log`, the API base controller's outer `raise unless
  # Rails.env.production?` never fires — so an unregistered action writes NO row
  # in ANY environment, and nothing raises to tell anyone. That is how 69 emitted
  # actions, including API token create/revoke and every finding disposition,
  # recorded nothing at all while the suite stayed green.
  #
  # Pairing specs cannot catch this: they compare ACTIONS to ACTION_CATEGORIES,
  # and an action absent from BOTH is consistent with itself. Only the source
  # tells the truth about what is actually emitted.
  describe "emitted actions are registered (#982)" do
    # Literal first arguments to the three audit_log helpers
    # (`concerns/auditable.rb`, `api/v1/base_controller.rb`,
    # `api/v1/admin/credentials_controller.rb`), plus direct `AuditEvent.log`.
    let(:literal_call_sites) do
      pattern = /(?:audit_log|audit_log_api)\(\s*"([a-z0-9_.]+)"|
                 AuditEvent\.log\(\s*(?:[a-z_]+:\s*[^,]+,\s*)*action:\s*"([a-z0-9_.]+)"/x

      Dir[Rails.root.join("{app,lib}/**/*.rb")].sort.flat_map do |file|
        File.readlines(file).each_with_index.filter_map do |line, index|
          match = line.match(pattern)
          next unless match

          { action: match[1] || match[2],
            location: "#{Pathname.new(file).relative_path_from(Rails.root)}:#{index + 1}" }
        end
      end
    end

    # Call sites whose action is built at runtime, which no static scan can
    # resolve. Named rather than ignored: a silent blind spot reads as coverage.
    # Every entry's expansions ARE registered — `#{doc.class.name.underscore}_fields_imported`
    # was NOT, which is how the four *_fields_imported actions were found.
    let(:known_dynamic_call_sites) do
      %w[
        app/controllers/api/v1/document_base_controller.rb
        app/controllers/concerns/baseline_declarable.rb
        app/controllers/concerns/boundary_attachable.rb
        app/controllers/concerns/field_importable.rb
        app/controllers/concerns/file_uploadable.rb
        app/controllers/concerns/publishable.rb
      ]
    end

    it "finds the call sites it claims to scan" do
      expect(literal_call_sites.size).to be > 200,
        "the scanner matched #{literal_call_sites.size} call sites — the regex has probably " \
        "drifted from the helper signatures, and a guard that scans nothing passes everything"
    end

    it "emits no action that is missing from ACTIONS" do
      unregistered = literal_call_sites.reject { |site| AuditEvent::ACTIONS.include?(site[:action]) }

      expect(unregistered).to be_empty, <<~MESSAGE
        These audit_log call sites name an action absent from AuditEvent::ACTIONS.
        Each one writes NO audit record, in every environment, and raises nothing:

        #{unregistered.map { |s| "  #{s[:location]}\t#{s[:action]}" }.join("\n")}

        Add each action to ACTIONS and to the matching ACTION_CATEGORIES group.
      MESSAGE
    end

    it "has no undeclared dynamic call site whose expansions cannot be checked" do
      interpolated = Dir[Rails.root.join("{app,lib}/**/*.rb")].sort.select do |file|
        File.read(file).match?(/(?:audit_log|audit_log_api)\(\s*(?:"[^"]*\#\{|[a-z_]+[\[(])/)
      end.map { |file| Pathname.new(file).relative_path_from(Rails.root).to_s }

      expect(interpolated - known_dynamic_call_sites).to be_empty, <<~MESSAGE
        New audit_log call site(s) build the action name at runtime, so the static
        guard above cannot verify them:

        #{(interpolated - known_dynamic_call_sites).map { |f| "  #{f}" }.join("\n")}

        Work out every string each one can produce, register them all, then add the
        file to `known_dynamic_call_sites`.
      MESSAGE
    end
  end

  describe ".log" do
    let(:user) { create(:user) }

    it "creates an audit event" do
      expect {
        AuditEvent.log(user: user, action: "login_success", provider: "local", ip_address: "127.0.0.1")
      }.to change(AuditEvent, :count).by(1)
    end

    it "creates an event without a user (failed login)" do
      expect {
        AuditEvent.log(action: "login_failure", provider: "local", ip_address: "127.0.0.1")
      }.to change(AuditEvent, :count).by(1)

      event = AuditEvent.last
      expect(event.user).to be_nil
    end

    it "handles invalid action gracefully" do
      expect {
        AuditEvent.log(action: "invalid_action", provider: "local")
      }.not_to change(AuditEvent, :count)
    end

    it "stores subject_type and subject_id when subject is provided" do
      # Create an actual record to use as subject
      authorization_boundary = create(:authorization_boundary)
      event = AuditEvent.log(
        user: user, action: "authorization_boundary_created",
        ip_address: "127.0.0.1", subject: authorization_boundary
      )
      expect(event.subject_type).to eq("AuthorizationBoundary")
      expect(event.subject_id).to eq(authorization_boundary.id)
    end

    it "leaves subject columns nil when no subject provided" do
      event = AuditEvent.log(user: user, action: "login_success", ip_address: "127.0.0.1")
      expect(event.subject_type).to be_nil
      expect(event.subject_id).to be_nil
    end

    it "emits structured JSON to Rails logger" do
      allow(Rails.logger).to receive(:info)

      AuditEvent.log(user: user, action: "login_success", ip_address: "10.0.0.1")

      expect(Rails.logger).to have_received(:info).with(a_string_including('"audit_event"'))
      expect(Rails.logger).to have_received(:info).with(a_string_including('"action":"login_success"'))
      expect(Rails.logger).to have_received(:info).with(a_string_including('"ip_address":"10.0.0.1"'))
      expect(Rails.logger).to have_received(:info).with(a_string_including(user.email))
    end

    it "includes subject info in structured log when subject provided" do
      allow(Rails.logger).to receive(:info)
      authorization_boundary = create(:authorization_boundary)

      AuditEvent.log(user: user, action: "authorization_boundary_created", ip_address: "10.0.0.1", subject: authorization_boundary)

      expect(Rails.logger).to have_received(:info).with(a_string_including('"subject_type":"AuthorizationBoundary"'))
      expect(Rails.logger).to have_received(:info).with(a_string_including("\"subject_id\":#{authorization_boundary.id}"))
    end
  end

  describe "#category" do
    it "returns Authentication for login events" do
      event = build(:audit_event, action: "login_success")
      expect(event.category).to eq("Authentication")
    end

    it "returns SSP Documents for ssp events" do
      event = build(:audit_event, action: "ssp_document_created")
      expect(event.category).to eq("SSP Documents")
    end

    it "returns Authorization for authorization_failure" do
      event = build(:audit_event, action: "authorization_failure")
      expect(event.category).to eq("Authorization")
    end
  end

  describe "scopes" do
    let(:user) { create(:user) }

    describe ".for_subject" do
      it "returns events for a specific subject" do
        authorization_boundary = create(:authorization_boundary)
        AuditEvent.log(user: user, action: "authorization_boundary_created", ip_address: "127.0.0.1", subject: authorization_boundary)
        AuditEvent.log(user: user, action: "login_success", ip_address: "127.0.0.1")

        results = AuditEvent.for_subject(authorization_boundary)
        expect(results.count).to eq(1)
        expect(results.first.action).to eq("authorization_boundary_created")
      end
    end

    describe ".by_subject_type" do
      it "filters by subject type string" do
        AuditEvent.create!(action: "ssp_document_created", subject_type: "SspDocument", subject_id: 1, metadata: {})
        AuditEvent.create!(action: "authorization_boundary_created", subject_type: "AuthorizationBoundary", subject_id: 1, metadata: {})

        results = AuditEvent.by_subject_type("SspDocument")
        expect(results.count).to eq(1)
      end
    end

    describe ".by_category" do
      it "filters by category name" do
        AuditEvent.create!(action: "login_success", metadata: {})
        AuditEvent.create!(action: "ssp_document_created", metadata: {})

        results = AuditEvent.by_category("Authentication")
        expect(results.count).to eq(1)
        expect(results.first.action).to eq("login_success")
      end

      it "returns none for unknown category" do
        expect(AuditEvent.by_category("Nonexistent")).to be_empty
      end
    end

    describe ".in_date_range" do
      it "filters events by date range" do
        old_event = AuditEvent.create!(action: "login_success", created_at: 30.days.ago, metadata: {})
        new_event = AuditEvent.create!(action: "login_success", created_at: 1.day.ago, metadata: {})

        results = AuditEvent.in_date_range(7.days.ago.to_date, Date.today)
        expect(results).to include(new_event)
        expect(results).not_to include(old_event)
      end

      it "handles nil start_date by applying only end_date filter" do
        event = AuditEvent.create!(action: "login_success", created_at: 1.day.ago, metadata: {})
        results = AuditEvent.in_date_range(nil, Date.today)
        expect(results).to include(event)
      end
    end

    describe ".search" do
      it "searches in action name" do
        AuditEvent.create!(action: "login_success", metadata: {})
        AuditEvent.create!(action: "ssp_document_created", metadata: {})

        results = AuditEvent.search("login")
        expect(results.count).to eq(1)
      end

      it "searches in metadata" do
        AuditEvent.create!(action: "ssp_document_created", metadata: { name: "My Test SSP" })
        AuditEvent.create!(action: "login_success", metadata: {})

        results = AuditEvent.search("My Test SSP")
        expect(results.count).to eq(1)
      end

      it "returns all for blank query" do
        AuditEvent.create!(action: "login_success", metadata: {})
        expect(AuditEvent.search("").count).to eq(1)
        expect(AuditEvent.search(nil).count).to eq(1)
      end
    end
  end
end
