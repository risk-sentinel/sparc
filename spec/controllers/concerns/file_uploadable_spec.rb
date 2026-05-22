# frozen_string_literal: true

require "rails_helper"
require "tempfile"
require "zip"

RSpec.describe FileUploadable do
  # Minimal harness to exercise the private zip-bomb check.
  let(:harness) do
    Class.new do
      include FileUploadable
      public :reject_if_zip_bomb!
    end.new
  end

  describe "#reject_if_zip_bomb! (#510)" do
    context "non-excel file_type" do
      it "is a no-op for json uploads" do
        fake = instance_double("ActionDispatch::Http::UploadedFile",
                               original_filename: "foo.json",
                               path: "/tmp/nonexistent")
        expect { harness.reject_if_zip_bomb!(fake, "json") }.not_to raise_error
      end
    end

    context ".xls (binary OLE2, not zip)" do
      it "is a no-op (only .xlsx is zip-format)" do
        fake = instance_double("ActionDispatch::Http::UploadedFile",
                               original_filename: "legacy.xls",
                               path: "/tmp/nonexistent")
        expect { harness.reject_if_zip_bomb!(fake, "excel") }.not_to raise_error
      end
    end

    context ".xlsx with uncompressed total under the cap" do
      it "passes" do
        allow(SparcConfig).to receive(:max_upload_bytes).and_return(10.megabytes)
        Tempfile.create([ "small", ".xlsx" ]) do |tmp|
          Zip::File.open(tmp.path, create: true) do |zip|
            zip.get_output_stream("xl/sheet.xml") { |io| io.write("a" * 1024) } # ~1 KB
          end
          fake = instance_double("ActionDispatch::Http::UploadedFile",
                                 original_filename: "small.xlsx",
                                 path: tmp.path)
          expect { harness.reject_if_zip_bomb!(fake, "excel") }.not_to raise_error
        end
      end
    end

    context ".xlsx with uncompressed total over the cap" do
      it "raises with a clear message naming the cap and the suggested env var" do
        allow(SparcConfig).to receive(:max_upload_bytes).and_return(1.kilobyte) # tiny cap
        Tempfile.create([ "bomb", ".xlsx" ]) do |tmp|
          # 10 KB of payload across two entries; cap is 1 KB → over.
          Zip::File.open(tmp.path, create: true) do |zip|
            zip.get_output_stream("xl/sheet1.xml") { |io| io.write("a" * 5.kilobytes) }
            zip.get_output_stream("xl/sheet2.xml") { |io| io.write("a" * 5.kilobytes) }
          end
          fake = instance_double("ActionDispatch::Http::UploadedFile",
                                 original_filename: "bomb.xlsx",
                                 path: tmp.path)
          expect { harness.reject_if_zip_bomb!(fake, "excel") }
            .to raise_error(/uncompressed XLSX size.*MB exceeds upload limit.*MB.*SPARC_MAX_UPLOAD_MB/)
        end
      end
    end
  end
end
