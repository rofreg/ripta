source 'https://rubygems.org'

ruby '2.3.2'

gem 'sinatra'
gem 'sinatra-contrib'
gem 'thin'
gem 'sprockets'
gem 'sprockets-helpers'
gem 'rerun'

gem 'dotenv'
gem 'json'
gem 'gtfs-realtime', git: 'https://github.com/rofreg/gtfs-realtime.git', branch: 'master'
gem 'rollbar'
gem 'newrelic_rpm'

group :development do
  gem 'sqlite3'
end

group :production do
  gem 'mysql2'
  gem 'rack-ssl-enforcer'
end