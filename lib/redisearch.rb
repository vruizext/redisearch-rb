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

  CREATE_OPTIONS_FLAGS = [:nooffsets, :nofreqs, :noscoreidx, :nofields]
  ADD_OPTIONS_FLAGS = [:nosave, :replace]
  SEARCH_OPTIONS_FLAGS = [:nocontent, :verbatim, :nostopwords,  :withscores, :withsortkeys]

  # Params options need an array with the values for the option
  #  { limit: ['0', '50'], sortby: ['year', 'desc'], return: ['2', 'title', 'year'] }
  ADD_OPTIONS_PARAMS = [:language]
  SEARCH_OPTIONS_PARAMS = [:filter, :return, :infields, :inkeys, :slop, :scorer, :sortby, :limit]

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
  #
  # Example:
  #
  #   redisearch = RediSearch.new('my_idx')
  #   redisearch.create_idx(['title', 'TEXT', 'WEIGHT', '2.0', 'director', 'TEXT', 'WEIGHT', '1.0'])
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
  def drop_index
    call(ft_drop)
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
    multi { docs.each { |doc_id, fields| @redis.call(ft_add(doc_id, fields, opts)) } }
  end

  # Search the index with the given `query`
  # @param [String] query text query, see syntax here http://redisearch.io/Query_Syntax/
  # @param [Hash] opts options for the query
  #
  #@return [Array] documents matching the query
  def search(query, opts = {})
    results_to_hash(call(ft_search(query, opts)), opts)
  end

  # Fetch a document by id
  def get_by_id(id)
    Hash[with_reconnect { @redis.hgetall(id) } || []]
      .tap { |doc| doc['id'] = id unless doc.empty? }
  end

  # Return information and statistics on the index.
  # @return [Hash] info returned by Redis key-value pairs
  #
  def info
    Hash[*call(ft_info)]
  end

  private

  def with_reconnect
    @redis.with_reconnect { yield }
  end

  def multi
    @redis.with_reconnect { @redis.multi { yield } }
  end

  def call(command)
    @redis.with_reconnect { @redis.call(command) }
  end

  def add(doc_id, fields)
    @redis.call(ft_add(doc_id, fields))
  end

  def ft_create(schema, opts)
    ['FT.CREATE', @idx_name , *create_options(opts), 'SCHEMA', *schema]
  end

  def ft_drop
    ['FT.DROP', @idx_name]
  end

  def ft_info
    ['FT.INFO', @idx_name]
  end

  def ft_add(doc_id, fields, opts = {}, weight =  nil)
    ['FT.ADD', @idx_name , doc_id, weight || DEFAULT_WEIGHT, *add_options(opts), 'FIELDS', *fields]
  end

  def ft_search(query, opts)
    ['FT.SEARCH', @idx_name, *query, *search_options(opts)].flatten
  end

  def create_options(opts = {})
    build_options(opts, CREATE_OPTIONS_FLAGS, [])
  end

  def add_options(opts = {})
    build_options(opts, ADD_OPTIONS_FLAGS, ADD_OPTIONS_PARAMS)
  end

  def search_options(opts = {})
    build_options(opts, SEARCH_OPTIONS_FLAGS, SEARCH_OPTIONS_PARAMS)
  end

  def build_options(opts, flags_keys, params_keys)
    flags_keys.map do |key|
      key.to_s.upcase if opts[key]
    end.compact +
    params_keys.map do |key|
      [key.to_s.upcase, *opts[key]] unless opts[key].nil?
    end.compact
  end

  def results_to_hash(results, opts = {})
    return {} if results.nil? || results[0] == 0
    results.shift
    offset = opts[:withscores] ? 1 : 0
    rows_per_doc = 2 + offset
    nr_of_docs = results.size / (2 + offset)
    (0..nr_of_docs-1).map do |n|
      doc = Hash[*results[rows_per_doc * n + 1 + offset]]
      doc['score'] = results[rows_per_doc * n + offset] if offset > 0
      doc['id'] = results[rows_per_doc * n]
      doc
    end
  end
end
