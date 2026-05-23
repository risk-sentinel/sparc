# frozen_string_literal: true

require "rails_helper"
require "tempfile"
require "zip"

RSpec.describe FileUploadable do
  # Minimal harness to exercise the private validation methods.
  let(:harness) do
    Class.new do
      include FileUploadable
      public :reject_if_zip_bomb!, :validate_content_type!,
             :validate_syntactic_structure!, :reject_if_executable_signature!
    end.new
  end

  # Build a fake ActionDispatch::Http::UploadedFile-like double pointing at
  # an on-disk tempfile with controlled content.
  def fake_upload(filename:, bytes:)
    tmp = Tempfile.new([ "fileup", File.extname(filename) ])
    tmp.binmode
    tmp.write(bytes)
    tmp.flush
    instance_double("ActionDispatch::Http::UploadedFile",
                    original_filename: filename,
                    path: tmp.path)
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

  describe "#validate_content_type! (#509)" do
    context "extension matches actual content" do
      it "passes valid JSON labeled .json" do
        fake = fake_upload(filename: "good.json", bytes: '{"hello":"world"}')
        expect { harness.validate_content_type!(fake) }.not_to raise_error
      end

      it "passes valid XML labeled .xml" do
        fake = fake_upload(filename: "good.xml", bytes: %(<?xml version="1.0"?><root/>))
        expect { harness.validate_content_type!(fake) }.not_to raise_error
      end

      it "passes valid XLSX (zip) labeled .xlsx" do
        Tempfile.create([ "good", ".xlsx" ]) do |tmp|
          Zip::File.open(tmp.path, create: true) do |zip|
            zip.get_output_stream("xl/sheet.xml") { |io| io.write("<x/>") }
          end
          fake = instance_double("ActionDispatch::Http::UploadedFile",
                                 original_filename: "good.xlsx",
                                 path: tmp.path)
          expect { harness.validate_content_type!(fake) }.not_to raise_error
        end
      end
    end

    context "extension does NOT match actual content (attack vector)" do
      it "rejects a PE32 binary mislabeled as .json" do
        # PE32 (Windows executable) magic bytes: "MZ" followed by header.
        pe32_header = "MZ" + ("\x00" * 60) + "PE\x00\x00".b
        fake = fake_upload(filename: "trojan.json", bytes: pe32_header)
        expect { harness.validate_content_type!(fake) }
          .to raise_error(/extension \.json expects.*actual content type is/)
      end

      it "rejects a zip mislabeled as .json" do
        Tempfile.create([ "fake", ".json" ]) do |tmp|
          Zip::File.open(tmp.path, create: true) do |zip|
            zip.get_output_stream("foo.txt") { |io| io.write("hello") }
          end
          fake = instance_double("ActionDispatch::Http::UploadedFile",
                                 original_filename: "fake.json",
                                 path: tmp.path)
          expect { harness.validate_content_type!(fake) }
            .to raise_error(/extension \.json expects.*actual content type is/)
        end
      end

      it "rejects a PDF mislabeled as .yaml" do
        pdf_bytes = "%PDF-1.4\n%\xE2\xE3\xCF\xD3\n".b
        fake = fake_upload(filename: "fake.yaml", bytes: pdf_bytes)
        expect { harness.validate_content_type!(fake) }
          .to raise_error(/extension \.yaml expects.*actual content type is/)
      end
    end

    context "extension not in allowlist" do
      it "is a no-op (extension layer already rejected)" do
        fake = fake_upload(filename: "weird.bin", bytes: "abc")
        expect { harness.validate_content_type!(fake) }.not_to raise_error
      end
    end
  end

  describe "#validate_syntactic_structure! (#509)" do
    context "json" do
      it "passes valid JSON" do
        fake = fake_upload(filename: "ok.json", bytes: '{"a":1,"b":[2,3]}')
        expect { harness.validate_syntactic_structure!(fake, "json") }.not_to raise_error
      end

      it "rejects malformed JSON with a clear message" do
        fake = fake_upload(filename: "bad.json", bytes: '{"a":')
        expect { harness.validate_syntactic_structure!(fake, "json") }
          .to raise_error(/not valid JSON/)
      end
    end

    context "yaml" do
      it "passes valid YAML" do
        fake = fake_upload(filename: "ok.yaml", bytes: "a: 1\nb:\n  - 2\n  - 3\n")
        expect { harness.validate_syntactic_structure!(fake, "yaml") }.not_to raise_error
      end

      it "rejects malformed YAML" do
        fake = fake_upload(filename: "bad.yaml", bytes: ":\n  - bad indent: [unbalanced")
        expect { harness.validate_syntactic_structure!(fake, "yaml") }
          .to raise_error(/not valid YAML/)
      end
    end

    context "xml / xccdf" do
      it "passes valid XML via XmlSecurity (XXE-safe)" do
        fake = fake_upload(filename: "ok.xml", bytes: %(<?xml version="1.0"?><root><child/></root>))
        expect { harness.validate_syntactic_structure!(fake, "xml") }.not_to raise_error
      end

      it "rejects malformed XML" do
        fake = fake_upload(filename: "bad.xml", bytes: "<root><unclosed>")
        expect { harness.validate_syntactic_structure!(fake, "xml") }
          .to raise_error(/not valid XML/)
      end

      it "applies the same check for xccdf file_type" do
        fake = fake_upload(filename: "ok.xml", bytes: %(<?xml version="1.0"?><Benchmark/>))
        expect { harness.validate_syntactic_structure!(fake, "xccdf") }.not_to raise_error
      end
    end

    context "excel" do
      it "is a no-op for excel (zip-bomb check handles structural validity)" do
        fake = fake_upload(filename: "x.xlsx", bytes: "anything")
        expect { harness.validate_syntactic_structure!(fake, "excel") }.not_to raise_error
      end
    end
  end

  describe "#reject_if_executable_signature! (#509)" do
    context "Windows PE / DOS executable (MZ)" do
      it "rejects PE32 bytes regardless of filename extension" do
        fake = fake_upload(filename: "trojan.json", bytes: "MZ" + ("\x00" * 60) + "PE\x00\x00".b)
        expect { harness.reject_if_executable_signature!(fake) }
          .to raise_error(/detected PE\/MS-DOS executable.*not permitted/)
      end
    end

    context "ELF binary (Linux)" do
      it "rejects ELF magic bytes" do
        fake = fake_upload(filename: "payload.json", bytes: "\x7fELF\x02\x01\x01".b + ("\x00" * 16))
        expect { harness.reject_if_executable_signature!(fake) }
          .to raise_error(/detected ELF binary.*not permitted/)
      end
    end

    context "Mach-O (macOS)" do
      it "rejects Mach-O 64-bit magic bytes" do
        fake = fake_upload(filename: "macbin.json", bytes: "\xfe\xed\xfa\xcf".b + ("\x00" * 16))
        expect { harness.reject_if_executable_signature!(fake) }
          .to raise_error(/detected Mach-O 64-bit.*not permitted/)
      end

      it "rejects Mach-O reverse byte order" do
        fake = fake_upload(filename: "macbin2.json", bytes: "\xcf\xfa\xed\xfe".b + ("\x00" * 16))
        expect { harness.reject_if_executable_signature!(fake) }
          .to raise_error(/detected Mach-O 64-bit \(reverse byte order\).*not permitted/)
      end
    end

    context "Java class file" do
      it "rejects the CAFEBABE magic bytes" do
        fake = fake_upload(filename: "evil.json", bytes: "\xca\xfe\xba\xbe".b + ("\x00" * 16))
        expect { harness.reject_if_executable_signature!(fake) }
          .to raise_error(/detected Java class file.*not permitted/)
      end
    end

    context "WebAssembly module" do
      it "rejects the \\x00asm magic bytes" do
        fake = fake_upload(filename: "module.json", bytes: "\x00asm\x01\x00\x00\x00".b + ("\x00" * 16))
        expect { harness.reject_if_executable_signature!(fake) }
          .to raise_error(/detected WebAssembly module.*not permitted/)
      end
    end

    context "Shebang script" do
      it "rejects shebang prefix" do
        fake = fake_upload(filename: "evil.json", bytes: "#!/bin/sh\nrm -rf /\n")
        expect { harness.reject_if_executable_signature!(fake) }
          .to raise_error(/detected Shebang script.*not permitted/)
      end
    end

    context "happy paths — legitimate content" do
      it "passes a valid JSON document" do
        fake = fake_upload(filename: "ok.json", bytes: '{"a":1,"b":[2,3]}')
        expect { harness.reject_if_executable_signature!(fake) }.not_to raise_error
      end

      it "passes a valid XML document" do
        fake = fake_upload(filename: "ok.xml", bytes: %(<?xml version="1.0"?><root/>))
        expect { harness.reject_if_executable_signature!(fake) }.not_to raise_error
      end

      it "passes a valid YAML document" do
        fake = fake_upload(filename: "ok.yaml", bytes: "key: value\nlist:\n  - 1\n  - 2\n")
        expect { harness.reject_if_executable_signature!(fake) }.not_to raise_error
      end

      it "passes a valid XLSX (zip header is allowed; xlsx context handled by allowlist+bomb check)" do
        Tempfile.create([ "ok", ".xlsx" ]) do |tmp|
          Zip::File.open(tmp.path, create: true) do |zip|
            zip.get_output_stream("xl/sheet.xml") { |io| io.write("<x/>") }
          end
          fake = instance_double("ActionDispatch::Http::UploadedFile",
                                 original_filename: "ok.xlsx",
                                 path: tmp.path)
          expect { harness.reject_if_executable_signature!(fake) }.not_to raise_error
        end
      end
    end
  end
end
