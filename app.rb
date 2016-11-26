# to run: rerun -- rackup

require 'dotenv'
Dotenv.load

require 'sinatra'

GTFS::Realtime.configure do |config|
  config.static_feed = "http://www.ripta.com/googledata/current/google_transit.zip"
  config.trip_updates_feed = "http://realtime.ripta.com:81/api/tripupdates"
  config.vehicle_positions_feed = "http://realtime.ripta.com:81/api/vehiclepositions"
  config.service_alerts_feed = "http://realtime.ripta.com:81/api/servicealerts"
  config.database_path = ENV["DATABASE_PATH"]
end

# Refresh GTFS Realtime data every 10 seconds
Thread.new do
  loop do
    sleep 10
    GTFS::Realtime.refresh_realtime_feed!
  end
end

get '/' do
  erb :get_location, layout: :default
end

post '/' do
  # find nearby stops
  latitude, longitude = params["latitude"].to_f, params["longitude"].to_f
  @stops = GTFS::Realtime::Stop.nearby(latitude, longitude)

  # find VERY nearby stops
  @close_stops = @stops.select{|s| s.distance(latitude, longitude) < 0.005}.sort_by{|s| s.distance(latitude, longitude)}

  # if the closest stop is RIGHT nearby, auto-choose it
  if @close_stops.first && @close_stops.first.distance(latitude, longitude) < 0.0005
    redirect to("/stops/#{@close_stops.first.id}")
  end

  erb :pick_stop, layout: :default
end

get '/stops' do
  @stops = GTFS::Realtime::Stop.all
  @geolocation = params["geolocation"]

  erb :all_stops, layout: :default
end

get '/stops/:id' do
  @stop = GTFS::Realtime::Stop[params[:id]]
  @stop_times = @stop.stop_times_for_today
  erb :stop, layout: :default
end