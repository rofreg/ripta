require 'rubygems'
require 'bundler'

Bundler.require

if Sinatra::Base.development?
  require 'new_relic/rack/developer_mode'
  use NewRelic::Rack::DeveloperMode
end

require './app'
run RiptaApp