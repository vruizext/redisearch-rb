# coding: utf-8
require File.expand_path('../lib/redisearch/version', __FILE__)

Gem::Specification.new do |spec|
  spec.name          = "redisearch-rb"
  spec.version       =  RediSearch::VERSION
  spec.authors       = ["Victor Ruiz"]
  spec.email         = ["vruizext@gmail.com"]

  spec.summary       = "Ruby client for RediSearch"
  spec.description   = "Ruby client for RediSearch"
  spec.homepage      = "https://github.com/vruizext/redisearch-rb"
  spec.license       = "MIT"

  spec.files         = `git ls-files`.split("\n")
  spec.test_files    = `git ls-files -- {test}/*`.split("\n")
end
