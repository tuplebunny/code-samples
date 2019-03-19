-- Produce RECURSIVELY NESTED JSON in pure SQL. Booyah!
--
-- production=> select jsonb_pretty(x) from public.mass_assign_load() as x;
--                                                                         jsonb_pretty                                                                         
-- -------------------------------------------------------------------------------------------------------------------------------------------------------------
--  {                                                                                                                                                          +
--      "1": {                                                                                                                                                 +
--          "name": "6' S-Video Cable",                                                                                                                        +
--          "available": "1",                                                                                                                                  +
--          "image_src": "/spree/products/74984/mini/S-255-200.jpg",                                                                                           +
--          "category_ids": [                                                                                                                                  +
--              1563,                                                                                                                                          +
--              1,                                                                                                                                             +
--              1576                                                                                                                                           +
--          ],                                                                                                                                                 +
--          "category_tree": [                                                                                                                                 +
--              [                                                                                                                                              +
--                  "Cables",                                                                                                                                  +
--                  [                                                                                                                                          +
--                      [                                                                                                                                      +
--                          "S-video"                                                                                                                          +
--                      ]                                                                                                                                      +
--                  ]                                                                                                                                          +
--              ]                                                                                                                                              +
--          ]                                                                                                                                                  +
--      },                                                                                                                                                     +
--      "2": {                                                                                                                                                 +
--          "name": "12' S-Video Cable",                                                                                                                       +
--          "available": "1",                                                                                                                                  +
--          "image_src": "/spree/products/79222/mini/S-255-202.jpg",                                                                                           +
--          "category_ids": [                                                                                                                                  +
--              2175,                                                                                                                                          +
--              2195,                                                                                                                                          +
--              1576,                                                                                                                                          +
--              2141,                                                                                                                                          +
--              1563,                                                                                                                                          +
--              1                                                                                                                                              +
--          ],                                                                                                                                                 +
--          "category_tree": [                                                                                                                                 +
--              [                                                                                                                                              +
--                  "Cables",                                                                                                                                  +
--                  [                                                                                                                                          +
--                      [                                                                                                                                      +
--                          "S-video"                                                                                                                          +
--                      ]                                                                                                                                      +
--                  ]                                                                                                                                          +
--              ],                                                                                                                                             +
--              [                                                                                                                                              +
--                  "Cable Type",                                                                                                                              +
--                  [                                                                                                                                          +
--                      [                                                                                                                                      +
--                          "S-Video"                                                                                                                          +
--                      ]                                                                                                                                      +
--                  ]                                                                                                                                          +
--              ]                                                                                                                                              +
--          ]                                                                                                                                                  +
--      },                                                                                                                                                     +
--      "3": {                                                                                                                                                 +
--          "name": "25' S-Video Cable",                                                                                                                       +
--          "available": "1",                                                                                                                                  +
--          "image_src": "/spree/products/74985/mini/S-255-206.jpg",                                                                                           +
--          "category_ids": [                                                                                                                                  +
--              2175,                                                                                                                                          +
--              2141,                                                                                                                                          +
--              1563,                                                                                                                                          +
--              1,                                                                                                                                             +
--              2195,                                                                                                                                          +
--              1576                                                                                                                                           +
--          ],                                                                                                                                                 +
--          "category_tree": [                                                                                                                                 +
--              [                                                                                                                                              +
--                  "Cables",                                                                                                                                  +
--                  [                                                                                                                                          +
--                      [                                                                                                                                      +
--                          "S-video"                                                                                                                          +
--                      ]                                                                                                                                      +
--                  ]                                                                                                                                          +
--              ],                                                                                                                                             +
--              [                                                                                                                                              +
--                  "Cable Type",                                                                                                                              +
--                  [                                                                                                                                          +
--                      [                                                                                                                                      +
--                          "S-Video"                                                                                                                          +
--                      ]                                                                                                                                      +
--                  ]                                                                                                                                          +
--              ]                                                                                                                                              +
--          ]                                                                                                                                                  +
--      },                                                                                                                                                     +
--      "4": {                                                                                                                                                 +
--          "name": "50' S-Video Cable",                                                                                                                       +
--          "available": "0",                                                                                                                                  +
--          "image_src": "/spree/products/74986/mini/S-255-208.jpg",                                                                                           +
--          "category_ids": [                                                                                                                                  +
--              2195,                                                                                                                                          +
--              2175,                                                                                                                                          +
--              2141,                                                                                                                                          +
--              1576,                                                                                                                                          +
--              1563,                                                                                                                                          +
--              1                                                                                                                                              +
--          ],                              
-- etc.

production=> \sf mass_assign_load 

CREATE OR REPLACE FUNCTION public.mass_assign_load()
 RETURNS jsonb
 LANGUAGE sql
 STABLE
AS $function$
  WITH RECURSIVE x (pid, cid, label) AS (
    SELECT
        t.parent_id
      , t.id
      , JSONB_BUILD_ARRAY(t.name)
    FROM
      spree_taxons AS t
    WHERE
      --t.taxonomy_id = 1
    --AND
      t.depth = 1

    UNION

    SELECT
        t.parent_id
      , t.id
      , x.label || TO_JSONB(t.name)
    FROM
      x
    INNER JOIN
      spree_taxons AS t
    ON
      x.cid = t.parent_id
  )

  SELECT
    JSONB_OBJECT_AGG(r.cluster_id, JSONB_BUILD_OBJECT(
        'name',          r.name
      , 'available',     r.available::TEXT
      , 'category_tree', r.category_tree
      , 'category_ids',  r.category_ids
      , 'image_src',     r.image_src::TEXT
    )) AS data
  FROM
    (
      SELECT
          r.cluster_id
        , r.name
        , r.category_tree
        , r.available
        , r.image_src
        , JSONB_AGG(pt.taxon_id) AS category_ids
      FROM
        (
          SELECT
              r.cluster_id
            , r.name
            , r.available
            , r.image_src
            , JSONB_AGG(r.root || JSONB_BUILD_ARRAY(r.lineage)) AS category_tree
          FROM
            (
              SELECT
                  p.id AS cluster_id
                , p.name
                , case when p.red_dot then
                    0
                  else
                    1
                  end as available
                , '/spree/products/' || a.id || '/mini/' || a.attachment_file_name AS image_src
                , r.root
                , JSONB_AGG(r.lineage) AS lineage
              FROM
                (
                  SELECT
                      r.cid
                    , JSONB_BUILD_ARRAY(r.label -> 0) AS root
                    , r.label - 0 AS lineage
                  FROM
                    (
                      SELECT
                          x.cid
                        , x.label
                      FROM
                        x
                      WHERE
                        NOT EXISTS
                          (
                            SELECT
                              1
                            FROM
                              spree_taxons AS t
                            WHERE
                              t.parent_id = x.cid
                          )
                    ) AS r
                ) AS r
              INNER JOIN
                spree_products_taxons AS pt
              ON
                r.cid = pt.taxon_id
              INNER JOIN
                spree_products AS p
              ON
                pt.product_id = p.id
              LEFT JOIN
                spree_assets AS a
              ON
                p.id = a.cluster_id
              AND
                a.main = TRUE
              GROUP BY
                1, 2, 3, 4, 5
            ) AS r
          GROUP BY
            1, 2, 3, 4
        ) AS r
      LEFT JOIN
        spree_products_taxons AS pt
      ON
        pt.product_id = r.cluster_id
      GROUP BY
        1,2,3,4,5

      UNION

      select
          p.id as cluster_id
        , name
        , JSONB_BUILD_ARRAY() AS category_tree
        , case when p.red_dot then
            0
          else
            1
          end as available
        , '/spree/products/' || a.id || '/mini/' || a.attachment_file_name AS image_src
        , JSONB_BUILD_ARRAY() as category_ids
      from
        spree_products as p
      LEFT JOIN
        spree_assets AS a
      ON
        p.id = a.cluster_id
      AND
        a.main = true
      where
        not exists (
          select
            1
          from
            spree_products_taxons as pt
          where
            p.id = pt.product_id
        )

    ) AS r
  ;
$function$
