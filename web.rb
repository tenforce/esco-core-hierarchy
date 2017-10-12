require_relative 'lib/hierarchy'
helpers Hierarchy::SinatraHelpers

###
# Vocabularies
##
MU_HIERARCHY = RDF::Vocabulary.new(MU.to_uri.to_s + "hierarchy/")
SKOS = RDF::Vocabulary.new("http://www.w3.org/2004/02/skos/core#")
ESCO = RDF::Vocabulary.new("http://data.europa.eu/esco/model#")

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
# returns the uuids of the topConcepts related to an esco structure
# @param uuid of the structure
# @return list of uuid
########
get '/structures/:uuid/top-concepts' do
  content_type 'application/vnd.api+json'
  query = %Q(SELECT ?uuid
FROM <#{settings.graph}>
WHERE {
  ?structure a <#{ESCO.Structure}>;
             <#{ESCO.codeList}> ?codeList;
             <#{MU_CORE.uuid}> "#{params['uuid']}".
  ?concept <#{SKOS.topConceptOf}> ?codeList;
           <#{MU_CORE.uuid}> ?uuid.
}
)
  children = query_result_to_list(query(query))

  result = children.map do |child|
    {id: child.to_s, type: 'concept'}
  end
  { data: result }.to_json
end

###
# Fetches the descendants of the target node 'concept' according to the hierarchy description 'id'
# @param concept the uuid of the concept to fetch the descendants from
# @param id the uuid of the hierarchy to use to fetch the descendants
# @param levels (optional) fetch descendants up to this level (but not the node itself), default 1
# @param filter (optional) the id of the filter to use if any
# @params other other params can be passed in, if they start with filter,
# they will be replaced into the filter query
#
# @return jsonapi list of children {data:[{id, type:'concept'}]}
###
get '/hierarchies/:structure_id/:concept_id/descendants' do
  content_type 'application/vnd.api+json'
  with_cache do
    concept = params[:concept_id]
    levels = params[:levels].to_i
    unless levels > 0
      levels = 1
    end

    id = params[:structure_id]

    filter_id = params[:filter]
    filter = nil

    unless filter_id.nil?
      filter = fetch_filter(filter_id)
    end

    hierarchy = ensure_hierarchy(id)
    {
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
get '/hierarchies/:structure_id/:concept_id/ancestors' do
  content_type 'application/vnd.api+json'
  with_cache do
    concept = params[:concept_id]
    id = params[:structure_id]
    filter_id = params[:filter]
    filter = nil

    unless filter_id.nil?
      filter = fetch_filter(filter_id)
    end

    hierarchy = ensure_hierarchy(id,true)

    {
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
