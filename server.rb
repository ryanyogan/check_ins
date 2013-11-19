require 'eventmachine'
require 'em-websocket'
require 'em-http'
require 'nokogiri'
require 'json'
require 'pp'
require 'thin'

class GeoCode
  include EM::Deferrable

  def query(postal_code)
    query = {
      postal: postal_code,
      geoit: :xml 
    }
    request = EM::HttpRequest.new('http://geocoder.ca/').get(query: query)
    request.callback do
      doc  = Nokogiri.parse(request.response)
      lat  = doc.search('latt').inner_text
      long = doc.search('longt').inner_text

      succeed(lat,long)
    end
    request.errback { fail }
  end
end

EM.run do
  EM::WebSocket.start(host: '0.0.0.0', port: 8080) do |ws|
    ws.onopen { puts "Client Connected to server" }

    ws.onmessage do |msg|
      geocode = GeoCode.new
      geocode.query(msg)
      geocode.callback do |lat, long|
        ws.send({type: 'location',
                  lat: lat,
                 long: long}.to_json)
      end
      geocode.errback do
        puts "Failed Geocoding of zipcode"
        ws.send({error: "Failed Geocoding"}.to_json)
      end
    end

    ws.onclose { puts "closed" }
    ws.onerror { |e| puts "Error: #{e.message}"}
  end
end
