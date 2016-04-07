# Application settings
environment '
    config.generators do |g|
      g.helper = false
      g.view_specs = false
    end
'
environment 'config.time_zone = "UTC"'
environment 'config.action_dispatch.x_sendfile_header = "X-Accel-Redirect"', env: "production"
environment 'config.static_cache_control = "public, max-age=31449600" # 1 year', env: "production"

# Setup configuration
create_file "config/application.yml" do <<-FILE
defaults: &defaults

development:
  <<: *defaults

test:
  <<: *defaults
FILE
end

inject_into_file "config/application.rb", before: "module" do <<-FILE
if File.exists?(File.expand_path('../application.yml', __FILE__))
  config = YAML.load(File.read(File.expand_path('../application.yml', __FILE__)))
  config.merge! config.fetch(Rails.env, {})
  config.each do |key, value|
    ENV[key] ||= value.to_s unless value.kind_of? Hash
  end
end

FILE
end

create_file "config/spring.rb" do <<-FILE
Spring.watch "config/application.yml"
FILE
end

inject_into_file "Gemfile", "\n\nruby '2.3.0'", after: "source 'https://rubygems.org'"

gem_group :test do
  gem "selenium-webdriver"
  gem "capybara"
end

gem_group :development do
  gem "quiet_assets"
end

if yes?("Hosted on Heroku?")
  gem_group :production do
    gem "rails_12factor"
    gem "heroku-deflater"
  end
end

gem "puma"
gem "font-awesome-rails"
gem "bootstrap-sass"
gem "so_meta"
gem "local_time"

run "bundle install"

# Setup puma
create_file "config/puma.rb" do <<-FILE
workers Integer(ENV['PUMA_WEB_CONCURRENCY'] || 2)
threads_count = Integer(ENV['PUMA_MAX_THREADS'] || 5)
threads threads_count, threads_count

preload_app!

port        ENV['PORT']     || 3000
environment ENV['RACK_ENV'] || 'development'

on_worker_boot do
  ActiveSupport.on_load(:active_record) do
    ActiveRecord::Base.establish_connection
  end
end
FILE
end

run "bundle binstubs puma"

create_file "Procfile" do <<-FILE
web: bin/puma -C ./config/puma.rb
FILE
end

create_file "app/assets/javascripts/init.coffee" do <<-FILE
window.App ||= {}

App.init = ->

$(document).on "page:change", ->
  App.init()

FILE
end

gsub_file "app/assets/javascripts/application.js", '//= require_tree .', ''
append_file "app/assets/javascripts/application.js", "//= require init"

inject_into_file "app/assets/javascripts/application.js", "//= require bootstrap\n", before: "//= require_tree ."

create_file "app/assets/stylesheets/application.scss" do <<-FILE
/*
 *= require_self
 */

@import "bootstrap-sprockets";
@import "bootstrap";
@import "font-awesome";
FILE
end

remove_file "app/assets/stylesheets/application.css"

gsub_file "app/views/layouts/application.html.erb", '<body>', '<body class="<%= controller_path.gsub(/\//, "-") %> <%= action_name %>">'

# Optional things
#
# Email
if yes?("Email?")
  create_file "config/initializers/setup_email.rb" do <<-FILE
ActionMailer::Base.smtp_settings = {
  :user_name => ENV["SENDGRID_USERNMAE"],
  :password => ENV["SENDGRID_PASSWORD"],
  :domain => ENV["EMAIL_DOMAIN"],
  :address => "smtp.sendgrid.net",
  :port => 587,
  :authentication => :plain,
  :enable_starttls_auto => true
}

# ActionMailer::Base.asset_host = "http://domain.com" if Rails.env.production?

ActionMailer::Base.default_url_options = {
  host: ENV["EMAIL_DOMAIN"],
  only_path: false
}

if Rails.env.development?
  class OverrideMailRecipient
    def self.delivering_email(mail)
      mail.to = ENV["EMAIL_OVERRIDE"]
    end
  end
  ActionMailer::Base.register_interceptor(OverrideMailRecipient)
end
FILE
  end

  inject_into_file "config/application.yml", before: "development" do <<-FILE
  SENDGRID_USERNAME:
  SENDGRID_PASSWORD:
  EMAIL_DOMAIN:

  EMAIL_OVERRIDE:

FILE
  end

end

# Sidekiq
if yes?("Sidekiq?")
  gem 'sidekiq'
  gem 'sinatra'

  create_file "config/initializers/sidekiq.rb" do <<-FILE
require 'sidekiq/web'

if Rails.env.production?
  Sidekiq::Web.use(Rack::Auth::Basic) do |user, password|
    user == ENV["SIDEKIQ_USERNAME"] && password == ENV["SIDEKIQ_PASSWORD"]
  end
end

Sidekiq.logger = Rails.logger
FILE
  end

  create_file "app/workers/email_worker.rb" do <<-FILE

class EmailWorker
  include Sidekiq::Worker

  def perform(klass, name, *args)
    klass.constantize.send(name.to_sym, *args).deliver
  end
end
FILE
  end

  inject_into_file "config/application.yml", before: "development" do <<-FILE
  SIDEKIQ_USERNAME:
  SIDEKIQ_PASSWORD:

FILE
  end

  append_file "Procfile" do <<-FILE
worker: bin/sidekiq
FILE
  end

  run "bundle install"
  run "bundle binstubs sidekiq"

  inject_into_file "config/routes.rb", "\n  mount Sidekiq::Web => '/sidekiq'\n", after: "Rails.application.routes.draw do"
end

git :init
append_file ".gitignore", "config/application.yml"

git add: "."
git commit: "-a -m 'Initial commit'"

run "bundle exec spring binstub --all"
