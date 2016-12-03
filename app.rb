require_relative 'init'
require 'rack/ssl' if Sinatra::Base.production?
require 'rollbar/middleware/sinatra'

# Refresh GTFS Realtime data every 10 seconds
Thread.new do
  loop do
    begin
      sleep 10
      GTFS::Realtime.refresh_realtime_feed!
    rescue StandardError => e
      # keep trying, even in the event of an error
      # but let us know about the issue
      Rollbar.error(e)
    end
  end
end

class RiptaApp < Sinatra::Application
  use Rack::SSL if Sinatra::Base.production?
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

    erb :trip, layout: :default
  end
end