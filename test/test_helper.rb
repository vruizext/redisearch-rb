$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)

require 'logger'
require 'minitest/autorun'
require 'subprocess'

require './lib/redisearch'

class RedisTestServer
  DEFAULT_REDIS_PATH = 'redis-server'
  DEFAULT_REDIS_CONFIG = './test/redis/redis.conf'

  attr_reader :process

  def initialize(path = nil, config = nil)
    @path = path || DEFAULT_REDIS_PATH
    @config = config || DEFAULT_REDIS_CONFIG
  end

  def start
    @process = Subprocess.popen([@path, @config])
    sleep(0.25)
  rescue => error
    Logger.new(STDERR).error(error.message)
    @process = nil
  end

  def stop
    @process.terminate
  rescue => error
    Logger.new(STDERR).error(error.message)
  end
end
