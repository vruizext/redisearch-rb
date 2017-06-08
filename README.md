[![Gem Version](https://badge.fury.io/rb/redisearch-rb.svg)](https://badge.fury.io/rb/redisearch-rb) ![travis-ci](https://travis-ci.org/vruizext/redisearch-rb.svg?branch=master)

# redisearch-rb

A simple Ruby client for RediSearch module
http://redisearch.io/


## Installation

First of all, you need to install RediSearch, if you haven't yet:

1. Install Redis 4.0.0-rc3 https://github.com/antirez/redis/releases/tag/4.0-rc3
2. Install RediSearch 0.16 http://redisearch.io/Quick_Start/
3. Edit your `redis.conf` file and add a `loadmodule` directive to load the RediSearch module built in the step 2.

To install this gem, add this line to your application's Gemfile:

```ruby
gem 'redisearch-rb'
```

And then execute:

    $ bundle install

Or install it yourself as:

    $ gem install redisearch-rb


In order to run the tests, it's necessary to set some env variables (see .env.example):

- `REDIS_SERVER_PATH`, the path to the `redis-server` executable

- `REDIS_MODULE_PATH`, the path to the RediSearch module

- `REDIS_PORT`, the TCP port used by Redis server

- `REDIS_TEST_URL` is the Redis url where the server will be available. The port has to match the port specified in
 `REDIS_PORT` or in the redis config file

- `REDIS_CONF_PATH`, is the path to your redis conf file. You can configure the port and the path to RediSearch module in
a config file if you prefer. If the path to the config file is given, `REDIS_MODULE_PATH` and `REDIS_PORT` will be
ignored


## Usage

```ruby
require 'redisearch-rb'

redis = Redis.new(REDIS_URL)
redisearch_client = RediSearch.new('test_idx', redis)

schema = ['title', 'TEXT', 'WEIGHT', '2.0',
          'director', 'TEXT', 'WEIGHT', '1.0',
          'year', 'NUMERIC']

redisearch_client.create_index(schema)
# => "OK"

docs = [['id_1', ['title', 'Lost in translation', 'director', 'Sofia Coppola', 'year', '2004']],
        ['id_2', ['title', 'Ex Machina', 'director', 'Alex Garland', 'year', '2014']]]
redisearch_client.add_docs(docs)
# => ["OK", "OK"]

# See query syntax here: http://redisearch.io/Query_Syntax/
redisearch_client.search('lost|machina', { withscores: true })
# => [{"title"=>"Ex Machina", "director"=>"Alex Garland", "year"=>"2014", "score"=>"2", "id"=>"id_2"},
#   {"title"=>"Lost in translation", "director"=>"Sofia Coppola", "year"=>"2004", "score"=>"1", "id"=>"id_1"}]

redisearch_client.search('@year:[2003 2004]')
# => [{"title"=>"Lost in translation", "director"=>"Sofia Coppola", "year"=>"2004", "id"=>"id_1"}]
```

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/vruizext/redisearch-rb.


## License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).

