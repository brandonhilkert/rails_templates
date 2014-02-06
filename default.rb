# Application settings
environment '
    config.generators do |g|
      g.test_framework :rspec, fixture: false
      g.helper = false
      g.assets = false
      g.view_specs = false
    end
'
environment 'config.time_zone = "Eastern Time (US & Canada)"'
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

gem_group :development, :test do
  gem "rspec-rails"
  gem "pry"
  gem "sqlite3"
  gem "better_errors"
  gem "binding_of_caller"
end

gem_group :test do
  gem "factory_girl_rails"
  gem "capybara"
  gem "selenium-webdriver"
  gem "database_cleaner"
  gem "shoulda-matchers"
  gem "rspec-rails"
end

gem_group :development do
  gem "quiet_assets"
end

gem_group :production do
  gem "pg"
  gem "rails_12factor"
  gem "heroku-deflater"
end

gem "anjlab-bootstrap-rails", :require => "bootstrap-rails",
                                :github => "anjlab/bootstrap-rails"
gem "font-awesome-rails"
gem "passenger"

run "bundle install"
run "bundle binstubs rspec-core"


create_file "Procfile" do <<-FILE
web: bundle exec passenger start -p $PORT --max-pool-size 3
FILE
end

# Setup rspec
generate "rspec:install"

create_file "spec/support/capybara.rb" do <<-FILE
require 'capybara/rails'
require 'capybara/rspec'

RSpec.configure do |config|
  Capybara.javascript_driver = :selenium
end
FILE
end

create_file "spec/support/database_cleaner.rb" do <<-FILE
RSpec.configure do |config|
  config.before(:each) do
    DatabaseCleaner.strategy = :transaction
    DatabaseCleaner.start
  end

  config.after(:each) do
    DatabaseCleaner.clean
  end
end
FILE
end

create_file "spec/support/factory_girl.rb" do <<-FILE
RSpec.configure do |config|
  config.include FactoryGirl::Syntax::Methods
end
FILE
end

create_file "spec/support/helpers.rb", ""

create_file "app/assets/javascripts/init.js.coffee" do <<-FILE
window.App ||= {}
FILE
end
append_file "app/assets/javascripts/application.js", "//= require init"

create_file "app/assets/stylesheets/application.css.scss" do <<-FILE
/*
 *= require_self
 */

@import "twitter/bootstrap";
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

ActionMailer::Base.default_url_options = {
  host: ENV["EMAIL_DOMAIN"]
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

  create_file "app/workers/sample_worker.rb" do <<-FILE
class SampleWorker
  include Sidekiq::Worker

  def perform

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
