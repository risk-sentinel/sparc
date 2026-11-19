# frozen_string_literal: true

require "rails_helper"
require "open3"
require "stringio"
require "tmpdir"
load Rails.root.join("script/ci/spec_shard.rb").to_s

# #1264 — CI runs the suite as shards, each given its files by this script. The
# property that matters is that every spec file runs in exactly one shard, for
# any number of shards, whether or not the timing table knows the file.
RSpec.describe "script/ci/spec_shard.rb" do
  describe SpecShard do
    let(:files) { %w[spec/a_spec.rb spec/b_spec.rb spec/c_spec.rb spec/d_spec.rb spec/e_spec.rb] }

    it "puts every file in exactly one shard" do
      (1..6).each do |total|
        shards = described_class.assign(files, { "spec/c_spec.rb" => 30.0 }, total)

        dealt = shards.flat_map { |s| s[:files] }
        expect(dealt).to match_array(files), "#{total} shard(s)"
        expect(shards.size).to eq(total)
      end
    end

    it "deals the slowest file first, to the lightest shard" do
      shards = described_class.assign(files, { "spec/a_spec.rb" => 10.0, "spec/b_spec.rb" => 9.0 }, 2)

      expect(shards[0][:files].first).to eq("spec/a_spec.rb")
      expect(shards[1][:files].first).to eq("spec/b_spec.rb")
      expect(shards.sum { |s| s[:seconds] }).to be_within(0.001).of(19.0 + (3 * SpecShard::DEFAULT_SECONDS))
    end

    it "weighs a file the timing table does not list as DEFAULT_SECONDS" do
      shards = described_class.assign([ "spec/new_spec.rb" ], {}, 1)

      expect(shards[0]).to eq(seconds: SpecShard::DEFAULT_SECONDS, files: [ "spec/new_spec.rb" ])
    end

    it "deals the same way every time" do
      expect(described_class.assign(files.reverse, {}, 3)).to eq(described_class.assign(files, {}, 3))
    end

    context "from the command line's entry point" do
      around do |example|
        Dir.mktmpdir("spec-shard-") do |dir|
          @root = dir
          files.each { |f| FileUtils.mkdir_p(File.dirname(File.join(dir, f))) && File.write(File.join(dir, f), "") }
          FileUtils.mkdir_p(File.join(dir, "spec/nested"))
          File.write(File.join(dir, "spec/nested/f_spec.rb"), "")
          File.write(File.join(dir, "spec/helper.rb"), "")
          @timings = File.join(dir, "timings.json").tap { |p| File.write(p, JSON.generate("spec/a_spec.rb" => 5.0)) }
          example.run
        end
      end

      def run_main(*argv)
        out = StringIO.new
        err = StringIO.new
        status = SpecShard.main(argv, out: out, err: err, root: @root, timings_path: @timings)
        [ status, out.string.lines.map(&:chomp), err.string ]
      end

      it "prints each shard's files, and together they are every *_spec.rb under spec/" do
        listed = (0..2).flat_map do |index|
          status, out, err = run_main(index.to_s, "3")
          expect(status).to eq(0)
          expect(err).to include("shard #{index + 1} of 3")
          out
        end

        expect(listed).to match_array(files + [ "spec/nested/f_spec.rb" ])
        expect(listed).not_to include("spec/helper.rb")
      end

      it "refuses a shard index outside the total" do
        status, out, err = run_main("3", "3")

        expect(status).to eq(1)
        expect(out).to be_empty
        expect(err).to include("shard index 3 is outside 0...3")
      end
    end
  end

  it "runs as a command, over this repository's spec files" do
    out, err, status = Open3.capture3(RbConfig.ruby, Rails.root.join("script/ci/spec_shard.rb").to_s, "0", "1")

    expect(status.exitstatus).to eq(0), err
    expect(out.lines.map(&:chomp)).to include("spec/scripts/spec_shard_spec.rb")
  end
end
