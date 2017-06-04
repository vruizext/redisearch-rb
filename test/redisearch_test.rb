require 'test_helper'

class RediSearchTest < Minitest::Test
  def setup
    @redis_server = RedisTestServer.new
    fail('error starting redis-server') unless @redis_server.start
    sleep(0.25)
    @redis_client = Redis.new(url: ENV['REDIS_URL'])
    @redis_client.flushdb
    @redisearch_client = RediSearch.new('test_idx', @redis_client)
    @schema = ['title', 'TEXT', 'WEIGHT', '2.0',
               'director', 'TEXT', 'WEIGHT', '1.0',
               'year', 'NUMERIC']

  end

  def teardown
    @redis_server&.stop
  end

  def test_that_it_has_a_version_number
    refute_nil ::RediSearch::VERSION
  end

  def test_create_idx
    assert @redisearch_client.create_index(@schema)
    info = @redis_client.call(['FT.INFO', 'test_idx'])
    assert_includes(info, 'test_idx')
  end

  def test_create_idx_fails_with_wrong_schema
    @schema << ['foo', 'BAR', 'WEIGHT', 'woz']
    assert_raises(Redis::CommandError) { @redisearch_client.create_index(@schema) }
  end

  def test_drop_idx
    assert(@redisearch_client.create_index(@schema))
    assert(@redisearch_client.drop_index)
    assert_raises(Redis::CommandError) { @redisearch_client.info }
  end

  def test_add_doc
    assert(@redisearch_client.create_index(@schema))
    doc = ['title', 'Lost in translation', 'director', 'Sofia Coppola', 'year', '2004']
    assert(@redisearch_client.add_doc('id_1', doc))
    assert_includes(@redis_client.call(['FT.SEARCH', 'test_idx', 'lost']).to_s, 'Lost in translation')
  end

  def test_add_docs
    assert(@redisearch_client.create_index(@schema))
    docs = [['id_1', ['title', 'Lost in translation', 'director', 'Sofia Coppola', 'year', '2004']],
            ['id_2', ['title', 'Ex Machina', 'director', 'Alex Garland', 'year', '2014']]]
    assert(@redisearch_client.add_docs(docs))
    search_result = @redis_client.call(['FT.SEARCH', 'test_idx', 'lost|ex'])
    assert_includes(search_result.to_s, 'Lost in translation')
    assert_includes(search_result.to_s, 'Ex Machina')
  end

  def test_search_simple_query
    assert(@redisearch_client.create_index(@schema))
    docs = [['id_1', ['title', 'Lost in translation', 'director', 'Sofia Coppola', 'year', '2004']],
            ['id_2', ['title', 'Ex Machina', 'director', 'Alex Garland', 'year', '2014']]]
    assert(@redisearch_client.add_docs(docs))
    matches = @redisearch_client.search('lost|machina', { withscores: true })
    assert_equal(2, matches.count)
    assert matches.any? { |doc| 'Lost in translation' == doc['title'] }
    assert matches.any? { |doc| 'Ex Machina' == doc['title'] }
    matches.each { |doc| assert doc['score'].to_i > 0 }
  end

  def test_search_field_selector
    assert(@redisearch_client.create_index(@schema))
    doc = ['id_1', ['title', 'Lost in translation', 'director', 'Sofia Coppola', 'year', '2004']]
    assert(@redisearch_client.add_doc(*doc))
    matches = @redisearch_client.search('@title:lost')
    assert_equal(1, matches.count)
    assert 'Lost in translation' == matches[0]['title']
    assert_empty @redisearch_client.search('@director:lost')
    assert_equal 1, @redisearch_client.search('@year:[2004 2005]').count
  end
end
