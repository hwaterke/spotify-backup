require 'sinatra'
require 'spotify-client'
require 'yaml'
require 'json'
require 'rack/utils'
require 'uri'
require 'net/http'
require 'base64'
require 'pp'
require 'slim'
require 'rest-client'

# Patch the SPotify library
Spotify::Client.class_eval { public :run }

CONFIG = YAML.load_file('config.yml')

helpers do
  def getTokenWithCode(code)
    puts "Grabbing token with code #{code}"
    uri = URI.parse('https://accounts.spotify.com/api/token')

    req = Net::HTTP::Post.new(uri)
    req.set_form_data({
      code: code,
      redirect_uri: CONFIG['REDIRECT_URL'],
      grant_type: 'authorization_code',
      client_id: CONFIG['CLIENT_ID'],
      client_secret: CONFIG['CLIENT_SECRET']
    })

    puts req
    puts req.body

    http = Net::HTTP.new(uri.hostname, uri.port)
    http.use_ssl = true
    res = http.request(req)

    raise "Error while grabbing token: #{res.body}" if res.code != '200'
    content =  JSON.parse(res.body)
    CONFIG.merge!(content)
    CONFIG[:token_date] = Time.now
    CONFIG[:token_expiry_date] = Time.now + content['expires_in']

    File.write('config.yml', YAML.dump(CONFIG))
  end

  def refresh_token
    puts 'Refreshing token'
    raise 'No refresh token' unless CONFIG['refresh_token']
    uri = URI.parse('https://accounts.spotify.com/api/token')

    req = Net::HTTP::Post.new(uri)
    req.set_form_data({
      refresh_token: CONFIG['refresh_token'],
      grant_type: 'refresh_token',
      client_id: CONFIG['CLIENT_ID'],
      client_secret: CONFIG['CLIENT_SECRET']
    })

    puts req
    puts req.body

    http = Net::HTTP.new(uri.hostname, uri.port)
    http.use_ssl = true
    res = http.request(req)

    raise "Error while grabbing token: #{res.body}" if res.code != '200'
    content =  JSON.parse(res.body)
    pp content
    CONFIG.merge!(content)
    CONFIG[:token_date] = Time.now
    CONFIG[:token_expiry_date] = Time.now + content['expires_in']

    File.write('config.yml', YAML.dump(CONFIG))
  end
end

get '/login' do
  scopes = 'playlist-read-private playlist-read-collaborative user-library-read'
  redirect 'https://accounts.spotify.com/authorize?' +
    Rack::Utils.build_nested_query({
      response_type: 'code',
      client_id: CONFIG['CLIENT_ID'],
      scope: scopes,
      redirect_uri: CONFIG['REDIRECT_URL']
    })
end

# This is called by Spotify
get '/callback' do
  getTokenWithCode(params['code'])
end

get '/save' do
  refresh_token unless CONFIG['token_expiry_date'] and CONFIG['token_expiry_date'] < Time.now

  client = Spotify::Client.new({
    access_token: CONFIG['access_token'],
    raise_errors: true
  })

  File.write('data/me.yml', YAML.dump(client.me))

  all_tracks = []
  tr = client.me_tracks
  next_link = tr['next']
  all_tracks += tr['items']

  while next_link do
    puts next_link
    tr = client.run(:get, next_link.gsub('https://api.spotify.com', ''), [200])
    next_link = tr['next']
    all_tracks += tr['items']
  end

  File.write('data/tracks.yml', YAML.dump(all_tracks))

end

get '/tracks' do
  @tracks = YAML.load_file('data/tracks.yml')
  slim :tracks
end