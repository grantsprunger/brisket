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
  :username => "sql",
  :password => "sql",
  :database => "brisket"
)

class BrisketEvent < ActiveRecord::Base
end

#close the connection
after do
  ActiveRecord::Base.connection.close
end

get '/' do
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
  #Return json of probe0 probe1 trend from mysql
  content_type :json
  
  sql = "SELECT  30 - TIMESTAMPDIFF(SECOND, created_at, NOW()) as idx, AVG(probe0) as probe0, AVG(probe1) as probe1 FROM brisket_events WHERE event = 'temperature' && created_at > NOW() - INTERVAL 30 SECOND GROUP BY idx ORDER BY idx ASC;"
  results = BrisketEvent.find_by_sql(sql)
  
  # probe 0 linear
  probe0x = []
  probe0y = []

  # probe 1 linear
  probe1x = []
  probe1y = []

  # Shove the time series into an array
  results.each do |t|

    probe0x << t[:idx]
    probe0y << t[:probe0]

    probe1x << t[:idx]
    probe1y << t[:probe1]
    
  end

  #Setup linear regression
  probelinear0 = Regression::Linear.new(probe0x, probe0y)
  probelinear1 = Regression::Linear.new(probe1x, probe1y)

  {:probe0 => probelinear0.slope > 0 || nil ? 'up' : 'down', :probe1 => probelinear1.slope > 0 || nil ? 'up' : 'down'}.to_json
end

get '/chart' do
  #Return json of probe0 probe1 temperature data
  content_type :json
  sql = "SELECT 31 - TIMESTAMPDIFF(MINUTE, created_at, NOW()) - 1 as idx, AVG(probe0) as probe0, AVG(probe1) as probe1 FROM brisket_events WHERE event = 'temperature' && created_at > NOW() - INTERVAL 31 MINUTE GROUP BY idx ORDER BY idx ASC;"
  results = BrisketEvent.find_by_sql(sql)

  # cart arrays
  chartx = []
  probe0y = []
  probe1y = []

  # Shove the time series into an array
  results.each do |t|

    chartx  << t[:idx].to_i
    probe0y << t[:probe0].to_f
    probe1y << t[:probe1].to_f
    
  end

  {:chartx => chartx, :probe0y => probe0y, :probe1y => probe1y}.to_json

end

get '/publish' do
  if !request.websocket?
    status 404
  else
    request.websocket do |ws|
      ws.onopen do
        settings.sockets << {:websocket => ws, :publisher => true}
      end
      ws.onmessage do |msg|
        temps = JSON.parse(msg, {:symbolize_names => true})

        if temps[:probe0] && temps[:probe1]
          #Convert from mv to C or F

          #Save to DB
          BrisketEvent.create({:event => 'temperature', :probe0 => temps[:probe0], :probe1 => temps[:probe1]})

          #Send to socket
          EM.next_tick {
            settings.sockets.each_with_index do |s, i| 
              if s[:publisher] == false
                s[:websocket].send(JSON.generate({:temperature_update => temps}))
              end
            end 
          }
        end
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