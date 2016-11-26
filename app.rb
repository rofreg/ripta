# to run: rerun -- rackup

require 'sinatra'

GTFS::Realtime.configure do |config|
  config.static_feed = "http://www.ripta.com/googledata/current/google_transit.zip"
  config.trip_updates_feed = "http://realtime.ripta.com:81/api/tripupdates"
  config.vehicle_positions_feed = "http://realtime.ripta.com:81/api/vehiclepositions"
  config.service_alerts_feed = "http://realtime.ripta.com:81/api/servicealerts"
  config.database_path = "sqlite://database.db"
end

# Refresh GTFS Realtime data every 10 seconds
Thread.new do
  loop do
    GTFS::Realtime.refresh_realtime_feed!
    sleep 10
  end
end

get '/' do
  # send_file File.expand_path('index.html', settings.public_folder)
  erb :get_location, layout: :default
end

post '/' do
  @stops = GTFS::Realtime::Stop.nearby(params["latitude"].to_f, params["longitude"].to_f)
  erb :pick_stop, layout: :default
end

get '/stops/:id' do
  @stop = GTFS::Realtime::Stop[params[:id]]
  @stop_times = @stop.stop_times_for_today
  erb :stop, layout: :default
end