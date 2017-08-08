$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)

require 'logger'
require 'minitest/autorun'
require 'subprocess'
require 'dotenv'

require './lib/redisearch-rb'

Dotenv.load('./.env')

class RedisTestServer
  DEFAULT_REDIS_PATH = 'redis-server'

  attr_reader :process, :url

  def initialize(default_port = nil)
    @command = [ENV['REDIS_SERVER_PATH'] || DEFAULT_REDIS_PATH]
    @port = ENV['REDIS_PORT'] || default_port
  end

  def start
    build_args
    @process = Subprocess.popen(@command)
    @url = "redis://127.0.0.1:#{@port}"
  rescue => error
    Logger.new(STDERR).error(error.message)
    @process = nil
  end

  def stop
    @process&.terminate
  rescue => error
    Logger.new(STDERR).error(error.message)
  end

  private

  def build_args
    if ENV['REDIS_CONF_PATH'].to_s.empty?
      @command << "--port #{@port}" unless @port.to_s.empty?
      @command << "--loadmodule #{ENV['REDIS_MODULE_PATH']}" unless ENV['REDIS_MODULE_PATH'].to_s.empty?
    else
      @command << ENV['REDIS_CONF_PATH']
    end
  end
end
