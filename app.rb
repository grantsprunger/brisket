#app.rb
require 'sinatra'
require 'sinatra-websocket'
require 'json'
require 'active_record'
require 'mysql2'
require 'linear-regression'

set :public_folder, File.dirname(__FILE__) + '/static'
set :server, 'thin'
set :sockets, []
set :cooking, false
set :bind, '0.0.0.0'

#Active Record Settings
ActiveRecord::Base.establish_connection(
  :adapter  => "mysql2",
  :host     => "127.0.0.1",
  :username => ENV['BRISKET_DATABSE_USER'],
  :password => ENV['BRISKET_DATABSE_PASSWORD'],
  :database => ENV['BRISKET_DATABSE']
)

BrisketEvent = Class.new(ActiveRecord::Base)

after do
  ActiveRecord::Base.connection.close
end

get '/' do
  # Responds to html and websocket requests

  if !request.websocket?
    erb :index
  else
    request.websocket do |ws|
      ws.onopen do
        ws_obj = {:websocket => ws, :publisher => false}
        settings.sockets << ws_obj
        
        # Tell the client if other clients are already cooking
        ws_obj[:websocket].send(JSON.generate({:cooking => settings.cooking}))
      end
      ws.onmessage do |msg|
        EM.next_tick {
          settings.sockets.each_with_index do |s, i| 
            if s[:publisher] == false
              s[:websocket].send(msg)
            end
          end 
        }
      end
      ws.onclose do
        settings.sockets.each_with_index  do |s, i|
          if ws.equal? s[:websocket]
            settings.sockets.delete_at(i)
          end
        end
      end
    end
  end
end

post '/cooking' do
  if params[:cooking] == 'true'
    settings.cooking = true
    BrisketEvent.create({:event => 'cooking', :probe0 => 0, :probe1 => 0})
  elsif params[:cooking] == 'false'
    settings.cooking = false
  end

  EM.next_tick {
    settings.sockets.each_with_index do |s, i| 
      if s[:publisher] == false
        s[:websocket].send(JSON.generate({:cooking => settings.cooking}))
      end
    end 
  }
end

post '/cooking_time' do
  # Receives cooking time update from javascript frontened, publishes update to websocket

  if params[:cooking_time]
    EM.next_tick {
      settings.sockets.each_with_index do |s, i| 
        if s[:publisher] == false
          s[:websocket].send(JSON.generate({:cooking_time => params[:cooking_time]}))
        end
      end 
    }
  end
end

get '/trend' do
  # Returns JSON past 120 second temperature trend for probes
  # {"probe0": "up", "probe1": "down"}

  content_type :json
  
  sql = 'SELECT 120 - TIMESTAMPDIFF(SECOND, created_at, NOW()) as idx, AVG(probe0) as probe0, AVG(probe1) as probe1 ' \
        'FROM brisket_events ' \
        'WHERE event = \'temperature\' AND created_at > NOW() - INTERVAL 120 SECOND ' \
        'GROUP BY idx ' \
        'ORDER BY idx ASC;'

  results = BrisketEvent.find_by_sql(sql)

  # probe 0 linear
  probe0_x = []
  probe0_y = []

  # probe 1 linear
  probe1_x = []
  probe1_y = []

  # Shove the time series into an array
  results.each do |t|
    probe0_x << t[:idx]
    probe0_y << t[:probe0]

    probe1_x << t[:idx]
    probe1_y << t[:probe1]
  end

  # It's more efficient for ruby to do the linear regression than mysql
  probe0_regression = Regression::Linear.new(probe0_x, probe0_y)
  probe1_regression = Regression::Linear.new(probe1_x, probe1_y)

  {:probe0 => probe0_regression.slope > 0 || nil ? 'up' : 'down', :probe1 => probe1_regression.slope > 0 || nil ? 'up' : 'down'}.to_json
end

get '/chart' do
  # Return JSON past 30 minutes of average temperatures
  # {"chartx": [30,29], "probe0": [55,56], "probe1": [77,78]}

  content_type :json

  sql = 'SELECT 31 - TIMESTAMPDIFF(MINUTE, created_at, NOW()) - 1 as idx, AVG(probe0) as probe0, AVG(probe1) as probe1 ' \
        'FROM brisket_events ' \
        'WHERE event = \'temperature\' AND created_at > NOW() - INTERVAL 31 MINUTE ' \
        'GROUP BY idx ' \
        'ORDER BY idx ASC;'
  
  results = BrisketEvent.find_by_sql(sql)

  # Chart Arrays
  chart_x  = []
  probe0_y = []
  probe1_y = []

  results.each do |t|
    chart_x  << t[:idx].to_i
    probe0_y << t[:probe0].to_f
    probe1_y << t[:probe1].to_f
  end

  {:chartx => chart_x, :probe0y => probe0_y, :probe1y => probe1_y}.to_json
end

post '/publish' do
  # Receives temperature update from the Arduino

  if params[:probe0] && params[:probe1]

    # Save the temperature event to the database
    BrisketEvent.create({:event => 'temperature', :probe0 => params[:probe0], :probe1 => params[:probe1]})

    EM.next_tick {
      settings.sockets.each_with_index do |s, i| 
        # Don't send the temp update back to the Arduino only to web clients
        if s[:publisher] == false
          s[:websocket].send(JSON.generate({:temperature_update => {:probe0 => params[:probe0], :probe1 => params[:probe1]}}))
        end
      end 
    }
  end
end