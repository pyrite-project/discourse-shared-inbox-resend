# frozen_string_literal: true

require "rspec"
require "open3"

RSpec.describe "Shared Inbox site setting registration" do
  %w[shared-inbox-with-resend discourse-shared-inbox-resend support-inbox].each do |directory_name|
    it "registers admin settings when installed as #{directory_name}, even while disabled" do
      stdout, stderr, status = Open3.capture3(
        { "SHARED_INBOX_PLUGIN_ROOT" => File.expand_path("../..", __dir__) },
        RbConfig.ruby,
        File.join(__dir__, "fixtures/register_site_settings.rb"),
        directory_name,
      )
      expect(status.success?).to eq(true), "Plugin registration failed:\n#{stdout}\n#{stderr}"
      expect(stdout).to include("Plugin settings registration passed")
    end
  end
end
