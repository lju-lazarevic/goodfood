CREATE INDEX ON :Recipe(id);
CREATE INDEX ON :Ingredient(name);
CREATE INDEX ON :Keyword(name);
CREATE INDEX ON :DietType(name);
CREATE INDEX ON :Collection(name);
:params jsonFile => "https://raw.githubusercontent.com/mneedham/bbcgoodfood/master/stream_all.json";
//Load all details related to Author = Good Food only
CALL apoc.load.json($jsonFile) YIELD value
WITH value.page.article.id AS id,
       value.page.title AS title,
       value.page.article.description AS description,
       value.page.recipe.cooking_time AS cookingTime,
       value.page.recipe.prep_time AS preparationTime,
       value.page.recipe.skill_level AS skillLevel WHERE value.page.article.author = "Good Food"
MERGE (r:Recipe {id: id})
SET r.cookingTime = cookingTime,
    r.preparationTime = preparationTime,
    r.name = title,
    r.description = description,
    r.skillLevel = skillLevel;
CALL apoc.load.json($jsonFile) YIELD value
WITH value.page.article.id AS id,
       value.page.recipe.ingredients AS ingredients WHERE value.page.article.author = "Good Food"
MATCH (r:Recipe {id:id})
FOREACH (ingredient IN ingredients |
  MERGE (i:Ingredient {name: ingredient})
  MERGE (r)-[:CONTAINS_INGREDIENT]->(i)
);
CALL apoc.load.json($jsonFile) YIELD value
WITH value.page.article.id AS id,
       value.page.recipe.keywords AS keywords WHERE value.page.article.author = "Good Food"
MATCH (r:Recipe {id:id})
FOREACH (keyword IN keywords |
  MERGE (k:Keyword {name: keyword})
  MERGE (r)-[:KEYWORD]->(k)
);
CALL apoc.load.json($jsonFile) YIELD value
WITH value.page.article.id AS id,
       value.page.recipe.diet_types AS dietTypes WHERE value.page.article.author = "Good Food"
MATCH (r:Recipe {id:id})
FOREACH (dietType IN dietTypes |
  MERGE (d:DietType {name: dietType})
  MERGE (r)-[:DIET_TYPE]->(d)
);
CALL apoc.load.json($jsonFile) YIELD value
WITH value.page.article.id AS id,
       value.page.recipe.collections AS collections WHERE value.page.article.author = "Good Food"
MATCH (r:Recipe {id:id})
FOREACH (collection IN collections |
  MERGE (c:Collection {name: collection})
  MERGE (r)-[:COLLECTION]->(c)
);

//tokenise
MATCH (i:Ingredient)
WITH i, apoc.text.split(tolower(i.name), '[ ]|[-]') AS names
FOREACH (n IN names|
 MERGE (in:IngredientName {name:n})
 MERGE (in)-[:IS_COMPONENT_OF]->(i)
    );

//remove stop words
MATCH (i:IngredientName) 
WHERE size(i.name) <3  
DETACH DELETE i;

MATCH (i:IngredientName) 
WHERE i.name IN ['and', 'the', 'this', 'with'] 
DETACH DELETE i;

//process plurals
MATCH (i1:IngredientName), (i2:IngredientName)
WHERE id(i1)<>id(i2) 
AND (i1.name+'s' = i2.name OR 
     i1.name+'es'=i2.name OR 
     i1.name+'oes'=i2.name)
WITH i1, i2
MATCH (i1)-[:IS_COMPONENT_OF]->(in1:Ingredient), 
      (i2)-[:IS_COMPONENT_OF]->(in2:Ingredient)
MERGE (i1)-[:IS_COMPONENT_OF]->(in2)
DETACH DELETE i2;

//check for similarities
MATCH (n1:IngredientName),(n2:IngredientName)
WHERE id(n1) <> id(n2)
WITH n1, n2, 
     apoc.text.sorensenDiceSimilarity(n1.name,n2.name) as sorensenDS
WHERE sorensenDS > 0.6 AND left(n1.name,2)=left(n2.name,2)
with n1, n2
WHERE size(n1.name) <> size(n2.name) 
AND (left(n1.name, size(n1.name)-1)+'ies' = n2.name OR 
     n1.name+'d' = n2.name OR 
     left(n1.name, size(n1.name)-1)+'d' = n2.name)
WITH n1, n2
MATCH (n2)-[:IS_COMPONENT_OF]->(i)
MERGE (n1)-[:IS_COMPONENT_OF]->(i)
DETACH DELETE n2;

//and those that sound similarities
MATCH (n1:IngredientName),(n2:IngredientName)
WHERE id(n1) < id(n2)
WITH n1, n2, 
     apoc.text.sorensenDiceSimilarity(n1.name,n2.name) AS sorensenDS
WHERE sorensenDS > 0.92 
CALL apoc.text.doubleMetaphone([n1.name, n2.name]) YIELD value 
WITH n1, n2, collect(value) AS val
WHERE val[0] = val[1]
WITH n1, n2
MATCH (n2)-[:IS_COMPONENT_OF]->(i:Ingredient)
MERGE (n1)-[:IS_COMPONENT_OF]->(i)
DETACH DELETE n2;

//Reatach ingredients and delete duplicates
MATCH (i:Ingredient)
WITH i, [(i)<-[:IS_COMPONENT_OF]-(in:IngredientName) | in] AS components
MATCH (i)-[:IS_COMPONENT_OF*2]-(i2)
WHERE i.name < i2.name
WITH DISTINCT i, components, i2
WHERE size((i2)<-[:IS_COMPONENT_OF]-()) = size(components) 
AND all(in IN components WHERE (in)-[:IS_COMPONENT_OF]->(i2))
WITH i, i2
MATCH (i2)<-[:CONTAINS_INGREDIENT]-(r2:Recipe)
CREATE (i)<-[:CONTAINS_INGREDIENT]-(r2)
WITH i2
DETACH DELETE i2