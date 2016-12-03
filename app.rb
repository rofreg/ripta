require_relative 'init'
require 'sinatra'

# Require SSL in production, so that geolocation works in Chrome
if ENV['RACK_ENV'] == 'production'
  require 'rack/ssl'
  use Rack::SSL
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
  @close_stops = @stops.select{|s| s.distance(latitude, longitude) < 0.002}.sort_by{|s| s.distance(latitude, longitude)}

  # if the closest stop is RIGHT nearby, auto-choose it
  if @close_stops.first && @close_stops.first.distance(latitude, longitude) < 0.0001
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
  @stop = GTFS::Realtime::Stop.find(params[:id])
  @stop_times = @stop.stop_times_for_today

  # Only show upcoming buses, not past ones
  @stop_times = @stop_times.select do |stop_time|
    scheduled_time = stop_time.scheduled_departure_time || stop_time.scheduled_arrival_time
    actual_time = stop_time.actual_departure_time || stop_time.actual_arrival_time

    scheduled_time > Time.now - 120 || (actual_time && actual_time > Time.now - 120)
  end

  # TODO: update gem to handle case where bus arrives + leaves early
  # right now, the bus re-appears on the schedule at that point :|

  erb :stop, layout: :default
end