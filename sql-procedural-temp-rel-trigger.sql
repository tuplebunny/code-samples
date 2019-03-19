-- SQL + Procedural monster.
--
-- There's a really cool technique used here, whereby I build a temporary
-- relation, and then activate a trigger on `price`, whose trigger-function
-- actually has access to the temp-relation created here.
--
-- I wrote this against PG 9.6. PG 10 has a specific mechanism for working with
-- sets in a trigger, but I actually think this is more flexible.
--
-- I also think it's cool to think of relations ("tables") as "just another
-- variable", no different than an integer, string, etc. In my experience,
-- this makes certain things way easier. I've seen questions on Stack Overflow
-- crying about how to work with multiple tuples in PL/PGSQL, since variables
-- defined in `DECLARE` are at-most a single tuple of a single type, e.g. RECORD.
--
-- Yes, my SQL is very "tall".

production=> \sf save_cluster

CREATE OR REPLACE FUNCTION public.save_cluster(_cluster jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
  declare
    cluster         record;
    product         record;
    attribute       record;
    attribute_count integer = 0;
    tt              record; -- temp-tuple
    vupns           TEXT[]; -- Available VUPN.
    vupn_index      INTEGER = 1; -- The index of available VUPN.
    product_title   TEXT;
  begin
    -- Gather available VUPN into an array.
    --
    select ARRAY_AGG(av.vupn) INTO vupns FROM available_vupn() AS av;

    -- 1. De-structure JSON into a tuple.
    --
    raise notice 'INIT:';
    raise notice '%', _cluster;

    select * into cluster from
      jsonb_to_record(_cluster) as cluster
        (
           options              jsonb -- array
          -- ,categories           jsonb -- array
          ,taxon_category_ids   JSONB -- array
          ,taxon_attribute_ids  JSONB -- array
          ,description          text
          ,errors               jsonb -- hash
          ,cluster_id           integer
          ,meta_description     text
          ,meta_keywords        text
          ,meta_title           text
          ,name                 text
          ,products             jsonb -- array
          ,shipping_category_id integer
          ,slug                 text
          ,tax_category_id      integer
          ,templates            jsonb -- array
          ,images               jsonb -- array
          ,red_dot              boolean
          ,include_in_feeds     BOOLEAN
          ,style                TEXT
        )
    ;

    raise notice '1';
    -- raise notice 'Categories: %', cluster.categories;
    raise notice 'Attributes: %', cluster.options;
    raise notice '2';

    -- Create/update the cluster.
    --
    -- Everything below this relies on its existence.
    --
    begin
      if cluster.cluster_id is null then
        raise notice 'INSERT CLUSTER';
        insert into spree_products
          (
             name
            ,created_at
            ,description
            ,meta_description
            ,meta_keywords
            ,meta_title
            ,shipping_category_id
            ,slug
            ,tax_category_id
            ,updated_at
            ,available_on
            ,red_dot
            ,include_in_feeds
            ,style
          )
        values
          (
             cluster.name
            ,now()
            ,cluster.description
            ,cluster.meta_description
            ,cluster.meta_keywords
            ,cluster.meta_title
            ,cluster.shipping_category_id
            ,cluster.slug
            ,cluster.tax_category_id
            ,now()
            ,now()
            ,cluster.red_dot
            ,cluster.include_in_feeds
            ,cluster.style
          )
        returning
          id into cluster.cluster_id
        ;
      else
        raise notice 'UPDATE CLUSTER';
        update spree_products set
          (
             description
            ,meta_description
            ,meta_keywords
            ,meta_title
            ,shipping_category_id
            ,slug
            ,tax_category_id
            ,name
            ,available_on
            ,red_dot
            ,include_in_feeds
            ,style
          ) = (
             cluster.description
            ,cluster.meta_description
            ,cluster.meta_keywords
            ,cluster.meta_title
            ,cluster.shipping_category_id
            ,cluster.slug
            ,cluster.tax_category_id
            ,cluster.name
            ,now()
            ,cluster.red_dot
            ,cluster.include_in_feeds
            ,cluster.style
          )
        where
          id = cluster.cluster_id
        ;
      end if;
    exception
      when unique_violation then
        raise notice 'ERROR MESSAGE: %', SQLERRM;
        cluster.errors = jsonb_set(cluster.errors, '{slug}', to_jsonb('Must be unique'::text));
      when not_null_violation then
        cluster.errors = JSONB_SET(cluster.errors, '{Name}', TO_JSONB('Must be set'::TEXT));
    end;

    if cluster.cluster_id is not null then
      insert into cluster_template
        (product_id, data)
      values
        (cluster.cluster_id, cluster.templates)
      on conflict (product_id) do update set
        data = cluster.templates
      ;

      begin
        insert into friendly_id_slugs
          (slug, sluggable_id, sluggable_type, created_at)
        values
          (cluster.slug, cluster.cluster_id, 'Spree::Product', now())
        ;
      exception
        when not_null_violation then
          cluster.errors = JSONB_SET(cluster.errors, '{Slug}', TO_JSONB('Must be set'::TEXT));
      end;
    end if;

    -- Establish error-status for cluster-tuple.
    --
      if cluster.description is null          or cluster.description = '' then
        cluster.errors = jsonb_set(cluster.errors, '{description}', to_jsonb('Must be set'::text));
      end if;

      if cluster.meta_description is null     or cluster.meta_description = '' then
        cluster.errors = jsonb_set(cluster.errors, '{meta_description}', to_jsonb('Must be set'::text));
      end if;

      if cluster.meta_keywords is null        or cluster.meta_keywords = '' then
        cluster.errors = jsonb_set(cluster.errors, '{meta_keywords}', to_jsonb('Must be set'::text));
      end if;

      if cluster.meta_title is null           or cluster.meta_title = '' then
        cluster.errors = jsonb_set(cluster.errors, '{meta_title}', to_jsonb('Must be set'::text));
      end if;

      if cluster.shipping_category_id is null or cluster.shipping_category_id < 1 then
        cluster.errors = jsonb_set(cluster.errors, '{shipping_category_id}', to_jsonb('Must be set'::text));
      end if;

      if cluster.tax_category_id is null      or cluster.tax_category_id < 1 then
        cluster.errors = jsonb_set(cluster.errors, '{tax_category_id}', to_jsonb('Must be set'::text));
      end if;
    --
    --

    raise notice 'ENTERING CATEGORIZING...';

    IF cluster.cluster_id IS NOT NULL THEN
      delete from spree_products_taxons where product_id = cluster.cluster_id;
    END IF;

    -- Categorize the cluster.
    --
      if cluster.cluster_id is not null then
        raise notice 'CATEGORIZING...';
        if jsonb_array_length(cluster.taxon_category_ids) = 0 then
          RAISE NOTICE 'NO TAX CATS';
          cluster.errors = jsonb_set(cluster.errors, '{taxon_category_ids}', to_jsonb('Must be categorized'::text));
        else
          RAISE NOTICE 'YES TAX CATS';
          -- delete from spree_products_taxons where product_id = cluster.cluster_id;

          perform
            cluster_categorize(cluster.cluster_id, category_id::integer)
          from
            jsonb_array_elements_text(cluster.taxon_category_ids) as category_id
          ;
        end if;
      ELSE
        raise notice 'CLUSTER ID NULL...';
      end if;
    --
    --

    raise notice 'CATEGORIZING OKAY!';

    raise notice '>>> %', cluster.taxon_attribute_ids;

    -- Assign taxon-attributes to the cluster.
    --
      if cluster.cluster_id is not null then
        if jsonb_array_length(cluster.taxon_attribute_ids) > 0 then
          -- 2018-12-14; LOL mybad; this naively deletes attribute-taxons, too. Oops.
          --


          perform
            cluster_categorize(cluster.cluster_id, taxon_attribute_id::integer)
          from
            jsonb_array_elements_text(cluster.taxon_attribute_ids) as taxon_attribute_id
          ;
        end if;
      end if;
    --
    --

    -- Assign attribute-pools (Spree lang: option-types) to the cluster.
    --
    raise notice '>>> 1';
      if cluster.cluster_id is not null then
      raise notice '>>> 2';
        if jsonb_array_length(cluster.options) > 0 then
        raise notice '>>> 3';
          delete from spree_product_option_types where product_id = cluster.cluster_id;

          insert into spree_product_option_types
            (product_id, option_type_id, position, created_at, updated_at)
          select
             cluster.cluster_id
            ,option_type_id::integer
            ,row_number() over () as position
            ,now()
            ,now()
          from
            jsonb_array_elements_text(cluster.options) as option_type_id
          ;
        end if;
      end if;
      raise notice '>>> 4';
    --
    --

    -- Iterate through products, creating/updating as needed.
    --
      if cluster.cluster_id is not null then
        for product in (
          select
             ((row_number() over ()) - 1)::text as rnum
            ,r1.*
            ,r2.images
          from
            (
              SELECT
                *
              FROM
                jsonb_to_recordset(cluster.products) as (
                   id                   integer
                  ,attributes           jsonb -- array-of-hashes
                  ,brand                text
                  ,cost_price           numeric(10, 2)
                  ,depth                numeric(8, 2)
                  ,free_shipping        boolean
                  ,gtin                 text
                  ,height               numeric(8, 2)
                  ,mfr_brand            text
                  ,mpn                  text
                  ,pricing              jsonb -- array-of-hashes
                  ,sku                  text
                  ,uri_slug             text
                  ,weight               numeric(8, 2)
                  ,width                numeric(8, 2)
                  ,errors               jsonb -- hash
                  ,is_master            boolean
                  ,slash_price          numeric(9, 2)
                  ,highlights           jsonb -- array-of-text
                  ,custom_pricing       boolean
                  ,custom_cost_price    boolean
                  ,custom_slash_price   boolean
                  ,custom_weight        boolean
                  ,custom_width         boolean
                  ,custom_height        boolean
                  ,custom_depth         boolean
                  ,custom_highlights    boolean
                  ,custom_sku           boolean
                  ,custom_brand         boolean
                  ,custom_mfr_brand     boolean
                  ,title                text
                  ,slug                 text
                  ,red_dot              boolean
                  ,custom_title         BOOLEAN
                  ,include_in_feeds     BOOLEAN
                  ,in_stock             INTEGER
                  ,in_stock_enforced    BOOLEAN
              )
            ) AS r1
          LEFT JOIN LATERAL
            (
              select
                 rx.viewable_id
                ,JSONB_AGG(rx.image ORDER BY rx.position) as images
              from
                (
                  select
                     viewable_id
                    ,a.position
                    ,jsonb_build_object('id', a.id, 'file_name', a.attachment_file_name, 'path', ('/spree/products/' || a.id || '/small/' || a.attachment_file_name)) as image
                  from
                    spree_assets as a
                  where
                    viewable_id = r1.id
                  and
                    a.viewable_type = 'Spree::Variant'
                ) as rx
              group by
                1
            ) AS r2
          ON
            r1.id = r2.viewable_id
        ) loop
          raise notice 'PRODUCT: %', product;

          if product.id is null then
            insert into spree_variants
              (
                 product_id
                ,sku
                ,weight
                ,height
                ,width
                ,depth
                ,cost_price
                ,gtin
                ,mpn
                ,brand
                ,mfr_brand
                ,is_master
                ,slash_price
                ,custom_pricing
                ,custom_cost_price
                ,custom_slash_price
                ,custom_weight
                ,custom_width
                ,custom_height
                ,custom_depth
                ,custom_highlights
                ,custom_sku
                ,custom_brand
                ,custom_mfr_brand
                ,title
                ,slug
                ,red_dot
                ,custom_title
                ,include_in_feeds
                ,in_stock
                ,in_stock_enforced
              )
            values
              (
                 cluster.cluster_id
                ,product.sku
                ,product.weight
                ,product.height
                ,product.width
                ,product.depth
                ,product.cost_price
                ,product.gtin
                ,product.mpn
                ,product.brand
                ,product.mfr_brand
                ,product.is_master
                ,product.slash_price
                ,product.custom_pricing
                ,product.custom_cost_price
                ,product.custom_slash_price
                ,product.custom_weight
                ,product.custom_width
                ,product.custom_height
                ,product.custom_depth
                ,product.custom_highlights
                ,product.custom_sku
                ,product.custom_brand
                ,product.custom_mfr_brand
                ,product.title
                ,parameterize(product.sku)
                ,product.red_dot
                ,product.custom_title
                ,product.include_in_feeds
                ,product.in_stock
                ,product.in_stock_enforced
              )
            returning
              id into product.id
            ;

            cluster.products = jsonb_set(cluster.products, array[product.rnum, 'id'], to_jsonb(product.id));
          else
            update spree_variants set
              (
                 product_id
                ,sku
                ,weight
                ,height
                ,width
                ,depth
                ,cost_price
                ,gtin
                ,mpn
                ,brand
                ,mfr_brand
                ,is_master
                ,slash_price
                ,custom_pricing
                ,custom_cost_price
                ,custom_slash_price
                ,custom_weight
                ,custom_width
                ,custom_height
                ,custom_depth
                ,custom_highlights
                ,custom_sku
                ,custom_brand
                ,custom_mfr_brand
                ,title
                ,slug
                ,red_dot
                ,custom_title
                ,include_in_feeds
                ,in_stock
                ,in_stock_enforced
              ) = (
                 cluster.cluster_id
                ,product.sku
                ,product.weight
                ,product.height
                ,product.width
                ,product.depth
                ,product.cost_price
                ,product.gtin
                ,product.mpn
                ,product.brand
                ,product.mfr_brand
                ,product.is_master
                ,product.slash_price
                ,product.custom_pricing
                ,product.custom_cost_price
                ,product.custom_slash_price
                ,product.custom_weight
                ,product.custom_width
                ,product.custom_height
                ,product.custom_depth
                ,product.custom_highlights
                ,product.custom_sku
                ,product.custom_brand
                ,product.custom_mfr_brand
                ,product.title
                ,parameterize(product.sku)
                ,product.red_dot
                ,product.custom_title
                ,product.include_in_feeds
                ,product.in_stock
                ,product.in_stock_enforced
              )
            where
              id = product.id
            ;
          end if;

          -- RAISE NOTICE '>>> HERE-1';

          IF product.images IS NOT NULL THEN
            cluster.products = JSONB_SET(cluster.products, ARRAY[product.rnum, 'images'], product.images);
          ELSE
            cluster.products = JSONB_SET(cluster.products, ARRAY[product.rnum, 'images'], JSONB_BUILD_ARRAY());
          END IF;

          IF product.id IS NOT NULL THEN

            -- RAISE NOTICE '>>> HERE-3';
            -- Auto-assigning SKU/VUPN when:
            --
            --   1. It would otherwise be null or ''.
            --   2. `custom_sku` is false.
            --
            -- SKU/VUPN is required.
            --
            IF (product.sku IS NULL OR product.sku = '') AND NOT product.custom_sku THEN
              cluster.products = JSONB_SET(cluster.products, ARRAY[product.rnum, 'sku'], TO_JSONB(vupns[vupn_index]::TEXT));
              UPDATE spree_variants SET sku = vupns[vupn_index] WHERE id = product.id;
              vupn_index = vupn_index + 1;
            ELSIF product.sku IS NULL OR product.sku = '' THEN
              cluster.errors   = JSONB_SET(cluster.errors, ARRAY['SKU/VUPN'], TO_JSONB('Required'::TEXT));
              cluster.products = jsonb_set(cluster.products, array[product.rnum, 'errors', 'SKU/VUPN'], to_jsonb('Required'::text));
            END IF;

            -- Weight is required, else Spree will fail to find shipping-methods.
            -- Also, it should be required in-general, as good house-keeping, etc.
            --
            IF product.weight IS NULL OR product.weight = 0 THEN
              cluster.errors   = JSONB_SET(cluster.errors, ARRAY['Weight'], TO_JSONB('Required'::TEXT));
              cluster.products = jsonb_set(cluster.products, array[product.rnum, 'errors', 'Weight'], to_jsonb('Required'::text));
            END IF;

            -- RAISE NOTICE '>>> HERE-7';



            -- Upsert spree_stock_items.
            --
            INSERT INTO spree_stock_items
              (stock_location_id, variant_id, created_at, updated_at)
            VALUES
              (1, product.id, now(), now())
            ON CONFLICT
              DO NOTHING
            ;

            -- RAISE NOTICE '>>> HERE-8';

            -- Assign attributes.
            --
            delete from spree_option_values_variants where variant_id = product.id;

            insert into spree_option_values_variants
              (variant_id, option_value_id)
            select
               product.id
              ,t.value_id as option_value_id
            from
              jsonb_to_recordset(product.attributes) as t(value_id integer)
            ;

            -- RAISE NOTICE '>>> HERE-9';

            -- Append error-message if cluster-attribute-pool-count > attribute-value-count
            -- on this particular product.
            --
            select count(*) into attribute_count from spree_option_values_variants where variant_id = product.id;

            if attribute_count <> jsonb_array_length(cluster.options) then
              cluster.products = jsonb_set(cluster.products, array[product.rnum, 'errors', 'attributes'], to_jsonb('Too few attribute-values'::text));
              cluster.errors   = jsonb_set(cluster.errors, array['attributes'], to_jsonb('1 or more products missing attribute-values'::text));
            end if;

            -- There are triggers that dynamically-set the product's title based
            -- on product's attribute-values.
            -- We must present the user the correct title.
            -- If user specified product has custom-title, we do nothing.
            --
            IF NOT product.custom_title THEN
              -- RAISE NOTICE '>>> HERE-6';

              SELECT
                p.name || ', ' || STRING_AGG(ov.presentation, ', ' ORDER BY ov.position) AS title
              INTO
                product_title
              FROM
                spree_variants AS v
              LEFT JOIN
                spree_products AS p
              ON
                v.product_id = p.id
              INNER JOIN
                spree_option_values_variants AS ovv
              ON
                v.id = ovv.variant_id
              LEFT JOIN
                spree_option_values AS ov
              ON
                ovv.option_value_id = ov.id
              WHERE
                v.id = product.id
              GROUP BY
                 v.id
                ,p.name
              ;

              -- WARNING: PG 9.6.5: When you JSONB_SET(JSONB, PATH, NULL), the value of your
              -- first argument becomes NULL entirely!
              --
              IF product_title IS NOT NULL THEN
                cluster.products = JSONB_SET(cluster.products, ARRAY[product.rnum, 'title'], TO_JSONB(product_title::TEXT));
              ELSE
                cluster.products = JSONB_SET(cluster.products, ARRAY[product.rnum, 'title'], TO_JSONB(cluster.name::TEXT));
              END IF;
            END IF;

            -- RAISE NOTICE '>>> HERE-5';

            -- Upsert highlights.
            --
            with hl as (
              select array_agg(hl) as hl from jsonb_array_elements_text(product.highlights) as hl
            )

            insert into product_highlight
              (variant_id, highlight)
            select
               product.id
              ,hl.hl as hl
            from
              hl
            on conflict (variant_id) do update set
              highlight = EXCLUDED.highlight
            ;

            -- RAISE NOTICE '>>> HERE-4';

            -- Handle pricing.
            --
            -- First we handle "new" pricing, i.e. the `price` relation.
            --
            -- There is a 2nd trigger on `price` relation that inserts data into
            -- the old pricing-relations, `spree_prices`, `spree_volume_prices`.
            --
            begin
              perform
                valid_price_insert(product.id, r.quantities, r.prices)
              from
                (
                  select
                     array_agg(int4range(t.qty_low, t.qty_high, '[]')) as quantities
                    ,array_agg(t.price) as prices
                  from
                    jsonb_to_recordset(product.pricing) as t(price numeric(9, 2), qty_low integer, qty_high integer)
                ) as r
              ;
            exception
              when RAISE_EXCEPTION then
                cluster.products = jsonb_set(cluster.products, array[product.rnum, 'errors', 'pricing'], to_jsonb(SQLERRM::text));
                cluster.errors   = jsonb_set(cluster.errors, array['pricing'], to_jsonb(SQLERRM::text));
            end;
          END IF;
        end loop;
      end if;
    --
    --

    -- RAISE NOTICE '>>> HERE-2';

    -- Ensure exactly 1 image is the "main" image for the Cluster.
    --
    PERFORM
      1
    FROM
      spree_assets
    WHERE
      cluster_id = cluster.cluster_id
    AND
      viewable_id IS NULL
    AND
      main = TRUE
    ;

    IF NOT FOUND THEN
      cluster.errors = jsonb_set(cluster.errors, array['images'], to_jsonb('Cluster must have default image.'::TEXT));
    END IF;

    -- If there are ANY errors, force cluster-red-dot.
    --
    PERFORM JSONB_OBJECT_KEYS(cluster.errors);

    IF FOUND THEN
      UPDATE
        spree_products
      SET
        red_dot = true
      WHERE
        id = cluster.cluster_id
      ;

      cluster.red_dot = true;
      cluster.errors = JSONB_SET(cluster.errors, ARRAY['WARNING'], TO_JSONB('Cluster Red-dotted because of errors.'::TEXT));
    END IF;

    raise notice '%', cluster.errors;

    raise notice '';
    raise notice 'PLPGSQL RETURNING:';
    raise notice '%', cluster;
    raise notice '';

    return row_to_json(cluster);
  end;
$function$
