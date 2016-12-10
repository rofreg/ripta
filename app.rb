require_relative 'init'
require 'rack/ssl-enforcer' if Sinatra::Base.production?
require 'rollbar/middleware/sinatra'

# Refresh GTFS Realtime data every 10 seconds
Thread.new do
  loop do
    begin
      sleep 10
      GTFS::Realtime.refresh_realtime_feed!
    rescue StandardError, Net::OpenTimeout => e
      # keep trying, even in the event of an error
      # but let us know about the issue
      Rollbar.error(e)
    end
  end
end

class RiptaApp < Sinatra::Application
  # force SSL, but exclude the Let's Encrypt ownership check URLs
  use Rack::SslEnforcer, except: /^\/.well-known/ if Sinatra::Base.production?

  use Rollbar::Middleware::Sinatra
  register Sinatra::MultiRoute

  configure do
    # use Sprockets for cache-busting assets in the 'public' folder
    Sprockets::Helpers.configure do |config|
      config.environment = Sprockets::Environment.new(root)
    end
  end

  helpers do
    include Sprockets::Helpers
  end


  #################
  # ACTUAL ROUTES #
  #################

  get '/' do
    erb :get_location, layout: :default
  end

  # let's encrypt ownership check
  get '/.well-known/acme-challenge/84HWWx3SMNpIO7e44kST24RMrC5074oHlfaZC8hy6pA' do
    "84HWWx3SMNpIO7e44kST24RMrC5074oHlfaZC8hy6pA.t5WkpflOT8aoWDx6YapIxwoo4T-0wM2UzilGpYCMmiU"
  end

  get '/.well-known/acme-challenge/iLDQBUGV3HT7SumJwHGvvwGQK1vjKhMMENNIoQ77X2M' do
    "iLDQBUGV3HT7SumJwHGvvwGQK1vjKhMMENNIoQ77X2M.t5WkpflOT8aoWDx6YapIxwoo4T-0wM2UzilGpYCMmiU"
  end

  route :get, :post, ['/nearby', '/stops/:id/nearby'] do
    if params[:id]
      # find nearby stops based on stop id
      @stop = GTFS::Realtime::Stop.find(params[:id])
      latitude, longitude = @stop.latitude, @stop.longitude
    elsif params[:latitude]
      # find nearby stops based on submitted location
      latitude, longitude = params[:latitude].to_f, params[:longitude].to_f
      autodetect_stop = true
    else
      redirect to("/")
    end

    @stops = GTFS::Realtime::Stop.nearby(latitude, longitude)

    # find VERY nearby stops
    @close_stops = @stops.select{|s| s.distance(latitude, longitude) < 0.002}.sort_by{|s| s.distance(latitude, longitude)}

    # if the closest stop is RIGHT nearby, auto-choose it
    if autodetect_stop && @close_stops.first && @close_stops.first.distance(latitude, longitude) < 0.0001
      redirect to("/stops/#{@close_stops.first.id}")
    end

    erb :pick_stop, layout: :default
  end

  get '/stops' do
    # optimize loading all stops by loading them as hashes
    @stops = GTFS::Realtime::Stop.connection.select_all("SELECT id, name FROM gtfs_realtime_stops").sort_by{|s| s["name"]}
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

    # TEMPORARY FIX: handle the case where a bus arrives + leaves early
    # after the bus leaves + before its scheduled time, it (wrongly) appears to be on-time.
    # as of 2016-12-04, RIPTA appears to project for all upcoming stops in the next 30 minutes.
    # so a quick-fix, let's hide any scheduled stops in the next 25 minutes without a live update,
    # excluding the routes that don't have any live updates at all.
    # this generally works, but it still has a few corner cases, esp. at terminal stops.
    # e.g. a bus from TF Green may look like it has departed when it actually hasn't

    @stop_times = @stop_times.select do |stop_time|
      should_show_stop_time = stop_time.live?
      should_show_stop_time ||= (stop_time.scheduled_departure_time || stop_time.scheduled_arrival_time) > Time.now + 25*60
      should_show_stop_time ||= GTFS::Realtime::TripUpdate.where(trip_id: stop_time.trip_id).none?
      should_show_stop_time
    end

    # refresh the page every 30 seconds
    @refresh_interval = 30

    erb :stop, layout: :default
  end

  get '/stops/:id/map' do
    @stop = GTFS::Realtime::Stop.find(params[:id])
    redirect to("http://www.google.com/maps/place/#{@stop.latitude},#{@stop.longitude}")
  end

  get '/trips/:id' do
    @trip = GTFS::Realtime::Trip.find(params[:id])
    @vehicle_position = GTFS::Realtime::VehiclePosition.where(trip_id: @trip.id).first
    @trip_update = GTFS::Realtime::TripUpdate.where(trip_id: @trip.id).first
    @stop_time_updates = GTFS::Realtime::StopTimeUpdate.where(trip_update_id: @trip_update.id) if @trip_update
    @delay = (@stop_time_updates.first.arrival_delay || @stop_time_updates.first.departure_delay) if @stop_time_updates&.any?

    erb :trip, layout: :default
  end
end