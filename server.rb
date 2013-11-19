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

class FaceBook
  include EM::Deferrable

  def query(lat, long)
    facebook_access_query = {
      client_id: 555303184529223,
      client_secret: 'b3b4979f09263905ffffa4a469425f68',
      grant_type: 'client_credentials'
    }
    faq = EM::HttpRequest.new('https://graph.facebook.com/oauth/access_token').get(query: facebook_access_query)
    faq.callback do
      token = faq.response.match(/access_token=(.*)$/)[1]

      facebook_query = {
        type: :place,
        center: "#{lat},#{long}",
        distance: 10000,
        access_token: token
      }
      facebook = EM::HttpRequest.new('https://graph.facebook.com/search').get(
        query: facebook_query)

      facebook.callback do
        locations = []

        data = JSON.parse(facebook.response)['data']
        data.each do |item|
          locations << { type: 'facebook',
                         name: item['name'],
                         lat: item['location']['latitude'],
                         long: item['location']['longitude']}

        end
        succeed(locations)
      end

      facebook.errback do
        puts "Facebook Query Failed"
        fail("FaceBook")
      end
    end

    faq.errback do
      puts "Facebook access token request failed"
      fail("FaceBook")
    end
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

        query_cb = Proc.new do |locations|
          locations.each do |location|
            ws.send(location.to_json)
          end
        end

        error_cb = Proc.new do |type|
          ws.sed({error: "#{type} call failed"}.to_json)
        end

        [FaceBook].each do |klass|
          g = klass.new
          g.query(lat, long)
          g.callback(&query_cb)
          g.errback(&error_cb)
        end
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
