require 'test_helper'

class RediSearchTest < Minitest::Test
  def setup
    @redis_server = RedisTestServer.new(6388)
    fail('error starting redis-server') unless @redis_server.start
    sleep(0.25)
    @redis_client = Redis.new(url: @redis_server.url)
    @redis_client.flushdb
    @redisearch_client = RediSearch.new('test_idx', @redis_client)
    @schema = ['title', 'TEXT', 'WEIGHT', '2.0',
               'director', 'TEXT', 'WEIGHT', '1.0',
               'genre', 'TAG',
               'year', 'NUMERIC', 'SORTABLE']

  end

  def teardown
    @redis_server&.stop
    sleep(0.25)
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
    doc = ['title', 'Lost in translation', 'director', 'Sofia Coppola', 'year', '2004']
    @redisearch_client.add_doc('id_1', doc)
    @redisearch_client.drop_index
    assert_raises(Redis::CommandError) { @redisearch_client.info }
    assert(@redis_client.hgetall('id_1').empty?)
  end

  def test_drop_idx_keep_documents
    @redisearch_client.create_index(@schema)
    doc = ['title', 'Lost in translation', 'director', 'Sofia Coppola', 'year', '2004']
    @redisearch_client.add_doc('id_1', doc)
    @redisearch_client.drop_index({ keepdocs: true })
    assert(@redis_client.hgetall('id_1').any?)
  end

  def test_add_doc
    assert(@redisearch_client.create_index(@schema))
    doc = ['title', 'Lost in translation', 'director', 'Sofia Coppola', 'year', '2004']
    assert(@redisearch_client.add_doc('id_1', doc))
    assert_includes(@redis_client.call(['FT.SEARCH', 'test_idx', 'lost']).to_s, 'Lost in translation')
  end

  def test_add_doc_replace
    assert(@redisearch_client.create_index(@schema))
    doc = ['title', 'Lost in translation', 'director', 'Sofia Coppola', 'year', '2004']
    assert(@redisearch_client.add_doc('id_1', doc))

    doc = ['title', 'Lost in translation', 'director', 'SC', 'year', '2005']
    assert_raises(Redis::CommandError) { @redisearch_client.add_doc('id_1', doc) }
    assert(@redisearch_client.add_doc('id_1', doc, { replace: true }))

    result = @redis_client.call(['FT.SEARCH', 'test_idx', 'SC'])
    assert result.any?
    assert result.to_s.include?('2005')
    assert result.to_s.include?('id_1')
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

  def test_get_by_id
    assert(@redisearch_client.create_index(@schema))
    docs = [['id_1', ['title', 'Lost in translation', 'director', 'Sofia Coppola', 'year', '2004']],
            ['id_2', ['title', 'Ex Machina', 'director', 'Alex Garland', 'year', '2014']]]
    assert(@redisearch_client.add_docs(docs))
    doc = @redisearch_client.get_by_id('id_1')
    assert_equal('id_1', doc['id'])
    assert_equal('Lost in translation', doc['title'])
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
    assert_equal([], @redisearch_client.search('foobarwozzz'))
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

  def test_search_inkeys
    @redisearch_client.create_index(@schema)
    docs = [['id_1', ['title', 'Lost in translation', 'director', 'Sofia Coppola', 'year', '2004']],
            ['id_2', ['title', 'Ex Machina', 'director', 'Alex Garland', 'year', '2014']]]
    assert(@redisearch_client.add_docs(docs))
    matches = @redisearch_client.search('(lost|garland)', { infields: ['1', 'title'] })
    assert_equal 1, matches.count
    matches = @redisearch_client.search('(lost|garland)', { infields: ['2', 'director', 'title'] })
    assert_equal 2, matches.count
  end

  def test_search_return_keys
    assert(@redisearch_client.create_index(@schema))
    doc = ['id_1', ['title', 'Lost in translation', 'director', 'Sofia Coppola', 'year', '2004']]
    assert(@redisearch_client.add_doc(*doc))
    matches = @redisearch_client.search('@title:lost', { return: ['2', 'title', 'year'] })
    assert_equal 1, matches.count
    assert_nil matches[0]['director']
    assert_equal 'Lost in translation', matches[0]['title']
    assert_equal '2004', matches[0]['year']
  end

  def test_search_sort_by
    @redisearch_client.create_index(@schema)
    docs = [['id_1', ['title', 'Lost in translation', 'director', 'Sofia Coppola', 'year', '2004']],
            ['id_2', ['title', 'Ex Machina', 'director', 'Alex Garland', 'year', '2014']]]
    assert(@redisearch_client.add_docs(docs))
    matches = @redisearch_client.search('@year:[2000 2017]', { sortby: ['year', 'asc'] })
    assert_equal 2, matches.count
    assert_equal 'id_1', matches[0]['id']
    matches = @redisearch_client.search('@year:[2000 2017]', { sortby: ['year', 'desc'] })
    assert_equal 'id_2', matches[0]['id']
  end

  def test_search_limit
    assert(@redisearch_client.create_index(@schema))
    docs = [['id_1', ['title', 'Lost in translation', 'director', 'Sofia Coppola', 'year', '2004']],
            ['id_2', ['title', 'Ex Machina', 'director', 'Alex Garland', 'year', '2014']],
            ['id_3', ['title', 'Terminator', 'director', 'James Cameron', 'year', '1984']],
            ['id_4', ['title', 'Blade Runner', 'director', 'Ridley Scott', 'year', '1982']]]
    assert(@redisearch_client.add_docs(docs))
    matches = @redisearch_client.search('@year:[1980 2017]', { limit: ['0', '3'], sortby: ['year', 'asc'] })
    assert_equal 3, matches.count
    assert_equal 'id_4', matches[0]['id']
    assert_equal 'id_3', matches[1]['id']
    assert_equal 'id_1', matches[2]['id']
    matches = @redisearch_client.search('@year:[1980 2017]', { limit: ['3', '3'], sortby: ['year', 'asc'] })
    assert_equal 1, matches.count
    assert_equal 'id_2', matches[0]['id']
  end

  def test_index_info
    assert(@redisearch_client.create_index(@schema))
    doc = ['id_1', ['title', 'Lost in translation', 'director', 'Sofia Coppola', 'year', '2004']]
    assert(@redisearch_client.add_doc(*doc))
    info = @redisearch_client.info
    assert info.any?
    assert_equal 1, info['num_docs'].to_i
    assert_equal 1, info['max_doc_id'].to_i
    assert_equal 5, info['num_terms'].to_i
  end

  def test_delete_by_id
    assert(@redisearch_client.create_index(@schema))
    docs = [['id_1', ['title', 'Lost in translation', 'director', 'Sofia Coppola', 'year', '2004']],
            ['id_2', ['title', 'Ex Machina', 'director', 'Alex Garland', 'year', '2014']],
            ['id_3', ['title', 'Terminator', 'director', 'James Cameron', 'year', '1984']],
            ['id_4', ['title', 'Blade Runner', 'director', 'Ridley Scott', 'year', '1982']]]
    assert(@redisearch_client.add_docs(docs))
    assert_equal(1, @redisearch_client.delete_by_id('id_1', { dd: false }))
    assert_equal(1, @redisearch_client.delete_by_id('id_2', { dd: true }))
    assert_empty(@redisearch_client.search('@title:lost'))
    assert(@redisearch_client.get_by_id('id_1').any?)
    assert(@redisearch_client.get_by_id('id_2').empty?)
    assert(@redis_client.del('id_1'))
    assert(@redisearch_client.get_by_id('id_1').empty?)
  end

  def test_auto_complete_suggestions
    dict_name = 'test_suggestions'
    @redisearch_client.autocomplete_add(dict_name, 'foobar', 2.0)
    @redisearch_client.autocomplete_add(dict_name, 'foowoz', 1.0)
    @redisearch_client.autocomplete_add(dict_name, 'foomeh', 0.85)
    @redisearch_client.autocomplete_add(dict_name, 'woowoz', 1.0)
    assert_equal(4, @redisearch_client.autocomplete_len(dict_name))
    results = @redisearch_client.autocomplete_get(dict_name, 'foo')
    assert_equal(3, results.count)
    assert_equal('foobar', results.first)
    assert_equal(4, @redisearch_client.autocomplete_get(dict_name, 'foo', { fuzzy: true }).count)
    assert @redisearch_client.autocomplete_del(dict_name, 'foobar').to_i > 0
    refute @redisearch_client.autocomplete_del(dict_name, 'foozzz').to_i > 0
    assert_equal('foowoz', @redisearch_client.autocomplete_get(dict_name, 'foo').first)
  end
end
