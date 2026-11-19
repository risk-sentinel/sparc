# frozen_string_literal: true

require "rails_helper"
require "open3"
require "stringio"
load Rails.root.join("script/ci/spec_shard.rb").to_s

# #1264 — the `test` job runs as shards, and this script decides which spec
# files each one runs. A file dealt to no shard would silently stop running.
#
# In-process through SpecShard, plus one run of the real command line.
RSpec.describe "script/ci/spec_shard.rb" do
  def run(*argv, **options)
    out = StringIO.new
    err = StringIO.new
    status = SpecShard.main(argv, out: out, err: err, **options)
    [ status, out.string.lines(chomp: true), err.string ]
  end

  describe "the repository's own spec files" do
    let(:every_file) { Dir.glob("spec/**/*_spec.rb", base: Rails.root.to_s).sort }

    it "puts every spec file in exactly one of four shards" do
      lists = (0...4).map { |index| run(index.to_s, "4").then { |status, files, _| status.zero? ? files : [] } }

      expect(lists.flatten.sort).to eq(every_file)
      expect(lists.flatten.uniq.size).to eq(every_file.size)
      expect(lists).to all(be_present)
    end

    it "includes this file, which has no timing entry" do
      expect(every_file).to include("spec/scripts/ci_spec_shard_spec.rb")
    end

    it "names only files that exist in the timing table" do
      timed = JSON.parse(File.read(SpecShard::TIMINGS)).keys
      expect(timed - every_file).to be_empty, "spec_timings.json lists files that are gone: #{(timed - every_file).inspect}"
    end
  end

  describe "dealing" do
    let(:timings) { { "spec/slow_spec.rb" => 100.0, "spec/medium_spec.rb" => 60.0, "spec/small_spec.rb" => 50.0 } }
    let(:files) { timings.keys + [ "spec/untimed_spec.rb" ] }

    it "gives the slowest file a shard of its own and balances the rest against it" do
      shards = SpecShard.deal(files, timings, 2)

      expect(shards[0][:files]).to eq([ "spec/slow_spec.rb", "spec/untimed_spec.rb" ])
      expect(shards[1][:files]).to eq([ "spec/medium_spec.rb", "spec/small_spec.rb" ])
      expect(shards.map { _1[:seconds] }).to eq([ 100.0 + SpecShard::DEFAULT_SECONDS, 110.0 ])
    end

    it "is the same deal whatever order the files arrive in" do
      expect(SpecShard.deal(files.reverse, timings, 3)).to eq(SpecShard.deal(files, timings, 3))
    end

    it "leaves a shard empty rather than fail when there are more shards than files" do
      shards = SpecShard.deal([ "spec/only_spec.rb" ], {}, 3)
      expect(shards.map { _1[:files].size }).to eq([ 1, 0, 0 ])
    end
  end

  describe "the command line" do
    it "prints the shard's files sorted, and its size on stderr" do
      Dir.mktmpdir("spec-shard-") do |root|
        FileUtils.mkdir_p(File.join(root, "spec/models"))
        %w[spec/b_spec.rb spec/a_spec.rb spec/models/c_spec.rb spec/support.rb].each { FileUtils.touch(File.join(root, _1)) }

        status, files, err = run("0", "1", root: root, timings: { "spec/b_spec.rb" => 120.0 })

        expect(status).to eq(0)
        expect(files).to eq(%w[spec/a_spec.rb spec/b_spec.rb spec/models/c_spec.rb])
        expect(err).to eq("shard 1 of 1: 3 files, about 2.0 minutes of examples\n")
      end
    end

    it "refuses an index outside the shards" do
      status, files, err = run("4", "4")
      expect(status).to eq(1)
      expect(files).to be_empty
      expect(err).to include("shard index 4 is outside 0...4")
    end

    it "refuses arguments that are not two integers" do
      [ [], [ "0" ], [ "0", "four" ], [ "0", "4", "extra" ] ].each do |argv|
        status, files, err = run(*argv)
        expect(status).to eq(2), argv.inspect
        expect(files).to be_empty
        expect(err).to include("usage:")
      end
    end

    it "runs as CI runs it" do
      out, err, status = Open3.capture3(RbConfig.ruby, Rails.root.join("script/ci/spec_shard.rb").to_s, "0", "4")

      expect(status).to be_success, err
      expect(out.lines(chomp: true)).to eq(run("0", "4")[1])
    end
  end
end
