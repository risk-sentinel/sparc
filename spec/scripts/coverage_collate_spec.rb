# frozen_string_literal: true

require "rails_helper"
require "open3"
require "stringio"
require "tmpdir"
load Rails.root.join("script/ci/coverage_collate.rb").to_s

# #1264 — CI merges the shards' coverage here and applies the floor to the
# total. It must refuse a set of results with a shard missing (that would read
# as "coverage fell"), and its filters, groups and floor must be spec_helper's.
RSpec.describe "script/ci/coverage_collate.rb" do
  describe CoverageCollate do
    describe ".shard_problem" do
      it "accepts one result from every shard" do
        expect(described_class.shard_problem(%w[rspec-shard-1-of-2 rspec-shard-0-of-2])).to be_nil
      end

      it "names the shards that are missing" do
        expect(described_class.shard_problem(%w[rspec-shard-0-of-4 rspec-shard-2-of-4]))
          .to eq("coverage is missing shard(s) 1, 3 of 4")
      end

      it "refuses a result that is not a shard's" do
        expect(described_class.shard_problem(%w[rspec-shard-0-of-1 RSpec])).to include("not shard results")
      end

      it "refuses shards that disagree on how many there are" do
        expect(described_class.shard_problem(%w[rspec-shard-0-of-2 rspec-shard-1-of-3])).to include("not shard results")
      end
    end

    # What the collate block configures, recorded instead of applied: running
    # SimpleCov.collate inside this suite would replace the suite's own coverage.
    def recorded_settings
      recorder = Class.new do
        attr_reader :settings

        def initialize = @settings = { skip: [], group: {} }
        def formatter(value) = @settings[:formatter] = value
        def coverage_dir(value) = @settings[:coverage_dir] = value
        def skip(path) = @settings[:skip] << path
        def group(name, path) = @settings[:group][name] = path
        def minimum_coverage(value) = @settings[:minimum_coverage] = value
      end.new

      allow(SimpleCov).to receive(:collate) do |files, profile, &block|
        @collated = [ files, profile ]
        recorder.instance_eval(&block)
      end
      yield
      recorder.settings
    end

    describe ".collate" do
      it "applies spec_helper.rb's filters, groups and floor to the merged result" do
        helper = Rails.root.join("spec/spec_helper.rb").read
        settings = recorded_settings { described_class.collate(%w[a.json b.json]) }

        expect(@collated).to eq([ %w[a.json b.json], "rails" ])
        expect(settings[:skip]).to eq(helper.scan(/^\s*skip "([^"]+)"/).flatten)
        expect(settings[:group]).to eq(helper.scan(/^\s*group "([^"]+)", "([^"]+)"/).to_h)
        expect(settings[:minimum_coverage]).to eq(Integer(helper[/^\s*minimum_coverage (\d+)/, 1]))
        expect(settings[:coverage_dir]).to eq("coverage")
        expect(settings[:formatter].new.formatters)
          .to eq([ SimpleCov::Formatter::HTMLFormatter, SimpleCov::Formatter::JSONFormatter ])
      end
    end

    describe ".main" do
      around { |example| Dir.mktmpdir("coverage-collate-") { |dir| @dir = dir; example.run } }

      def resultset(name)
        File.join(@dir, "#{name}.json").tap { |path| File.write(path, JSON.generate(name => { "coverage" => {} })) }
      end

      def run_main(argv)
        err = StringIO.new
        status = nil
        settings = recorded_settings { status = described_class.main(argv, err: err) }
        [ status, err.string, settings ]
      end

      it "merges a complete set of shard results" do
        files = [ resultset("rspec-shard-0-of-2"), resultset("rspec-shard-1-of-2") ]
        status, err, = run_main(files)

        expect(status).to eq(0)
        expect(err).to be_empty
        expect(@collated).to eq([ files, "rails" ])
      end

      it "refuses, without merging, when a shard is missing" do
        status, err, = run_main([ resultset("rspec-shard-0-of-2") ])

        expect(status).to eq(1)
        expect(err).to include("missing shard(s) 1 of 2")
        expect(SimpleCov).not_to have_received(:collate)
      end

      it "refuses when given no results" do
        status, err, = run_main([])

        expect(status).to eq(1)
        expect(err).to include("no coverage resultsets given")
        expect(SimpleCov).not_to have_received(:collate)
      end
    end
  end

  it "runs as a command, and refuses an incomplete set before merging" do
    Dir.mktmpdir("coverage-collate-cli-") do |dir|
      path = File.join(dir, ".resultset.json")
      File.write(path, JSON.generate("rspec-shard-0-of-2" => { "coverage" => {} }))
      out, err, status = Open3.capture3(RbConfig.ruby, Rails.root.join("script/ci/coverage_collate.rb").to_s, path,
                                        chdir: Rails.root.to_s)

      expect(status.exitstatus).to eq(1), out
      expect(err).to include("coverage is missing shard(s) 1 of 2")
    end
  end
end
