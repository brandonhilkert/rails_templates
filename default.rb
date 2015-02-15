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

inject_into_file "Gemfile", after: "source 'https://rubygems.org'" do <<-FILE

ruby "2.2.0"
FILE
end

gem_group :development, :test do
  gem "pry"
end

gem_group :test do
  gem "selenium-webdriver"
  gem "capybara"
end

gem_group :development do
  gem "quiet_assets"
end

gem_group :production do
  gem "rails_12factor"
  gem "heroku-deflater"
end

gem "unicorn"
gem "font-awesome-rails"
gem "bootstrap-sass"
gem "so_meta"
gem "local_time"

run "bundle install"

# Setup unicorn for Heroku
create_file "config/unicorn.rb" do <<-FILE
worker_processes Integer(ENV["WEB_CONCURRENCY"] || 3)
timeout 15
preload_app true

before_fork do |server, worker|
  Signal.trap 'TERM' do
    puts 'Unicorn master intercepting TERM and sending myself QUIT instead'
    Process.kill 'QUIT', Process.pid
  end

  defined?(ActiveRecord::Base) and
    ActiveRecord::Base.connection.disconnect!
end

after_fork do |server, worker|
  Signal.trap 'TERM' do
    puts 'Unicorn worker intercepting TERM and doing nothing. Wait for master to send QUIT'
  end

  defined?(ActiveRecord::Base) and
    ActiveRecord::Base.establish_connection
end
FILE
end

create_file "Procfile" do <<-FILE
web: bundle exec unicorn -p $PORT -c ./config/unicorn.rb
FILE
end

create_file "app/assets/javascripts/init.js.coffee" do <<-FILE
window.App ||= {}
FILE
end
append_file "app/assets/javascripts/application.js", "//= require init"

inject_into_file "app/assets/javascripts/application.js", before: "//= require_tree ." do <<-FILE
//= require bootstrap
FILE
end

create_file "app/assets/stylesheets/application.css.scss" do <<-FILE
/*
 *= require_self
 */

@import "bootstrap";
@import "font-awesome";
FILE
end

remove_file "app/assets/stylesheets/application.css"

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
  gem 'sidekiq', require: "sidekiq/web"
  gem 'sinatra'

  create_file "config/initializers/sidekiq.rb" do <<-FILE
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
worker: bundle exec sidekiq
FILE
  end

  run "bundle install"
end

git :init
append_file ".gitignore", "config/application.yml"

git add: "."
git commit: "-a -m 'Initial commit'"
