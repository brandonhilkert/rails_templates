# Setup root landing page
generate(:controller, "landing index")
route "root to: 'landing#index'"

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
application_settings = <<-TEMPLATE
defaults: &defaults

development:
  <<: *defaults

test:
  <<: *defaults
TEMPLATE
create_file "config/application.yml", application_settings

application_setup = <<-TEMPLATE
if File.exists?(File.expand_path('../application.yml', __FILE__))
  config = YAML.load(File.read(File.expand_path('../application.yml', __FILE__)))
  config.merge! config.fetch(Rails.env, {})
  config.each do |key, value|
    ENV[key] ||= value.to_s unless value.kind_of? Hash
  end
end
TEMPLATE
run "echo '#{application_setup}' >> config/application.rb"

gem_group :development, :test do
  gem "rspec-rails"
  gem "pry"
  gem "sqlite3"
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
end

gem "anjlab-bootstrap-rails", :require => "bootstrap-rails",
                                :github => "anjlab/bootstrap-rails"
gem "font-awesome-rails"
gem "unicorn"

run "bundle install"
run "bundle binstubs rspec-core"
run "bundle binstubs rake"

# Setup unicorn for Heroku
unicorn_config = <<-TEMPLATE
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
TEMPLATE
create_file "config/unicorn.rb", unicorn_config

procfile = <<-TEMPLATE
web: bundle exec unicorn -p $PORT -c ./config/unicorn.rb
TEMPLATE
create_file "Procfile", procfile

# Setup rspec
generate "rspec:install"
run "mkdir spec/support"

capybara = <<-TEMPLATE
require 'capybara/rails'
require 'capybara/rspec'

RSpec.configure do |config|
  Capybara.javascript_driver = :selenium
end
TEMPLATE
create_file "spec/support/capybara.rb", capybara

database_cleaner = <<-TEMPLATE
RSpec.configure do |config|
  config.before(:each) do
    DatabaseCleaner.strategy = :transaction
    DatabaseCleaner.start
  end

  config.after(:each) do
    DatabaseCleaner.clean
  end
end
TEMPLATE
create_file "spec/support/database_cleaner.rb", database_cleaner

factory_girl = <<-TEMPLATE
RSpec.configure do |config|
  config.include FactoryGirl::Syntax::Methods
end
TEMPLATE
create_file "spec/support/factory_girl.rb", factory_girl

create_file "spec/support/helpers.rb", ""

time_helper = <<-TEMPLATE
module TimeHelper
  def timeago(time, options = {})
    options[:class] ||= "timeago"
    content_tag(:time, time.to_s, options.merge(datetime: time.getutc.iso8601)) if time
  end
end
TEMPLATE
create_file "app/helpers/time_helper.rb", time_helper

get "http://timeago.yarp.com/jquery.timeago.js", "vendor/assets/javascripts/jquery.timeago.js"

init = <<-TEMPLATE
window.App ||= {}
TEMPLATE
create_file "app/assets/javascripts/init.js.coffee", init
run "echo '//= require init' >> app/assets/javascripts/application.js"

app_timeago = <<-TEMPLATE
App.TimeAgo =
  replaceTimes: ->
    $("time.timeago").timeago()
TEMPLATE
create_file "app/assets/javascripts/app.timeago.js.coffee", app_timeago
run "echo '//= require app.timeago' >> app/assets/javascripts/application.js"


git :init
run "echo 'config/application.yml' >> .gitignore"

git add: "."
git commit: "-a -m 'Initial commit'"
