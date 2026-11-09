# frozen_string_literal: true

module SharedInbox
  class Engine < ::Rails::Engine
    engine_name PLUGIN_NAME
    isolate_namespace SharedInbox
    config.autoload_paths << File.join(config.root, "lib")
    config.to_prepare do
      scheduled_job_dir = "#{config.root}/app/jobs/scheduled"
      Rails.autoloaders.main.eager_load_dir(scheduled_job_dir) if Dir.exist?(scheduled_job_dir)
    end
  end
end
