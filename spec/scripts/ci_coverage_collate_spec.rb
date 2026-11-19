# frozen_string_literal: true

require "rails_helper"
require "open3"
require "stringio"
load Rails.root.join("script/ci/coverage_collate.rb").to_s

# #1264 — each test shard records its own coverage; this script merges them
# and applies the floor the whole suite must meet. It must not pass on a
# partial set of shards, and the merged total (not any one shard's) is what
# the floor is held against.
#
# In-process through CoverageCollate, plus runs of the real command line.
RSpec.describe "script/ci/coverage_collate.rb" do
  around { |example| Dir.mktmpdir("coverage-collate-") { |dir| @dir = dir; example.run } }

  # A shard's .resultset.json, covering `lines` of the one source file.
  def resultset(name, lines = [ 1, 1, 1, 1 ])
    path = File.join(@dir, name, ".resultset.json")
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, JSON.generate(name => { "coverage" => { source_file => { "lines" => lines } },
                                             "timestamp" => Time.now.to_i }))
    path
  end

  def source_file
    File.join(@dir, "app/models/thing.rb").tap do |path|
      next if File.exist?(path)

      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, "a = 1\nb = 2\nc = 3\nd = 4\n")
    end
  end

  def command_line(*resultsets)
    Open3.capture3({ "COVERAGE" => nil }, RbConfig.ruby, Rails.root.join("script/ci/coverage_collate.rb").to_s,
                   *resultsets, chdir: @dir)
  end

  describe "which sets of results it accepts" do
    it "accepts every shard of one run" do
      expect(CoverageCollate.problem([ resultset("rspec-shard-0-of-2"), resultset("rspec-shard-1-of-2") ])).to be_nil
    end

    it "names the shard that is missing" do
      expect(CoverageCollate.problem([ resultset("rspec-shard-0-of-4"), resultset("rspec-shard-3-of-4") ]))
        .to eq("coverage is missing shard(s) 1, 2 of 4")
    end

    it "refuses results that are not shard results" do
      expect(CoverageCollate.problem([ resultset("rspec-shard-0-of-1"), resultset("RSpec") ]))
        .to start_with("coverage results are not shard results:")
    end

    it "refuses shards of different runs" do
      expect(CoverageCollate.problem([ resultset("rspec-shard-0-of-2"), resultset("rspec-shard-1-of-4") ]))
        .to start_with("coverage results are not shard results:")
    end

    it "refuses no results at all" do
      expect(CoverageCollate.problem([])).to eq("no coverage resultsets given")
    end
  end

  describe "the settings it merges with" do
    # Records what the settings block asks of SimpleCov, without merging: a
    # real SimpleCov.collate here would replace this run's own coverage.
    let(:recorder) do
      Class.new do
        def calls = (@calls ||= [])
        def respond_to_missing?(*) = true
        def method_missing(name, *args) = calls << [ name, *args ]
      end.new
    end

    before do
      allow(SimpleCov).to receive(:collate) { |_files, _profile, &settings| recorder.instance_eval(&settings) }
    end

    it "merges the files it was given under the rails profile, and returns success" do
      files = [ resultset("rspec-shard-0-of-1") ]
      expect(CoverageCollate.main(files, err: StringIO.new)).to eq(0)
      expect(SimpleCov).to have_received(:collate).with(files, "rails")
    end

    it "holds the total to the floor and skips what spec_helper.rb skips" do
      CoverageCollate.collate([ resultset("rspec-shard-0-of-1") ])

      helper = Rails.root.join("spec/spec_helper.rb").read
      expect(recorder.calls).to include([ :minimum_coverage, 70 ], [ :coverage_dir, "coverage" ])
      expect(helper).to include("minimum_coverage 70")
      recorder.calls.select { |name, *| %i[skip group].include?(name) }.each do |name, *args|
        expect(helper).to include("#{name} #{args.map(&:inspect).join(', ')}")
      end
      expect(recorder.calls.count { |name, *| name == :skip }).to eq(helper.scan(/^\s+skip "/).size)
      expect(recorder.calls.count { |name, *| name == :group }).to eq(helper.scan(/^\s+group "/).size)
    end

    it "does not merge a set with a shard missing" do
      err = StringIO.new
      expect(CoverageCollate.main([ resultset("rspec-shard-1-of-2") ], err: err)).to eq(1)
      expect(err.string).to eq("coverage is missing shard(s) 0 of 2\n")
      expect(SimpleCov).not_to have_received(:collate)
    end
  end

  describe "the command line, as CI runs it" do
    it "passes when the shards together meet the floor though neither does alone" do
      _out, err, status = command_line(resultset("rspec-shard-0-of-2", [ 1, 1, 0, 0 ]),
                                       resultset("rspec-shard-1-of-2", [ 0, 0, 1, 1 ]))

      expect(status).to be_success, err
      report = JSON.parse(File.read(File.join(@dir, "coverage/coverage.json")))
      expect(report.dig("coverage", "app/models/thing.rb", "lines")).to eq([ 1, 1, 1, 1 ])
      expect(report.dig("total", "lines", "percent")).to eq(100.0)
    end

    it "fails when the merged total is under the floor" do
      out, err, status = command_line(resultset("rspec-shard-0-of-2", [ 1, 1, 0, 0 ]),
                                      resultset("rspec-shard-1-of-2", [ 1, 0, 0, 0 ]))

      expect(status).not_to be_success
      expect(out + err).to match(/coverage.*50(\.0+)?%.*70/im)
    end

    it "fails, naming the shard, when one is missing" do
      _out, err, status = command_line(resultset("rspec-shard-0-of-2"))

      expect(status.exitstatus).to eq(1)
      expect(err).to include("coverage is missing shard(s) 1 of 2")
      expect(File).not_to exist(File.join(@dir, "coverage"))
    end
  end
end
