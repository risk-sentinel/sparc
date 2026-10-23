# frozen_string_literal: true

require "rails_helper"

# #1270 — on the Profile screen, a control's priority is set in place and
# controls are changed together from the bulk bar. These submit what the page
# renders (form action, method, field names, the checkboxes' `form`
# attribute) and read the result back from the database.
RSpec.describe "Profile control priority and bulk edit (#1270)", type: :request do
  let(:profile) { create(:profile_document) }
  let!(:ac1) { create(:profile_control, profile_document: profile, control_id: "ac-1", priority: nil, control_family: "AC") }
  let!(:ac2) { create(:profile_control, profile_document: profile, control_id: "ac-2", priority: "P3", control_family: "AC") }
  let(:author) { create(:user).tap { grant_permission(_1, "profiles.write") } }
  let(:curator) do
    create(:user).tap do |u|
      grant_permission(u, "profiles.write")
      grant_permission(u, "back_matter.write")
    end
  end
  let(:reader) { create(:user) }
  let!(:resource) { create(:back_matter_resource, title: "Invented access policy", globally_available: true) }

  def page_doc
    get profile_document_path(profile)
    expect(response).to have_http_status(:ok)
    Nokogiri::HTML(response.body)
  end

  # Builds the request the bulk bar's form makes when `button` is pressed with
  # the checkboxes for `control_ids` ticked: every field the form owns, plus
  # the checkboxes that name it with their `form` attribute.
  def submit_bulk_bar(doc, control_ids:, button:, choose: {})
    form = doc.at_css("form#profile-bulk-form")
    expect(form).to be_present
    params = {}
    form.css("input[type=hidden]").each { params[_1["name"]] = _1["value"] }
    form.css("select").each do |select|
      chosen = choose[select["name"]] || select.at_css("option")&.[]("value")
      params[select["name"]] = chosen
    end
    pressed = form.css("button[name=bulk_action]").find { _1.text.strip == button }
    expect(pressed).to be_present, "no #{button.inspect} button on the bulk bar"
    params["bulk_action"] = pressed["value"]

    boxes = doc.css("input[type=checkbox][form='profile-bulk-form']")
    ticked = boxes.map { _1["value"] }.select { control_ids.include?(_1) }
    # A browser sends no field at all for a group with nothing ticked.
    params["control_ids"] = ticked if ticked.any?
    method = (params.delete("_method") || form["method"]).downcase
    public_send(method, form["action"], params: params)
  end

  describe "the Profile screen" do
    it "offers an author the priority selector, the checkboxes and the bulk bar" do
      sign_in_as(author)
      doc = page_doc

      selector = doc.at_css("select#priority-#{ac1.id}")
      expect(selector["aria-label"]).to eq("Priority for AC-1")
      expect(selector["class"]).to include("sparc-priority-select--unset")
      expect(selector.css("option").map(&:text)).to eq([ "Priority not set", "P1", "P2", "P3" ])
      expect(doc.at_css("select#priority-#{ac2.id} option[selected]")["value"]).to eq("P3")
      expect(doc.css("input[type=checkbox][form='profile-bulk-form']").map { _1["value"] }).to contain_exactly("ac-1", "ac-2")
      expect(doc.at_css("input[data-group='AC'][data-action*='toggleGroup']")).to be_present
    end

    it "shows a reader the priority, and nothing to change it with" do
      sign_in_as(reader)
      doc = page_doc

      expect(doc.at_css("select.sparc-priority-select")).to be_nil
      expect(doc.at_css("form#profile-bulk-form")).to be_nil
      expect(doc.css(".control-card .sparc-status-pill").map { _1.text.strip }).to include("P3", "(None)")
    end

    it "shows a published profile's priority read-only, even to an author" do
      profile.update!(lifecycle_status: "published")
      sign_in_as(author)
      doc = page_doc

      expect(doc.at_css("select.sparc-priority-select")).to be_nil
      expect(doc.at_css("form#profile-bulk-form")).to be_nil
    end

    it "offers resource linking only to a user who may write back-matter" do
      sign_in_as(author)
      expect(page_doc.at_css("form#profile-bulk-form select[name=resource_id]")).to be_nil

      sign_in_as(curator)
      expect(page_doc.css("form#profile-bulk-form select[name=resource_id] option").map(&:text))
        .to include("Invented access policy")
    end

    # The chip filtered on "None" while each card carries "(None)", so it hid
    # every control.
    it "filters the not-set chip on the label the control cards carry" do
      sign_in_as(reader)
      doc = page_doc

      chip = doc.css(".summary-chip").find { _1.at_css(".sparc-chip-label")&.text&.strip == "Not set" }
      expect(chip["data-heatmap-chip-filter-param"]).to eq(doc.at_css(".control-card[data-priority='(None)']")["data-priority"])
    end
  end

  describe "the bulk bar, submitted as rendered" do
    it "sets the priority of the selected controls" do
      sign_in_as(author)

      submit_bulk_bar(page_doc, control_ids: %w[ac-1 ac-2], button: "Set priority", choose: { "priority" => "P1" })

      expect(response).to redirect_to(profile_document_path(profile))
      expect(flash[:success]).to eq("2 controls: priority P1")
      expect([ ac1.reload.priority, ac2.reload.priority ]).to eq(%w[P1 P1])
      expect(AuditEvent.where(action: "profile_controls_bulk_edited").last.metadata)
        .to include("control_ids" => %w[ac-1 ac-2], "priority" => "P1")
    end

    it "clears the priority of the selected controls" do
      sign_in_as(author)

      submit_bulk_bar(page_doc, control_ids: %w[ac-2], button: "Set priority", choose: { "priority" => "" })

      expect(ac2.reload.priority).to be_nil
    end

    it "links and unlinks a resource" do
      sign_in_as(curator)

      submit_bulk_bar(page_doc, control_ids: %w[ac-1 ac-2], button: "Link resource",
                                choose: { "resource_id" => resource.id.to_s })
      expect([ ac1, ac2 ].map { _1.back_matter_resources.reload.to_a }).to eq([ [ resource ], [ resource ] ])

      submit_bulk_bar(page_doc, control_ids: %w[ac-2], button: "Unlink resource",
                                choose: { "resource_id" => resource.id.to_s })
      expect(ac2.back_matter_resources.reload).to be_empty
      expect(ac1.back_matter_resources.reload).to eq([ resource ])
    end

    it "shows the reason when nothing is selected" do
      sign_in_as(author)

      submit_bulk_bar(page_doc, control_ids: [], button: "Set priority")

      expect(flash[:error]).to match(/at least one control/)
    end
  end

  describe "the inline selector" do
    let(:path) { bulk_profile_document_profile_controls_path(profile) }

    it "saves one control's priority and answers in JSON" do
      sign_in_as(author)

      patch path, params: { control_ids: [ "ac-1" ], priority: "P2" }, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig("data", "control_ids")).to eq([ "ac-1" ])
      expect(ac1.reload.priority).to eq("P2")
    end

    it "explains a refusal in JSON" do
      sign_in_as(author)

      patch path, params: { control_ids: [ "ac-1" ], priority: "urgent" }, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to match(/must be one of/)
    end
  end

  describe "permissions, both directions" do
    let(:path) { bulk_profile_document_profile_controls_path(profile) }

    it "refuses a user without profiles.write" do
      sign_in_as(reader)

      patch path, params: { control_ids: [ "ac-1" ], priority: "P1" }, as: :json

      expect(response).to have_http_status(:forbidden)
      expect(ac1.reload.priority).to be_nil
    end

    it "refuses linking to a user without back_matter.write, while letting them set priority" do
      sign_in_as(author)

      patch path, params: { control_ids: [ "ac-1" ], link_resource_ids: [ resource.id ] }, as: :json
      expect(response).to have_http_status(:forbidden)
      expect(ac1.back_matter_resources.reload).to be_empty

      patch path, params: { control_ids: [ "ac-1" ], priority: "P1" }, as: :json
      expect(response).to have_http_status(:ok)
    end
  end

  describe "the control Edit screen" do
    before do
      ac1.profile_control_fields.create!(field_name: "parameter:ac-1_prm_1", field_value: "Invented value")
      ac1.profile_control_fields.create!(field_name: "parameter_value", field_value: "Invented stored text")
    end

    it "keeps id, title, priority, notes and back-matter, and drops the parameter fields" do
      sign_in_as(curator)
      get edit_profile_document_profile_control_path(profile, ac1)

      doc = Nokogiri::HTML(response.body)
      expect(doc.at_css("select[name='profile_control[priority]']").css("option").map { _1["value"] })
        .to eq([ "", "P1", "P2", "P3" ])
      expect(doc.at_css("textarea[name='fields[tailoring_notes]']")).to be_present
      expect(response.body).to include("Back-Matter References")
      expect(doc.css("input[name^='param_values']")).to be_empty
      expect(doc.at_css("textarea[name='fields[parameter_value]']")).to be_nil
    end

    it "saves without touching stored parameter values" do
      sign_in_as(curator)

      patch profile_document_profile_control_path(profile, ac1),
            params: { profile_control: { control_id: "ac-1", title: "Invented title", priority: "P2" },
                      fields: { tailoring_notes: "Invented note", parameter_value: "ignored" } }

      expect(ac1.reload.priority).to eq("P2")
      fields = ac1.profile_control_fields.reload.index_by(&:field_name)
      expect(fields["tailoring_notes"].field_value).to eq("Invented note")
      expect(fields["parameter_value"].field_value).to eq("Invented stored text")
      expect(fields["parameter:ac-1_prm_1"].field_value).to eq("Invented value")
    end
  end
end
