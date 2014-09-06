#genomatic.rb
require 'active_record'
require 'mysql2'

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

probe0 = 0.25
probe1 = 0.5

loop do
  probe0 = probe0 + 0.001
  probe1 = probe1 - 0.0013
  BrisketEvent.create({:event => 'temperature', :probe0 => probe0, :probe1 => probe1})
  sleep(1)
end

