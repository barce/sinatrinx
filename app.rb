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

# switch ip to internal ec2 ip address
ThinkingSphinx::Configuration.instance.address  = '10.211.166.145'
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
  'health ok' +
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
