# Super simple sample app. You'll need to create config and log directories to make everything happy, but beyond that, should be smooth sailing with the latest from GitHub (not in a gem release just yet).
# mkdir -p config
# mkdir -p log

require 'rubygems'
require 'rack/cache'
require 'sinatra'
require 'pg'
require 'active_record'
require 'thinking-sphinx'
require 'ts-delayed-delta'
require 'thinking_sphinx/deltas/delayed_delta'
require 'thinking_sphinx/deltas/datetime_delta'
require 'yaml'


yamlstring = ''
File.open("config/database.yml", "r") { |f|
    yamlstring = f.read
}
db = YAML::load(yamlstring)

set :port,3000 

use Rack::Cache do
 set :verbose, true
 set :metastore,   "file:/var/cache/rack/meta"
 set :entitystore, "file:/var/cache/rack/body"
end


helpers do

  def protected!
    unless authorized?
      response['WWW-Authenticate'] = %(Basic realm="Restricted Area")
      throw(:halt, [401, "Not authorized\n"])
    end
  end

  def authorized?
    @auth ||=  Rack::Auth::Basic::Request.new(request.env)
    @auth.provided? && @auth.basic? && @auth.credentials && @auth.credentials == ['admin', '456b7016a916a4b178dd72b947c152b7']
  end

end

# switch ip to internal ec2 ip address
ThinkingSphinx::Configuration.instance.address  = "#{db['sphinx']}"
ActiveRecord::Base.establish_connection(
  'host'     => db['host'],
  'adapter'  => 'postgresql',
  'encoding' => 'unicode',
  'database' => db['database'],
  'pool'     => 100,
  'prepared_statements' => false,
  'username' => db['username'],
  'password' => db['password'],
  'port'     => db['port']
)

ActiveSupport.on_load :active_record do
  include ThinkingSphinx::ActiveRecord
end

def clear_connections
  ActiveRecord::Base.clear_active_connections!
end

def pretty_time(hours)
  Time.now + (3600 * hours)
end

def get_stats

  a          = pretty_time(-1).to_s.split(/\s+/)
  start_time = a[0] + 'T' + a[1]
  a          = pretty_time(0).to_s.split(/\s+/)
  end_time   = a[0] + 'T' + a[1]

  staging="---------[staging]---------\n" +`#{ENV['HOME']}/CloudWatch/bin/mon-get-stats IndexTimeCheck --start-time #{start_time} --end-time #{end_time} --period 60 --statistics "Average" --namespace "AWS:Sphinx" --dimensions "InstanceId=#{ENV['STAGING_INSTANCE_ID']}"  -I #{ENV['AWS_ACCESS_KEY']} -S #{ENV['AWS_SECRET_KEY']}`
  prod="---------[production]---------\n" + `#{ENV['HOME']}/CloudWatch/bin/mon-get-stats IndexTimeCheck --start-time #{start_time} --end-time #{end_time} --period 60 --statistics "Average" --namespace "AWS:Sphinx" --dimensions "InstanceId=#{ENV['INSTANCE_ID']}" -I #{ENV['AWS_ACCESS_KEY']} -S #{ENV['AWS_SECRET_KEY']}`

  all = staging + "\n\n" + prod
  all
end

class Post < ActiveRecord::Base
  define_index do
    indexes text

    has view_count, like_count,comments_count, media_type, created_at, updated_at
    has "CRC32(media_type)", :as => :media_type_crc, :type => :integer
    where "deleted = 'f' and text like e'%\\x23%' "
    set_property :delta => :datetime, :threshold => 1.minutes
  end
end

get '/all' do
  '<ul>' + 
  Post.search.collect { |a| "<li>#{a.text}</li>" }.join('') +
  '</ul>'
end

get '/healthcheck' do
  response["Cache-Control"] = "max-age=0, public"
  "health ok\n" +
  '<ul>' + 
  Post.search.collect { |a| "<li>#{a.text}</li>" }.join('') +
  '</ul>'
end

get '/test' do
  ThinkingSphinx::Configuration.instance.address 
end

get '/search/:hashtag' do
  response["Cache-Control"] = "max-age=0, public"
  params[:hashtag] +
  '<ul>' + 
  Post.search(params[:hashtag]).collect { |a| "<li>#{a.text}</li>" }.join('') +
  '</ul>' + '<!-- ' + clear_connections.inspect + ' -->'
end

get '/serverstats' do
  protected!
  response["Cache-Control"] = "max-age=600, public"
  '<pre>' +
  get_stats +
  '</pre>'
end
