module Hierarchy
  module SinatraHelpers

    DEFAULT_FILTER_DEPTH = 5
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

      first = result.first
      unless first
        return nil
      end

      first.each_binding do |name, value|
        structure[name.to_s] = value.to_s
      end

      restriction_on_fetching_children = ""

      fetch_children = structure['fetchChildren']
      if fetch_children == 'false'
        restriction_on_fetching_children = "
        ?node <http://www.w3.org/2004/02/skos/core#inScheme> <#{structure['codeList']}> .
      "
      end

      hierarchy['name'] = structure['name']
      hierarchy['id'] = structure['id']
      if structure['codedProperty'].nil? or structure['codedProperty'].eql? "http://www.w3.org/2004/02/skos/core#broader"
        hierarchy['path'] = "<http://www.w3.org/2004/02/skos/core#broader>"
      else
        hierarchy['path'] = "<#{structure['codedProperty']}> | <http://www.w3.org/2004/02/skos/core#broader>"
      end
      hierarchy['restriction'] = "filter (?scheme in (<#{structure['codeList']}>, <#{structure['structureFor']}>)) ?target <http://www.w3.org/2004/02/skos/core#inScheme> ?scheme."

      hierarchy['restriction'] += "
    {
      {
        ?node <http://www.w3.org/2004/02/skos/core#inScheme> <#{structure['codeList']}> .
      }
      UNION
      {
        ?node <http://www.w3.org/2004/02/skos/core#inScheme> <#{structure['structureFor']}>;
        a <http://data.europa.eu/esco/model#MemberConcept> .
        #{restriction_on_fetching_children}
      }
    }"

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
    <#{ESCO.codedProperty}> ?codedProperty ;
    <#{ESCO.structureFor}> ?structureFor ;
    <#{ESCO.codeList}> ?codeList ;
    <http://sem.tenforce.com/vocabularies/etms/fetchChildren> ?fetchChildren .
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

    unless extension.nil?
      other_path = ""
      if levels > 1
        one_hop_less = build_property_path(hierarchy, levels-1)
        other_path += "#{one_hop_less} / "
      end
      other_path += extension

      # no point in doing an union with the same predicate
      unless node_to_target.include? "#{other_path}"
        node_to_target = "{ { #{node_to_target} } UNION { #{var1} #{other_path} #{var2} . } }"
      end
    end

    node_to_target
  end

    ###
    # Fetches the descendants of a hierarchy object starting from the node with target as a uuid
    # The descendents are fetched up to a depth of levels
    #
    # @param hierarchy: a hierarchy object as returned by #fetch_hierarchy
    # @param target: a uuid of the target node
    # @param levels: the depth to where children should be fetched
    #
    # @returns children: the descendants of the target node in the format [{id, type}] where type is always 'concept'
    ###
    def fetch_children (hierarchy, target, levels, filter, params)
      path = build_property_path(hierarchy, levels)

      return_children = []
      max_level = 0
      max_level = filter[:depth].to_i if filter && filter[:depth]
      max_level = DEFAULT_FILTER_DEPTH unless max_level > 0

      (0..max_level).each do |level|
        filterString = ""
        unless filter.nil?
          filterString = insert_filter_params(filter, path, params, hierarchy, level)
        end

        query = "SELECT DISTINCT ?nodeId WHERE {
        ?target <#{MU_CORE.uuid}> \"#{target}\" .
        ?node #{path} ?target .
        ?node <#{MU_CORE.uuid}> ?nodeId .

        #{hierarchy['restriction']}


        #{filterString}
      }"

        children = query_result_to_list(query(query))
        new_children = []

        children.map do |child|
          new_children.push({id: child.to_s, type: 'concept'})
        end

        # merging the two arrays together and getting rid of the duplicates
        return_children = return_children | new_children

      end

      return_children
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
        #  the query doesn't work with multiple ?s
        # path += "? / #{hierarchy['path']}"
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
    def fetch_ancestors (hierarchy, target, filter, params)
      path = hierarchy['path']

      filterString = ""
      unless filter.nil?
        filterString = insert_filter_params(filter, path, params)
      end

      query = "SELECT DISTINCT ?nodeId WHERE {
      ?target <#{MU_CORE.uuid}> \"#{target}\" .
      ?target (#{path})* ?node .
      ?node <#{MU_CORE.uuid}> ?nodeId .

      #{hierarchy['restriction']}

      #{filterString}

    }"
      ancestors = query_result_to_list(query(query))

      result = []
      ancestors.map do |anc|
        unless anc.to_s == target
          result.push({id: anc.to_s, type: 'concept'})
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
      query = "SELECT ?filter ?uuid ?name WHERE {
      ?f a <#{MU_HIERARCHY.Filter}> ;
         <#{MU_CORE.uuid}> ?uuid ;
         <#{MU_HIERARCHY.filter}> ?filter ;
         <#{SKOS.prefLabel}> ?name .
    }"
      query(query).map do |row|
        FILTERS[row[:uuid].to_s] = {
            filter: row[:filter].to_s,
            name: row[:name].to_s
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
    def replace_descendants_to_node (filter, hierarchy, level)
      # max_depth = filter[:depth].to_i
      if level > 0
        connection = connect_variables_by_path("?descendant", "?node", hierarchy, level)
        path = "#{connection}  "
      else
        path = "?descendant a ?thing . FILTER(?descendant = ?node) "
    end

      filter[:filter].gsub("\#{DESCENDANT_TO_NODE}", path)
    end

    def insert_filter_params (filter, path, params, hierarchy = nil, level=nil)
      filterString = filter[:filter].gsub("\#{PATH}", path)
      if hierarchy
          filterString = replace_descendants_to_node(filter, hierarchy, level).gsub("\#{PATH}", path)
      end
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
end
