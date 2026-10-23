# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProfileControlBulkEditService do
  let(:profile) { create(:profile_document) }
  let!(:ac1) { create(:profile_control, profile_document: profile, control_id: "ac-1", priority: nil) }
  let!(:ac2) { create(:profile_control, profile_document: profile, control_id: "ac-2", priority: "P3") }
  let!(:ac21) { create(:profile_control, profile_document: profile, control_id: "ac-2.1", priority: nil) }
  let(:user) { create(:user) }
  let(:global) { create(:back_matter_resource, title: "Invented global policy", globally_available: true) }
  let(:private_elsewhere) { create(:back_matter_resource, title: "Invented private record", globally_available: false) }

  subject(:service) { described_class.new(profile, user: user) }

  describe "priority" do
    it "sets it on every named control, in any accepted id form" do
      result = service.apply(control_ids: [ "ac-1", "AC-2(1)" ], priority: "P1")

      expect([ ac1.reload.priority, ac21.reload.priority ]).to eq(%w[P1 P1])
      expect(ac2.reload.priority).to eq("P3")
      expect(result.control_ids).to contain_exactly("ac-1", "ac-2.1")
      expect(result.priority_changed).to be(true)
    end

    it "clears it when sent empty" do
      service.apply(control_ids: [ "ac-2" ], priority: "")

      expect(ac2.reload.priority).to be_nil
    end

    it "leaves it alone when not sent" do
      service.apply(control_ids: [ "ac-2" ], link_resource_ids: [ global.id ])

      expect(ac2.reload.priority).to eq("P3")
    end

    it "refuses a value outside P1-P3 and writes nothing" do
      expect { service.apply(control_ids: [ "ac-1", "ac-2" ], priority: "P9") }
        .to raise_error(described_class::EditError, /must be one of P1, P2, P3/)
      expect(ac2.reload.priority).to eq("P3")
    end
  end

  describe "back-matter" do
    it "links a resource to every named control, once" do
      ac1.control_back_matter_links.create!(back_matter_resource: global)

      result = service.apply(control_ids: %w[ac-1 ac-2], link_resource_ids: [ global.id.to_s ])

      expect(result.linked).to eq(1)
      expect(ac1.back_matter_resources.reload).to eq([ global ])
      expect(ac2.back_matter_resources.reload).to eq([ global ])
    end

    it "unlinks without deleting the resource" do
      [ ac1, ac2 ].each { _1.control_back_matter_links.create!(back_matter_resource: global) }

      result = service.apply(control_ids: %w[ac-1 ac-2], unlink_resource_ids: [ global.id ])

      expect(result.unlinked).to eq(2)
      expect(ac1.back_matter_resources.reload).to be_empty
      expect(BackMatterResource.exists?(global.id)).to be(true)
    end

    it "refuses a resource the user may not link, and writes nothing" do
      expect {
        service.apply(control_ids: %w[ac-1], priority: "P2",
                      link_resource_ids: [ global.id, private_elsewhere.id ])
      }.to raise_error(described_class::EditError, /not available to you: #{private_elsewhere.id}/)
      expect(ac1.reload.priority).to be_nil
      expect(ac1.back_matter_resources.reload).to be_empty
    end

    it "lets a user link their own organization's resource" do
      org = create(:organization)
      create(:organization_membership, user: user, organization: org)
      own = create(:back_matter_resource, organization: org, globally_available: false)

      service.apply(control_ids: %w[ac-1], link_resource_ids: [ own.id ])

      expect(ac1.back_matter_resources.reload).to eq([ own ])
    end
  end

  describe "refusals" do
    it "names controls that are not in the profile, and writes nothing" do
      expect { service.apply(control_ids: %w[ac-1 zz-9], priority: "P1") }
        .to raise_error(described_class::EditError, "Not in this profile: zz-9")
      expect(ac1.reload.priority).to be_nil
    end

    it "refuses an empty selection" do
      expect { service.apply(control_ids: [], priority: "P1") }
        .to raise_error(described_class::EditError, /at least one control/)
    end

    it "refuses a change that changes nothing" do
      expect { service.apply(control_ids: %w[ac-1]) }
        .to raise_error(described_class::EditError, /Nothing to change/)
    end

    it "refuses a published profile" do
      profile.update!(lifecycle_status: "published")

      expect { service.apply(control_ids: %w[ac-1], priority: "P1") }
        .to raise_error(described_class::EditError, /is published/)
      expect(ac1.reload.priority).to be_nil
    end
  end
end
