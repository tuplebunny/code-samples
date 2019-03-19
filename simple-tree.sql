-- Produces a relation like:
--
-- production=> select * from category_tree();
--  pid  | sid  | depth |                                                   lineage                                                    |                     name                     | leaf 
-- ------+------+-------+--------------------------------------------------------------------------------------------------------------+----------------------------------------------+------
--     1 | 3067 |     1 | Arduino                                                                                                      | Arduino                                      | f
--  3067 | 3089 |     2 | Arduino > Arduino Cases                                                                                      | Arduino Cases                                | t
--  3067 | 3088 |     2 | Arduino > Arduino Displays & Keypads                                                                         | Arduino Displays & Keypads                   | t
--  3067 | 3094 |     2 | Arduino > Arduino FTDI & Misc                                                                                | Arduino FTDI & Misc                          | t
--  3067 | 3123 |     2 | Arduino > Arduino Jumper Cables                                                                              | Arduino Jumper Cables                        | t
--  3067 | 3122 |     2 | Arduino > Arduino LEDs                                                                                       | Arduino LEDs                                 | t
--  3067 | 3086 |     2 | Arduino > Arduino Main Boards                                                                                | Arduino Main Boards                          | t
--  3067 | 3090 |     2 | Arduino > Arduino Protoboards & Shields                                                                      | Arduino Protoboards & Shields                | t
--  3067 | 3095 |     2 | Arduino > Arduino Related Connectors & Hardware                                                              | Arduino Related Connectors & Hardware        | t
--  3067 | 3092 |     2 | Arduino > Arduino Relays & Motors                                                                            | Arduino Relays & Motors                      | t
--  3067 | 3121 |     2 | Arduino > Arduino Robot Kits                                                                                 | Arduino Robot Kits                           | t
--  3067 | 3087 |     2 | Arduino > Arduino Sensors                                                                                    | Arduino Sensors                              | t
--  3067 | 3091 |     2 | Arduino > Arduino Starter Kits                                                                               | Arduino Starter Kits                         | t
--  3067 | 3093 |     2 | Arduino > Arduino Wireless Products                                                                          | Arduino Wireless Products                    | t
--     1 | 1466 |     1 | Automotive                                                                                                   | Automotive                                   | f
--  1466 | 1467 |     2 | Automotive > Automotive 12v LEDs & Strips                                                                    | Automotive 12v LEDs & Strips                 | f
--  1467 | 1468 |     3 | Automotive > Automotive 12v LEDs & Strips > Panel Mount 12v Lights                                           | Panel Mount 12v Lights                       | t
--  1467 | 1469 |     3 | Automotive > Automotive 12v LEDs & Strips > Strip lighting                                                   | Strip lighting                               | t
-- etc.

CREATE OR REPLACE FUNCTION public.category_tree()
 RETURNS SETOF category_tree_2
 LANGUAGE sql
AS $function$
  WITH RECURSIVE tree(pid, sid, depth, lineage, name) AS (
    select
       parent_id as pid
      ,id        as sid
      ,depth
      ,name::text
      ,name::text
    from
      spree_taxons
    where
      taxonomy_id = 1
    and
      depth = 1

    union

    select
       t.parent_id as pid
      ,t.id as sid
      ,t.depth
      ,tree.lineage || ' > ' || t.name
      ,t.name
    from
      spree_taxons as t
    inner join
      tree
    on
      tree.sid = t.parent_id
    where
      t.taxonomy_id = 1
  )

  select
     tree.pid
    ,tree.sid
    ,tree.depth
    ,tree.lineage
    ,tree.name
    ,case when r.id is not null then
      true
    else
      false
    end as leaf
  from
    tree
  left join
    (
      select
        t1.id
      from
        spree_taxons as t1
      where
        taxonomy_id = 1
      and
        not exists
          (
            select
              1
            from
              spree_taxons as t2
            where
              taxonomy_id = 1
            and
              t1.id = t2.parent_id
          )
    ) as r
  on
    tree.sid = r.id
  order by
    lineage;
$function$
