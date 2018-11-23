require 'redis'

##
# Ruby client for RediSearch module
# http://redisearch.io/
#
class RediSearch
  DEFAULT_WEIGHT = '1.0'

  # Supported options
  # Flags options can be only true or false,
  #
  # { verbatim: true, withscores: true, withsortkey: false }

  OPTIONS_FLAGS = {
    add: [:nosave, :replace, :partial],
    create: [:nooffsets, :nofreqs, :nohl, :nofields],
    del: [:dd],
    drop: [:keepdocs],
    search: [:nocontent, :verbatim, :nostopwords, :withscores, :withsortkeys],
    sugadd: [:incr],
    sugget: [:fuzzy, :withscores],
  }

  # Params options need an array with the values for the option
  #  { limit: ['0', '50'], sortby: ['year', 'desc'], return: ['2', 'title', 'year'] }
  OPTIONS_PARAMS = {
    add: [:language, :payload],
    create: [:stopwords],
    search: [:filter, :return, :infields, :inkeys, :slop, :scorer, :sortby, :limit, :payload],
    sugget: [:max],
  }

  # Create RediSearch client instance
  #
  # @param [String] idx_name name of the index
  # @param [Redis] redis_client Redis instance
  # If no `redis_client` is given, `RediSearch` tries to connect to the default redis url
  # i.e. redis://127.0.0.1:6379
  #
  # @return [RediSearch] a new client instance
  def initialize(idx_name, redis_client = nil)
    @idx_name = idx_name
    @redis = redis_client || Redis.new
  end

  # Create new index with the given `schema`
  # @param [Array] schema
  # @param [Hash] opts options
  # Example:
  #
  #   redisearch = RediSearch.new('my_idx')
  #   redisearch.create_idx(['title', 'TEXT', 'WEIGHT', '2.0', 'director', 'TEXT', 'WEIGHT', '1.0', 'year', 'NUMERIC', 'SORTABLE'])
  #
  # See http://redisearch.io/Commands/#ftcreate
  #
  # @return [String] "OK" on success
  def create_index(schema, opts = {})
    call(ft_create(schema, opts))
  end

  # Drop all the keys in the current index
  #
  # See http://redisearch.io/Commands/#ftdrop
  # @return [String] "OK" on success
  def drop_index(opts = {})
    call(ft_drop(opts))
  end

  # Add a single doc to the index, with the given `doc_id` and `fields`
  #
  # @param [String] doc_id id assigned to the document
  # @param [Array] fields name-value pairs to be indexed
  # @param [Hash] opts optional parameters
  # Example:
  #
  #   redisearch = RediSearch.new('my_idx')
  #   redisearch.add_doc('id_1', ['title', 'Lost in translation', 'director', 'Sofia Coppola'])
  #
  # See http://redisearch.io/Commands/#ftadd
  # @return [String] "OK" on success
  def add_doc(doc_id, fields, opts = {})
    call(ft_add(doc_id, fields, opts))
  end

  # Add a set of docs to the index. Uses redis `multi` to make a single bulk insert.
  #
  # @param [Array] docs array of tuples doc_id-fields e.g. [[`id_1`, [fields_doc_1]], [`id_2`, [fields_doc_2]]]
  #
  # Example:
  #
  #   redisearch = RediSearch.new('my_idx')
  #   docs = [['id_1', ['title', 'Lost in translation', 'director', 'Sofia Coppola'],
  #           ['id_2', ['title', 'Ex Machina', 'director', 'Alex Garland']]
  #   redisearch.add_docs(docs)
  #
  # See http://redisearch.io/Commands/#ftadd
  # @return [String] "OK" on success
  def add_docs(docs, opts = {})
    docs.each { |doc_id, fields| call(ft_add(doc_id, fields, opts))}
  end

  # Search the index with the given `query`
  # @param [String] query text query, see syntax here http://redisearch.io/Query_Syntax/
  # @param [Hash] opts options for the query
  #
  # @return [Array] documents matching the query
  def search(query, opts = {})
    build_docs(call(ft_search(query, opts)), opts)
  end

  # Fetch a document by id
  #
  # @param [String] doc_id id assigned to the document
  # @return [Hash] Hash containing document
  def get_by_id(doc_id)
    Hash[*call(ft_get(doc_id))]
      .tap { |doc| doc['id'] = doc_id unless doc.empty? } || {}
  end

  # Return information and statistics on the index.
  # @return [Hash] info returned by Redis key-value pairs
  #
  def info
    Hash[*call(ft_info)]
  end

  # Deletes a document from the index
  #
  # See http://redisearch.io/Commands/#ftdel
  #
  # @param [String] doc_id id assigned to the document
  # @return [int] 1 if the document was in the index, or 0 if not.
  def delete_by_id(doc_id, opts = {})
    call(ft_del(doc_id, opts))
  end

  # Deletes all documents matching the query
  #
  # @param [String] query in the same format as used in `search`
  # @param [Hash] opts options for the query, same  as in `search`
  # @return [int] count of documents deleted
  def delete_by_query(query, opts = {})
    call(ft_search(query, opts.merge(nocontent: true)))[1..-1].map do |doc_id|
      call(ft_del(doc_id, opts))
    end.sum
  end

  # Adds a string to an auto-complete suggestion dictionary.
  #
  # See https://oss.redislabs.com/redisearch/Commands/#ftsugadd
  #
  # @param [String] dict_name the key used to store the dictionary
  # @param [String] content the string that is going to be indexed
  # @param [Hash] opts optional parameters
  # @return [int] current size of the dictionary
  def autocomplete_add(dict_name, content, score = 1.0, opts = {})
    call(ft_sugadd(dict_name, content, score, opts))
  end

  # Gets completion suggestions for a prefix.
  #
  # See https://oss.redislabs.com/redisearch/Commands/#ftsugadd
  #
  # @param [String] dict_name the key used to store the dictionary
  # @param [String] prefix the prefix to search / complete
  # @param [Hash] opts optional parameters
  # @return [Array] a list of the top suggestions matching the prefix,
  # optionally with score after each entry
  def autocomplete_get(dict_name, prefix, opts = {})
    call(ft_sugget(dict_name, prefix, opts))
  end

  # Deletes a string from an auto-complete suggestion dictionary.
  #
  # See https://oss.redislabs.com/redisearch/Commands/#ftsugdel
  #
  # @param [String] dict_name the key used to store the dictionary
  # @param [String] content the string that is going to be deleted
  # @param [Hash] opts optional parameters
  # @return [int] 1 if the string was found and deleted, 0 otherwise
  def autocomplete_del(dict_name, content)
    call(ft_sugdel(dict_name, content))
  end

  # Gets the current size of an auto-complete suggestion dictionary.
  #
  # See https://oss.redislabs.com/redisearch/Commands/#ftsugdel
  #
  # @param [String] dict_name the key used to store the dictionary
  # @return [int] current size of the dictionary
  def autocomplete_len(dict_name)
    call(ft_suglen(dict_name))
  end

  # Execute arbitrary command in redisearch index
  # Only RediSearch commands are allowed
  #
  # @param [Array] command
  # @return [mixed] The output returned by redis
  def call(command)
    raise ArgumentError.new("unknown/unsupported command '#{command.first}'") unless valid_command?(command.first)
    @redis.with_reconnect { @redis.call(command.flatten) }
  end

  private

  def with_reconnect
    @redis.with_reconnect { yield }
  end

  def multi
    @redis.with_reconnect { @redis.multi { yield } }
  end

  def add(doc_id, fields)
    @redis.call(ft_add(doc_id, fields))
  end

  def ft_create(schema, opts)
    ['FT.CREATE', @idx_name , *serialize_options(opts, :create), 'SCHEMA', *schema]
  end

  def ft_drop(opts)
    ['FT.DROP', @idx_name, *serialize_options(opts, :drop)]
  end

  def ft_info
    ['FT.INFO', @idx_name]
  end

  def ft_add(doc_id, fields, opts = {}, weight =  nil)
    ['FT.ADD', @idx_name , doc_id, weight || DEFAULT_WEIGHT, *serialize_options(opts, :add), 'FIELDS', *fields]
  end

  def ft_add_hash(doc_id, opts = {}, weight =  nil)
    ['FT.ADDHASH', @idx_name , doc_id, weight || DEFAULT_WEIGHT, *serialize_options(opts, :add)]
  end

  def ft_search(query, opts)
    ['FT.SEARCH', @idx_name, *query, *serialize_options(opts, :search)].flatten
  end

  def ft_get(doc_id)
    ['FT.GET', @idx_name , doc_id]
  end

  def ft_mget(doc_ids)
    ['FT.MGET', @idx_name , *doc_ids]
  end

  def ft_del(doc_id, opts)
    ['FT.DEL', @idx_name , doc_id, *serialize_options(opts, :del)]
  end

  def ft_tagvals(field_name)
    ['FT.TAGVALS', @idx_name , field_name]
  end

  def ft_explain(query, opts)
    ['FT.EXPLAIN', @idx_name, *query, *serialize_options(opts, :search)].flatten
  end

  def ft_sugadd(dict_name, content, score, opts)
    ['FT.SUGADD', dict_name , content, score, *serialize_options(opts, :sugadd)]
  end

  def ft_sugdel(dict_name, content)
    ['FT.SUGDEL', dict_name , content]
  end

  def ft_suglen(dict_name)
    ['FT.SUGLEN', dict_name]
  end

  def ft_sugget(dict_name, prefix,opts)
    ['FT.SUGGET', dict_name , prefix, *serialize_options(opts, :sugget)]
  end

  def serialize_options(opts, method)
     [flags_for_method(opts, method), params_for_method(opts, method)].flatten.compact
  end

  def flags_for_method(opts, method)
    OPTIONS_FLAGS[method].to_a.map do |key|
      key.to_s.upcase if opts[key]
    end.compact
  end

  def params_for_method(opts, method)
    OPTIONS_PARAMS[method].to_a.map do |key|
      [key.to_s.upcase, *opts[key]] unless opts[key].nil?
    end.compact
  end

  def build_docs(results, opts = {})
    return {} if results.nil? || results[0] == 0
    results.shift
    score_offset = opts[:withscores] ? 1 : 0
    content_offset = opts[:nocontent] ? 0 : 1
    rows_per_doc = 1 + content_offset + score_offset
    nr_of_docs = results.size / rows_per_doc
    (0..nr_of_docs-1).map do |n|
      doc = opts[:nocontent] ? {} : Hash[*results[rows_per_doc * n + content_offset + score_offset]]
      doc['score'] = results[rows_per_doc * n + score_offset] if opts[:withscores]
      doc['id'] = results[rows_per_doc * n]
      doc
    end
  end

  def valid_command?(command)
    %w(FT.CREATE FT.ADD FT.ADDHASH FT.SEARCH FT.DEL FT.DROP FT.GET FT.MGET
       FT.SUGADD FT.SUGGET FT.SUGDEL FT.SUGLEN FT.SYNADD FT.SYNUPDATE FT.SYNDUMP
       FT.INFO FT.AGGREGATE FT.EXPLAIN FT.TAGVALS).include?(command)
  end
end
