# Shared examples verifying that an OSCAL export service produces
# identical UUIDs on repeated exports (no SecureRandom.uuid churn).
#
# Usage in an exporter spec:
#   subject { OscalSspExportService.new(document) }
#   it_behaves_like "produces stable UUIDs across exports"
#
RSpec.shared_examples "produces stable UUIDs across exports" do |export_method: :export_unvalidated|
  include ActiveSupport::Testing::TimeHelpers

  it "emits identical UUIDs on repeated exports" do
    travel_to Time.zone.local(2026, 4, 16, 12, 0, 0) do
      first  = JSON.parse(subject.public_send(export_method))
      second = JSON.parse(subject.public_send(export_method))
      expect(extract_uuids(first)).to eq(extract_uuids(second))
    end
  end

  it "produces JSON-equivalent output on repeated exports under frozen time" do
    travel_to Time.zone.local(2026, 4, 16, 12, 0, 0) do
      a = JSON.parse(subject.public_send(export_method))
      b = JSON.parse(subject.public_send(export_method))
      expect(a).to eq(b)
    end
  end

  it "emits only RFC 4122 v4-shaped UUIDs" do
    travel_to Time.zone.local(2026, 4, 16, 12, 0, 0) do
      data = JSON.parse(subject.public_send(export_method))
      uuids = extract_uuids(data).reject(&:blank?)
      expect(uuids).to all(match(BackMatterResource::UUID_V4_REGEX))
    end
  end

  def extract_uuids(node, acc = [])
    case node
    when Hash
      %w[uuid observation-uuid risk-uuid finding-uuid component-uuid
         party-uuid task-uuid].each do |key|
        acc << node[key] if node.key?(key)
      end
      node.each_value { |v| extract_uuids(v, acc) }
    when Array then node.each { |v| extract_uuids(v, acc) }
    end
    acc
  end
end
