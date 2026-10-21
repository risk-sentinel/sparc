# frozen_string_literal: true

require "rails_helper"

# #785 / #1104 — production refuses to boot on local-disk storage unless the
# operator acknowledges it, and the refusal is a named error a caller can
# rescue or match, not a bare RuntimeError.
RSpec.describe "config/initializers/zz_storage_posture.rb" do
  let(:initializer) { Rails.root.join("config/initializers/zz_storage_posture.rb") }

  def with_env(vars)
    original = vars.keys.index_with { |k| ENV.fetch(k, nil) }
    vars.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
    yield
  ensure
    original.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
  end

  before do
    allow(Rails.application.config).to receive(:after_initialize) { |&block| block.call }
    allow(Rails.env).to receive(:production?).and_return(true)
    allow(StorageUrl).to receive(:local?).and_return(true)
    allow(Rails.logger).to receive(:warn)
  end

  it "refuses local disk in production with UnsafeLocalStorageError" do
    with_env("SECRET_KEY_BASE_DUMMY" => nil, "SPARC_ALLOW_LOCAL_STORAGE" => nil) do
      expect { load initializer }
        .to raise_error(StorageUrl::UnsafeLocalStorageError, /LOCAL DISK in production/)
    end
  end

  it "warns instead when the operator acknowledged local storage" do
    with_env("SECRET_KEY_BASE_DUMMY" => nil, "SPARC_ALLOW_LOCAL_STORAGE" => "true") do
      expect { load initializer }.not_to raise_error
      expect(Rails.logger).to have_received(:warn).with(/SPARC_ALLOW_LOCAL_STORAGE=true/)
    end
  end
end
