require 'redis'

##
# Ruby client for RediSearch module
# http://redisearch.io/
#
class RediSearch
  # VERSION = '0.1.0'

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
  def create_index(schema)
    call(ft_create(schema))
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
  #
  # Example:
  #
  #   redisearch = RediSearch.new('my_idx')
  #   redisearch.add_doc('id_1', ['title', 'Lost in translation', 'director', 'Sofia Coppola'])
  #
  # See http://redisearch.io/Commands/#ftadd
  # @return [String] "OK" on success
  def add_doc(doc_id, fields)
    call(ft_add(doc_id, fields))
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
  def add_docs(docs)
    multi { docs.each { |doc_id, fields| @redis.call(ft_add(doc_id, fields)) } }
  end

  # Search the index with the given `query`
  # @param [String] query text query, see syntax here http://redisearch.io/Query_Syntax/
  # @param [Hash] opts options for the query
  #
  #@return [Array] documents matching the query
  def search(query, opts = {})
    results_to_hash(call(ft_search(query, opts)))
  end

  # Return information and statistics on the index.
  # @return [Hash] info returned by Redis key-value pairs
  #
  def info
    result = call(ft_info)
    return unless result.size > 0
    nr_of_rows = result.size / 2
    (0..nr_of_rows-1).map do |n|

    end
  end

  private

  def multi
    @redis.with_reconnect { @redis.multi { yield } }
  end

  def call(command)
    @redis.with_reconnect { @redis.call(command) }
  end

  def add(doc_id, fields)
    @redis.call(ft_add(doc_id, fields))
  end

  def ft_create(schema)
    ['FT.CREATE', @idx_name , 'SCHEMA', *schema]
  end

  def ft_drop
    ['FT.DROP', @idx_name]
  end

  def ft_info
    ['FT.INFO', @idx_name]
  end

  def ft_add(doc_id, fields)
    ['FT.ADD', @idx_name , doc_id, '1.0', 'REPLACE', 'FIELDS', *fields]
  end

  def ft_search(query, opts)
    command = ['FT.SEARCH', @idx_name, *query]
    command << 'NOSTOPWORDS' if opts[:nostopwords]
    command << 'VERBATIM' if opts[:verbatim]
    if opts[:offset] || opts[:limit]
      limit = opts[:limit].to_i > 0 ? opts[:limit].to_i : -1
      command << "LIMIT #{opts[:offset].to_i} #{limit}"
    end
    command << 'WITHSCORES' if opts[:withscores]
    command << "SCORER #{opts[:scorer]}" unless opts[:scorer].to_s.empty?
    command << "SLOP #{opts[:slop]}" if opts[:slop].to_i > 0
    command
  end

  def results_to_hash(results)
    return {} if results.nil? || results[0] == 0
    results.shift
    offset = results.size % 3 == 0 ? 1 : 0
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
