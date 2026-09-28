require "rails_helper"
require "rake"

RSpec.describe "lib/tasks/ksi.rake", type: :task do
  before(:all) do
    Rails.application.load_tasks if Rake::Task.tasks.empty?
  end

  let(:task) { Rake::Task["ksi:import"] }

  before { task.reenable }

  def ksi_catalog = ControlCatalog.find_by(source: "FedRAMP 20x")

  it "imports the vendored snapshot" do
    expect { task.invoke }.to output(/imported FedRAMP 2026\.09\.13\.02/).to_stdout

    expect(ksi_catalog.version).to eq("2026.09.13.02")
  end

  it "[true] is a dry run — it reports, and writes nothing" do
    expect { task.invoke("true") }.to output(/would import FedRAMP/).to_stdout

    expect(ksi_catalog).to be_nil
  end

  it "exits non-zero when the import is refused" do
    refused = FedrampKsiImportService::Result.new(status: :refused, version: "x", changes: {}, errors: [ "/: bad" ])
    allow(FedrampKsiImportService).to receive(:new).and_return(instance_double(FedrampKsiImportService, call: refused))

    expect { task.invoke }.to raise_error(SystemExit) { |e| expect(e.status).to eq(1) }
                                .and output(/REFUSED/).to_stdout
  end
end
