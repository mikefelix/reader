require 'active_record/base'

rails_root = Rails.root || File.dirname(__FILE__) + '/../..'
redis_config = YAML.load_file(rails_root.to_s + '/config/redis.yml')
rails_env = Rails.env || 'production'
pool_size = Integer(ENV["SIDEKIQ_CONNECTION_POOL_SIZE"].to_i || 15)

Sidekiq.configure_server do |config|
  config.redis = { :url => redis_config[rails_env], :namespace => 'reader' }
  if ENV["DATABASE_URL"]
    ENV["DATABASE_URL"] = "#{ENV["DATABASE_URL"]}?pool=#{pool_size}"
    ActiveRecord::Base.establish_connection
  end

end

Sidekiq.configure_client do |config|
  config.redis = { :url => redis_config[rails_env], :namespace => 'reader' }
end
