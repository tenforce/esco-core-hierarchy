# mu-r-hierarchy

This project offers two api calls, one to fetch the descendants (up to a certain level) of a concept and one to fetch all ancestors of a concept.

Hierarchies are resources of their own that describe which paths to follow in the hierarchy. The format of the hierarchy in RDF is given below.

Note: the hierarchy service is graph agnostic, it only looks in the default graph of the sparql endpoint.

## Fetch descendants
The following GET call takes the hierarchy (structure) description identified by the uuid *'e92305e6-301f-45b3-980d-ec51d0a3a3f8'* and uses its description to find the descendants of the concept with uuid *'1DE4A2A8-C998-11E5-AF4F-DBC8669C75B0'* up to level 2.

```
http://service-path/hierarchies/e92305e6-301f-45b3-980d-ec51d0a3a3f8/1DE4A2A8-C998-11E5-AF4F-DBC8669C75B0/descendants?levels=2
```

## Fetch ancestors
The following GET call takes the hierarchy (structure) description identified by the uuid *'e92305e6-301f-45b3-980d-ec51d0a3a3f8'* and fetches all the ancestors of the concept with uuid *'e92305e6-301f-45b3-980d-ec51d0a3a3f8'*

```
http://service-path/hierarchies/e92305e6-301f-45b3-980d-ec51d0a3a3f8/1DE4A2A8-C998-11E5-AF4F-DBC8669C75B0/ancestors
```

## Hierarchy description
Hierarchies need to be configured in the application. They are present in the store as concepts with their own uuid. Hierarchies have the following structure:

```
@prefix hier: <http://mu.semte.ch/vocabularies/hierarchy/> .
@prefix mu: <http://mu.semte.ch/vocabularies/core/> .
@prefix skos: <http://www.w3.org/2004/02/skos/core#> .

hier: 1 hier:Hierarchy ;
    skos:prefLabel "ISCO" ;
    mu:uuid "52029960-ac8c-4a45-b70e-dc821a558c08" ;
    hier:path "( <http://www.w3.org/2004/02/skos/core#broader> | <http://data.europa.eu/esco/model#memberOfISCOGroup )" ;
    hier:restriction "?node <http://www.w3.org/2004/02/skos/core#inScheme> <http://data.europa.eu/esco/model#ESCO_Occupations> ." .
```

the properties of a hierarchy description are:
- **mu:uuid** the id of the label
- **skos:prefLabel** the label of the hierarchy
- **hier:path** the sparql property path expression that points from some concept to its direct broader form
- **hier:restriction** (optional) a restriction that a node in the result set has to adhere to. Nodes in the result set will match the ?node variable. These restrictions are parts of a sparql query.

## Deployment
The service can be deployed using this command

```
docker run -it -p 4567:80 --name sinatra --volume /path/to/app/:/usr/src/app/ext --link mumappingplatform_db_1:database -e LOG_LEVEL=debug tenforce/mu-r-hierarchy
```