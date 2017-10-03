# coding: utf-8
require File.expand_path('../lib/redisearch/version', __FILE__)

Gem::Specification.new do |spec|
  spec.name          = "redisearch-rb"
  spec.version       =  RediSearch::VERSION
  spec.authors       = ["Victor Ruiz"]
  spec.email         = ["vruizext@gmail.com"]

  spec.summary       = "A simple Ruby client library for RediSearch"
  spec.description   = "A simple Ruby client library for RediSearch.
                        RediSearch is a Redis powered search engine, developed by RedisLabs. http://redisearch.io/"
  spec.homepage      = "https://github.com/vruizext/redisearch-rb"
  spec.license       = "MIT"
  spec.required_ruby_version = '> 2.4.0'
  spec.files         = `git ls-files`.split("\n")
  spec.test_files    = `git ls-files -- {test}/*`.split("\n")
end
