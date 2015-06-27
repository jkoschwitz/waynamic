# Example cypher-queries to visualize the current dataset

run this commands in the [neo4j-browser](http://localhost:7474/browser/)

## System

    // Server configuration
    :GET /db/manage/server/jmx/domain/org.neo4j/instance%3Dkernel%230%2Cname%3DConfiguration

    // Kernel information
    :GET /db/manage/server/jmx/domain/org.neo4j/instance%3Dkernel%230%2Cname%3DKernel

    // ID Allocation
    :GET /db/manage/server/jmx/domain/org.neo4j/instance%3Dkernel%230%2Cname%3DPrimitive%20count

    // Store file sizes
    :GET /db/manage/server/jmx/domain/org.neo4j/instance%3Dkernel%230%2Cname%3DStore%20file%20sizes

    // Extensions
    :GET /db/data/ext

## General

    // Get some data
    MATCH (n)
    RETURN n LIMIT 100

    // What nodes are there
    MATCH (a)
    RETURN
      DISTINCT head(labels(a)) AS label,
      count(a) AS count

    // What is related, and how
    MATCH (a)-[r]->(b)
    WHERE labels(a) <> [] AND labels(b) <> []
    RETURN
      DISTINCT head(labels(a)) AS this,
      type(r) as to,
      head(labels(b)) AS that,
      count(r) AS count
    LIMIT 10

    // REST API
    :GET /db/data

## graph visualization

    // 10 users likes/dislikes
    MATCH (user:user) WITH user LIMIT 10
    MATCH (user)-[r:like|dislike]->(media)
    RETURN user, media

    // 10 media items and its metadata (limited)
    MATCH (media:picture|music|movie|video) WHERE rand()<0.1 WITH media LIMIT 10
    MATCH (media)-[:metadata]->(metadata)
    RETURN media, metadata LIMIT 200

    // 3 users likes/dislikes in media and its metadata
    MATCH (user:user) WITH user LIMIT 3
    MATCH (user)-[:like|dislike]->(media)-[:metadata]->(metadata)
    RETURN user, media, metadata

    // 3 users interests in metadata
    MATCH (user:user) WITH user LIMIT 3
    MATCH (user)-[:interest]->(metadata)
    RETURN user, metadata

## lists - statistics

    // pictures - sorted by keyword-count
    MATCH (picture:picture) WITH picture LIMIT 1000
    MATCH (picture)-->(keyword:keyword)
    RETURN
      DISTINCT id(picture) AS picture_id,
      count(keyword) AS keywords
    ORDER BY keywords DESC

    // users - sorted by friend-count
    MATCH (user:user)
    MATCH (user)-[:knows]->(Friend)
    RETURN
      DISTINCT id(user) AS user_id,
      count(Friend) AS Friends
    ORDER BY Friends DESC

    // keywords having the same picture
    MATCH (picture:picture) WHERE rand()<0.1
    WITH picture LIMIT 10
    MATCH (picture)-->(keyword:keyword)
    RETURN DISTINCT
      keyword.name AS keyword,
      count(picture) AS pictures
    ORDER BY pictures DESC

## specific nodes (id required)

    // one node by id
    START node=node(203567)
    RETURN node

    // one user and picture
    START picture = node(220255), user = node(203468)
    MATCH (user)--(keyword:keyword)--(picture)
    RETURN picture, user, keyword

## lists - interest

    // interest list of one user
    START user=node(1)
    //MATCH (user:user) WHERE rand() < 0.1 WITH user LIMIT 1
    MATCH (user)-[i:interest]->(keyword:keyword)
    RETURN
      keyword.name AS keyword,
      i.like AS likes,
      i.dislike AS dislikes
    ORDER BY likes DESC
    LIMIT 100

    // interest profile (not normalized)
    START user=node(1)
    //MATCH (user:user) WHERE rand() < 0.1 WITH user LIMIT 1
    MATCH (user)-[i:interest]->(metadata)
    WHERE i.like > 0
    WITH
      metadata,
      i.like * i.like / (0.3*i.dislike + i.like) AS interests
    ORDER BY interests DESC
    RETURN
      labels(metadata)[0] AS metadata_type,
      metadata.name AS metadata_name,
      interests AS interestlevel
    LIMIT 100

    // content based filtering
    START user=node(1)
    //MATCH (user:user) WHERE rand() < 0.1 WITH user LIMIT 1
    MATCH (user)-[i:interest]->()<-[:metadata]-(media)
    WHERE
      not (user)-[:like]->(media)
      and i.like > 0
    WITH
      DISTINCT media,
      sum(i.like * i.like / (0.3*i.dislike + i.like)) AS interests
    ORDER BY interests DESC
    RETURN
      DISTINCT id(media) AS media_id,
      labels(media)[0] AS media_type,
      media.url AS media_url,
      'Passend zu Ihren Interessen' AS subtitle,
      interests AS interestlevel
    LIMIT 100



## manipulation

    // delete stuff made by mistake
    MATCH (x)
    WHERE labels(x) = []
    WITH x
    OPTIONAL MATCH (x)-[r]-(a)
    DELETE r,x

    // 1. delete all (dis)likes, interests
    MATCH (:user)-[r:like|dislike|interest]->()
    DELETE r

    // 2. delete all metadata
    MATCH ()-[metadata:metadata]->(metadata)
    DELETE metadata, metadata

    // 3. delete all pictures
    MATCH (picture:picture)
    DELETE picture
