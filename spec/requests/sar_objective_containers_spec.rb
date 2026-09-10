# frozen_string_literal: true

require "rails_helper"

# #1114 — NIST's grouping nodes are headings, not work.
#
# Owner review: 'There are some empty "parent" control labels "AC-02h. (no
# prose)"'.
#
# 800-53A nests determination statements under container parts that carry a
# LABEL and no prose — `ac-1_obj`, `ac-1_obj.a`, `ac-1_obj.a.1`. Rendered as
# assessable rows they showed "(no prose)" beside a Pending pill and an Edit
# button, for something there is nothing to determine about.
#
# The same container-vs-leaf distinction as #1113, where binding a field to a
# container rendered an empty box.
RSpec.describe "SAR objective containers (#1114)", type: :request do
  before { sign_in_as(create(:user, :admin)) }

  let(:sar) { create(:sar_document) }
  let!(:control) { sar.sar_controls.create!(control_id: "ac-2", title: "Accounts", control_family: "AC", row_order: 0) }

  let!(:group) do
    control.sar_control_objectives.create!(objective_id: "ac-2_obj.h", label: "AC-02h.",
                                           prose: nil, status: "pending",
                                           row_order: 0, uuid: SecureRandom.uuid)
  end
  let!(:leaf) do
    control.sar_control_objectives.create!(objective_id: "ac-2_obj.h-1", label: "AC-02h.[01]",
                                           prose: "accounts are reviewed", status: "pending",
                                           row_order: 1, uuid: SecureRandom.uuid)
  end

  it "never prints the (no prose) placeholder" do
    get sar_document_path(sar)

    expect(response.body).not_to include("(no prose)")
  end

  it "renders the container as a heading rather than an assessable row" do
    get sar_document_path(sar)

    expect(response.body).to include("sparc-objective-group")
    # No status pill and no Edit for a container: there is nothing to determine.
    group_row = response.body[/sparc-objective-group.*?<\/tr>/m].to_s
    expect(group_row).not_to include("sparc-status-pill")
    expect(group_row).not_to include("objective_id=#{group.id}")
  end

  it "still shows its label, so the structure is visible" do
    get sar_document_path(sar)

    expect(response.body).to include("AC-02h.")
  end

  it "keeps the determination statement beneath it assessable" do
    get sar_document_path(sar)

    expect(response.body).to include("accounts are reviewed")
    expect(response.body).to include("obj-#{leaf.id}")
  end

  describe "the model" do
    it "knows a container from a determination" do
      expect(group).to be_container
      expect(group).not_to be_determinable
      expect(leaf).not_to be_container
      expect(leaf).to be_determinable
    end

    it "scopes to the determinable ones" do
      expect(control.sar_control_objectives.determinable).to contain_exactly(leaf)
    end

    # A container can never become a finding: OSCAL requires a determination and
    # there is nothing stated to determine. Asserted against the EXPORT, not
    # against the predicate — the first version of this example checked
    # `determinable?` and would have passed while the exporter, which keys off
    # `determined?`, happily emitted one.
    it "is never exported as a finding, even if it somehow carries a status" do
      group.update!(status: "passing")
      leaf.update!(status: "passing")

      raw = OscalSarExportService.new(sar.reload).export_unvalidated
      doc = raw.is_a?(String) ? JSON.parse(raw) : raw.deep_stringify_keys
      targets = Array(doc.dig("assessment-results", "results"))
                  .flat_map { |r| Array(r["findings"]) }
                  .map { |f| f.dig("target", "target-id") }

      expect(targets).to include("ac-2_obj.h-1")
      expect(targets).not_to include("ac-2_obj.h"),
        "a grouping node must not be reported as a determination"
    end
  end
end
