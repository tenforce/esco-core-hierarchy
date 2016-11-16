###
# Vocabularies
##
MU_HIERARCHY = RDF::Vocabulary.new(MU.to_uri.to_s + "hierarchy/")
SKOS = RDF::Vocabulary.new("http://www.w3.org/2004/02/skos/core#")
ESCO = RDF::Vocabulary.new("http://data.europa.eu/esco/model#")
DEFAULT_FILTER_DEPTH = 5
# the set of filters available on the hierarchy calls
FILTERS = {}

# cached hierarchy, key is the full uri coming in
CACHE = {}
# how long a value can be cached
CACHE_DURATION = (ENV['HIER_CACHE_TIME'] || 1.0/24.0).to_f

###
# Calls
###

###
# Fetches the descendants of the target node 'concept' according to the hierarchy description 'id'
# @param concept the uuid of the concept to fetch the descendants from
# @param id the uuid of the hierarchy to use to fetch the descendants
# @param levels (optional) fetch descendants up to this level (but not the node itself), default 1
# @param filter (optional) the id of the filter to use if any
# @params other other params can be passed in, if they start with filter, 
# they will be replaced into the filter query
#
# @return jsonapi list of ancestors {data:[{id, type:'concept'}]}
###
get '/hierarchies/:id/target/:concept' do
  content_type 'application/vnd.api+json'
  with_cache do
    concept = params[:concept]
    levels = params[:levels].to_i
    unless levels > 0
      levels = 1
    end

    id = params[:id]

    filterId = params[:filter]
    filter = nil

    unless filterId.nil?
      filter = fetch_filter(filterId)
    end

    hierarchy = ensure_hierarchy(id)
    result = {
      data: fetch_children(hierarchy, concept, levels, filter, params)
    }.to_json
  end
end

###
# Fetches the ancestors of the target node 'concept' according to the hierarchy description 'id'
# @param concept the uuid of the concept to fetch the ancestors from
# @param id the uuid of the hierarchy to use to fetch the descendants
# @param filter (optional) the id of the filter to use if any
# @params other other params can be passed in, if they start with filter, 
# they will be replaced into the filter query
#
# @return jsonapi list of ancestors {data:[{id, type:'concept'}]}
###
get '/hierarchies/:id/ancestors/:concept' do
  content_type 'application/vnd.api+json'
  with_cache do
    concept = params[:concept]
    id = params[:id]
    filterId = params[:filter]
    filter = nil

    unless filterId.nil?
      filter = fetch_filter(filterId)
    end

    hierarchy = ensure_hierarchy(id,true)

    result = {
      data: fetch_ancestors(hierarchy, concept, filter, params)
    }.to_json
  end
end

###
# clears the cache
###
post '/hierarchies/cache/clear' do
  content_type 'application/vnd.api+json'

  CACHE = {}

  {
    status: "ok"
  }.to_json
end

###
# Returns the size of the cache in number of cached items
###
get '/hierarchies/cache/size' do
  content_type 'application/vnd.api+json'

  {
    size: CACHE.length
  }.to_json
end

###
# Helpers
###

helpers do
  ###
  # Parses the result of a hierarchy query to a description in an object without RDF literals
  # all variables returned by the sparql query become keys in the result
  ###
  def parse_hierarchy_result (result)
    hierarchy = {}

    first = result.first()
    if not first
      return nil
    end

    first.each_binding do |name, value|
      hierarchy[name.to_s] = value.to_s
    end
    hierarchy
  end

  ###
  # Parses the result of a structure query to a description in an object without RDF literals
  # transforms the structure to a hierarchy compatible object
  ###
  def parse_structure_result (result, forAncestors = false)
    hierarchy = {}
    structure = {}

    first = result.first()
    if not first
      return nil
    end

    first.each_binding do |name, value|
      structure[name.to_s] = value.to_s
    end

    hierarchy['name'] = structure['name']
    hierarchy['id'] = structure['id']
    hierarchy['path'] = "<http://www.w3.org/2004/02/skos/core#broader>"
    hierarchy['extension'] = "<#{structure['codedProperty']}>"
    hierarchy['restriction'] = "{ { ?node <http://www.w3.org/2004/02/skos/core#inScheme> <#{ESCO.codeList}> . ?target <#{structure['codedProperty']}> ?node } UNION { ?node <http://www.w3.org/2004/02/skos/core#inScheme> <#{ESCO.structureFor}> . ?target <http://www.w3.org/2004/02/skos/core#broader>* ?node. } }"

    if forAncestors
      hierarchy['restriction'] = "{ { ?target <http://www.w3.org/2004/02/skos/core#inScheme> <#{ESCO.codeList}> . ?node <#{structure['codedProperty']}> ?target } UNION { ?target <http://www.w3.org/2004/02/skos/core#inScheme> <#{ESCO.structureFor}> . ?node <http://www.w3.org/2004/02/skos/core#broader>* ?target. } }"

    end

    hierarchy
  end

  ###
  # Fetches the hierarchy description with the given id if it exists, if it does not, creates
  # a skos based hierarchy restriction
  #
  # forAncestors indicates whether the hierarchy should be fetched for a call asking for ancestors.
  # in that case the direction of the restriction might be different
  ###
  def ensure_hierarchy (id, forAncestors = false)
    hierarchy = fetch_hierarchy(id)
    if hierarchy.nil?
      hierarchy = hierarchy_from_structure(id, forAncestors)
    end
    if hierarchy.nil?
      hierarchy = { 
        "name" => "auto-generated skos hierarchy",
        "id" => "-1",
        "path" => "<http://www.w3.org/2004/02/skos/core#broader>",
        "restriction" => "?node <http://www.w3.org/2004/02/skos/core#inScheme> ?hierarchy .
                          ?hierarchy <#{MU_CORE.uuid}> \"#{id}\" ."
      }
    end
    hierarchy
  end

  ###
  # Performs a query to fetch a single hierarchy with id as a uuid
  ###
  def fetch_hierarchy (id)
    query = "SELECT * WHERE {
?s a <#{MU_HIERARCHY.Hierarchy}> ;
     <#{SKOS.prefLabel}> ?name ;
     <#{MU_CORE.uuid}> \"#{id}\" ;
     <#{MU_HIERARCHY.path}> ?path .
     OPTIONAL {
       ?s <#{MU_HIERARCHY.restriction}> ?restriction .
     }
}"
    parse_hierarchy_result(query(query))
  end

  ###
  # creates a hierarchy description from a given structure
  ###
  def hierarchy_from_structure (id, forAncestors = false)
    query = "SELECT * WHERE {
  ?s a <#{ESCO.Structure}> ;
    <#{SKOS.prefLabel}> ?name ;
    <#{MU_CORE.uuid}> \"#{id}\" ;
    <#{ESCO.codedProperty}> ?property ;
    <#{ESCO.codelist}> ?cs .
}"
    parse_structure_result(query(query), forAncestors)
  end

  ###
  # takes the given hierarchy description and connects the two variables to one another for /levels down the path
  ###
  def connect_variables_by_path (var1, var2, hierarchy, levels)
    path = build_property_path(hierarchy, levels)
    node_to_target = "#{var1} #{path} #{var2} ."
    extension = hierarchy['extension']

    if not extension.nil?
      other_path = ""
      if levels > 1
        one_hop_less = build_property_path(hierarchy, levels-1)
        other_path += "#{one_hop_less} / "
      end
      other_path += extension

      node_to_target = "{ { #{node_to_target} } UNION { #{var1} #{other_path} #{var2} . } }"
    end

    node_to_target
  end

  ###
  # Fetches the descendants of a hierarchy object starting from the node with target as a uuid
  # The descendents are fetched up to a depth of levels
  #
  # @param hierarchy: a hierarchy object as returned by #fetch_hierarchy
  # @param target: a uuid ot the target node
  # @param levels: the depth to where children should be fetched
  #
  # @returns children: the descendants of the target node in the format [{id, type}] where type is always 'concept'
  ###
  def fetch_children (hierarchy, target, levels, filter, params)

    node_to_target = connect_variables_by_path("?node", "?target", hierarchy, levels)
    filterString = ""
    unless filter.nil?
      filterString = insert_filter_params(filter,hierarchy,params)
    end

    query = "SELECT DISTINCT ?nodeId WHERE {
      #{node_to_target}
      ?node <#{MU_CORE.uuid}> ?nodeId .

      #{hierarchy['restriction']}

  	  ?target <#{MU_CORE.uuid}> \"#{target}\" .

      #{filterString}
    }"

    children = query_result_to_list(query(query))

    children.map do |child|
      { id: child.to_s, type: 'concept' }
    end
  end

  ###
  # Builds the property path for the given hierarchy and the given number of levels
  # @param hierarchy: a hierarchy object according to #fetch_hierarchy
  # @param levels: a number of levels to build a path.
  # @returns a property path according to the SPARQL spec that is a (levels) times repetition of
  # the hierarchy's path
  ###
  def build_property_path (hierarchy, levels)
    path = hierarchy['path']
    
    while levels > 1 do
      path += " / #{hierarchy['path']}"
      levels -= 1
    end
    path
  end

  ###
  # Fetches the ancestors of a hierarchy starting from the node with uuid target
  # @param hierarchy: a hierarchy object according to #fetch_hierarchy
  # @param target: the uuid of the target node to fetch the ancestors from
  # @param filter (optional): a filter object that can be applied on the results
  # @returns the list of ancestors in the format [{id,type}] where type is 'concept'
  ###
  def fetch_ancestors (hierarchy, target, filter,params)
    path = hierarchy['path']

    path_extension = ""
    if not hierarchy['extension'].nil?
      path_extension = " / #{hierarchy['extension']}?"
    end

    filterString = ""
    unless filter.nil?
      filterString = insert_filter_params(filter,hierarchy,params)
    end

    query = "SELECT DISTINCT ?nodeId WHERE {
      ?target <#{MU_CORE.uuid}> \"#{target}\" .
      ?target (#{path})* #{path_extension} ?node .
      ?node <#{MU_CORE.uuid}> ?nodeId .

      #{hierarchy['restriction']}

      #{filterString}

    }"
    ancestors = query_result_to_list(query(query))

    result = []
    ancestors.map do |anc|
      unless anc.to_s == target
        result.push( { id: anc.to_s, type: 'concept' })
      end
    end
    result
  end

  ###
  # Looks for the filter with the given uuid. If the filters are not loaded yet, loads the filters
  ###
  def fetch_filter (filter)
    if FILTERS.length == 0
      fetch_filters()
    end
    FILTERS[filter]
  end

  ###
  # reloads all filters from the store
  ###
  def fetch_filters
    query = "SELECT ?filter ?uuid ?name ?depth WHERE {
      ?f a <#{MU_HIERARCHY.Filter}> ;
         <#{MU_CORE.uuid}> ?uuid ;
         <#{MU_HIERARCHY.filter}> ?filter ;
         <#{SKOS.prefLabel}> ?name .
      OPTIONAL {
        ?f <#{MU_HIERARCHY.depth}> ?depth .
      }
    }"
    query(query).map do |row|
      FILTERS[row[:uuid].to_s] = {
        filter: row[:filter].to_s,
        name: row[:name].to_s,
        depth: row[:depth].to_s
      }
    end
  end

  ###
  # transforms a result set to a list of strings, adding all values to the result
  ###
  def query_result_to_list (result)
    list = []
    result.map do |row|
      row.each_value do |value|
        list.push value.to_s
      end
    end
    list
  end

  ###
  # if the filter's string has the #{DESCENDANT_TO_NODE} replacer in the query, it is
  # replaced by the path to the node up to the maximum depth for the filter
  ###
  def replace_descendants_to_node (filter, hierarchy)
    max_depth = filter[:depth].to_i
    max_depth = DEFAULT_FILTER_DEPTH unless max_depth > 0

    current_depth = 0
    pathNodes = []
    while current_depth < max_depth
      current_depth +=1
      connection = connect_variables_by_path("?descendant", "?node", hierarchy, current_depth)
      pathNodes.push "{ #{connection} }"
    end
    path = pathNodes.join(" UNION ")
    # have to do this, as a bind does not work in virtuoso...
    path = "#{path} UNION { ?descendant a ?thing . FILTER(?descendant = ?node) }"

    path = "{ #{path} }"

    filter[:filter].gsub("\#{DESCENDANT_TO_NODE}", path)
  end

  ###
  # inserts the filter parameters into the query by replacing the filter-NAME params into the query
  ###
  def insert_filter_params (filter, hierarchy, params)
    filterString = replace_descendants_to_node(filter, hierarchy)
    params.map do |key, value|
      if key.start_with? "filter-"
        variable = key.sub "filter-", ""
        filterString = filterString.gsub("\#{#{variable}}", value.to_s)
      end
    end
    filterString
  end

  ###
  # Builds a cache key out of the get function an its parameters
  ###
  def cache_key (request)
    request.fullpath
  end

  ###
  # Tries to fetch an element from the cache
  ###
  def try_cache_hit (path)
    cached = CACHE[path]
    unless cached.nil?
      cache_forever = path.index('filter-status').nil?
      if cache_forever or ((DateTime.now - cached[:date]) < CACHE_DURATION)
        log.info "CACHE HIT: #{path}"
        return cached[:value]
      end
    end
    return nil
  end

  ###
  # Cache the value for the given path
  ###
  def cache (path, value)
    CACHE[path] = {
      date: DateTime.now,
      value: value
    }
  end

  ###
  # run the given block with caching and name it fun
  ###
  def with_cache (&block)
    cacher = cache_key(request)
    hit = try_cache_hit(cacher)
    unless hit.nil?
      return hit
    end

    result = block.call()

    cache(cacher, result)
    result
  end
end
