# frozen_string_literal: true

require "rspec"
require "open3"
require "tmpdir"

RSpec.describe "Shared Inbox engine boot" do
  it "boots a Rails application and runs the prepare callback again on reload" do
    plugin_root = File.expand_path("../..", __dir__)
    Dir.mktmpdir("shared-inbox-boot-") do |app_root|
      stdout, stderr, status = Open3.capture3(
        {
          "SHARED_INBOX_PLUGIN_ROOT" => plugin_root,
          "SHARED_INBOX_BOOT_APP_ROOT" => app_root,
        },
        RbConfig.ruby,
        File.join(__dir__, "fixtures/boot_engine.rb"),
      )
      expect(status.success?).to eq(true), "Rails boot failed:\n#{stdout}\n#{stderr}"
      expect(stdout).to include("Engine boot and prepare callback passed")
    end
  end
end
