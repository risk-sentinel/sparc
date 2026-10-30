# frozen_string_literal: true

require "rails_helper"

# 1.18.0-rf — the weekly activity behind the Boundaries tab's sparklines.
RSpec.describe BoundaryActivity do
  let(:now) { Time.utc(2026, 10, 29, 12) } # a Thursday
  let(:this_week) { now.beginning_of_week }
  let(:alpha) { create(:authorization_boundary) }
  let(:bravo) { create(:authorization_boundary) }

  def event(subject, at)
    AuditEvent.create!(action: "ssp_document_created", subject_type: subject.class.name, subject_id: subject.id, created_at: at)
  end

  it "counts events on the boundary and on its documents, by week, oldest first" do
    ssp = create(:ssp_document, authorization_boundary: alpha)
    poam = create(:poam_document, authorization_boundary: alpha)
    evidence = create(:evidence, authorization_boundary: alpha)

    event(alpha, this_week + 1.day)
    event(ssp, this_week + 2.days)
    event(poam, this_week - 1.week)
    event(evidence, this_week - 25.weeks)
    event(create(:ssp_document, authorization_boundary: bravo), this_week)

    series = described_class.weekly([ alpha.id, bravo.id ], now: now)

    expect(series[alpha.id].size).to eq(26)
    expect(series[alpha.id].last).to eq(2)
    expect(series[alpha.id][-2]).to eq(1)
    expect(series[alpha.id].first).to eq(1)
    expect(series[alpha.id].sum).to eq(4)
    expect(series[bravo.id].sum).to eq(1)
  end

  it "leaves out events older than the window, other boundaries and unrelated subjects" do
    ssp = create(:ssp_document, authorization_boundary: alpha)
    event(ssp, this_week - 26.weeks)
    event(create(:ssp_document, authorization_boundary: bravo), this_week)
    event(create(:control_catalog), this_week)

    expect(described_class.weekly([ alpha.id ], now: now)).to eq(alpha.id => Array.new(26, 0))
  end

  it "no longer counts an event whose subject was deleted outright" do
    poam = create(:poam_document, authorization_boundary: alpha)
    event(poam, this_week)
    poam.delete

    expect(described_class.weekly([ alpha.id ], now: now)[alpha.id].sum).to eq(0)
  end

  it "is one query however many boundaries" do
    ids = Array.new(5) { create(:authorization_boundary).id }
    queries = []
    callback = ->(*, payload) { queries << payload[:sql] unless payload[:name].in?([ "SCHEMA", "TRANSACTION" ]) }
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { described_class.weekly(ids, now: now) }

    expect(queries.size).to eq(1)
  end

  it "returns nothing for no boundaries" do
    expect(described_class.weekly([], now: now)).to eq({})
  end
end
