require_relative '/usr/src/app/sinatra_template/helpers.rb'
require 'sparql/client'
require_relative '/usr/src/app/spec_helper.rb'
require 'linkeddata'

describe "hierarchy api" do
  before(:all) do
    require 'rdf/trig'
    repository = RDF::Repository.load("./spec/ext/test-repository.trig")
    @graph = "http://mu.semte.ch/application"
    @sparql_client = SPARQL::Client.new(repository)
    app.settings.sparql_client = @sparql_client
    app.settings.graph = @graph
  end

  before(:each) do

  end

  context "/structures/:uuid/topConcepts" do
    it "should return success" do
      get '/structures/blaa/top-concepts'
      expect(last_response.status).to eq(200)
    end

    it "should return an array of uuids" do
      get '/structures/8d96e5dd-2056-4e97-b3a5-1428b0c2a848/top-concepts'
      expect(last_response.body).to have_json_path("data")

      uuids = ["da646914-3f9d-11e7-a919-92ebcb67fe33","da646bb2-3f9d-11e7-a919-92ebcb67fe33","da646fc2-3f9d-11e7-a919-92ebcb67fe33"]
      json = JSON.parse(last_response.body)
      expect(json["data"].sort).to be_json_eql(uuids.sort)
    end
  end

  context "/hierarchies/:id/target/:concept" do

  end
end
