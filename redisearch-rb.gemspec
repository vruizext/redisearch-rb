# coding: utf-8

Gem::Specification.new do |spec|
  spec.name          = "redisearch-rb"
  spec.version       =  '0.0.1'
  spec.authors       = ["Victor Ruiz"]
  spec.email         = ["vruizext@gmail.com"]

  spec.summary       = "Ruby client for RediSearch"
  spec.description   = "Ruby client for RediSearch"
  spec.homepage      = "https://github.com/vruizext/redisearch-rb"
  spec.license       = "MIT"

  spec.files         = `git ls-files`.split("\n")
  spec.test_files    = `git ls-files -- {test}/*`.split("\n")
end
