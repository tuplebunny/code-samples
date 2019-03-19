# I think this code is interested because of function:
#
#   self.results_resistor
#
# See the comments there.

class Array
  def powerset(arr)
    a = [[]]
    for i in 0...arr.size do
      len = a.size; j = 0;
      while j < len
        a << (a[j] + [arr[i]])
        j+=1
      end
    end
    a
  end
end

module FacetedSearch

  # This function expects a front-end-user-submitted search-query that includes
  # the term "resistor".
  #
  # The parsing-process is "best effort".
  #
  # This function returns a hash, e.g.:
  #
  #   {'ohm' => 1, 'watt' => 10, 'tolerance' => 0.01}
  #   {'watt' => 10}
  #   {}
  #
  def self.parse_resistor(query)
    q          = query.downcase # Do not affect the value of the argument.
    attributes = {}             # Return-value.

    regexp_ohm = [
      %r{([\d.,]+\s*[k])},  # Numeric, kilo.
      %r{([\d.,]+\s*[m])},  # Numeric, mega.
      %r{([\d.,]+\s*[g])},  # Numeric, gig.
      %r{([\d.,]+)\s*[o]},  # Numeric, ohm (no unit specified).
    ]

    regexp_tolerance = [
      %r{([\d.,]+%)}
    ]

    regexp_watt = [
      %r{([\d.,\/]+)[\s-]*w}
    ]

    # Determine ohm-value, if found.
    #
    ##
      regexp_ohm.each do |r|
        match = q.match(r)

        if match
          ohm = match.captures.first

          if ohm.include?('k')
            ohm = ohm.to_f * 1_000
          elsif ohm.include?('m')
            ohm = ohm.to_f * 1_000_000
          elsif ohm.include?('g')
            ohm = ohm.to_f * 1_000_000_000
          else
            ohm = ohm.to_f
          end

          attributes['ohm'] = ohm

          break
        end
      end
    ##
    #

    # Determine watt-value, if found.
    #
    ##
      regexp_watt.each do |r|
        match = q.match(r)

        if match
          watt = match.captures.first

          if watt.include?('1/2')
            watt = 0.5
          elsif watt.include?('1/4')
            watt = 0.25
          else
            watt = watt.to_f
          end

          attributes['watt'] = watt

          break
        end
      end
    ##
    #

    # Determine tolerance-value, if found.
    #
    ##
      regexp_tolerance.each do |r|
        match = q.match(r)

        if match
          tolerance = match.captures.first

          if tolerance.include?('1%')
            tolerance = 0.01
          elsif tolerance.include?('5%')
            tolerance = 0.05
          else
            tolerance = tolerance.to_f
          end

          attributes['tolerance'] = tolerance

          break
        end
      end
    ##
    #

    attributes
  end

  # Why did I do this?
  #
  # First, consider the situation.
  #
  # Front-end-user submits a search-query to Vetco.net.
  #
  # I determine the query includes the term "resistor".
  #
  # Full-text-search, by itself, and the way it's presently (2017-11-02)
  # configured, performs poorly, e.g.:
  #
  # Searching for "2 ohm 1 watt resistor" yields these top-5 results:
  #
  #   2.4 Ohm 2 Watt Resistor
  #   5.1 Ohm 2 Watt Resistor
  #   6.2 Ohm 2 Watt Resistor
  #   8.2 Ohm 2 Watt Resistor
  #   9.1 Ohm 2 Watt Resistor
  #
  # Clearly, none of these are what I asked for, despite the fact that my query
  # is, I think, explicit.
  #
  # With respect to the following code...
  #
  # I'd rather be highly-explicity with respect to what is being done.
  #
  # Because we are operating-in-response-to a user-submitted-query, our results
  # are highly-variable; did the user specify ohms only? Ohms and watts? Watts
  # and tolerance? All 3?
  #
  # I could have dynamically constructed a query; I chose not to.
  #
  # I discarded the idea because I think it will be more difficult to mentally-
  # process conditional-logic-generating-SQL than it would be to simply type
  # more lines.
  #
  # Further, if you should need to tweak a query in a specific case, you can do
  # so without impacting any of the other queries; my solution is completely
  # orthogonal.
  #
  def self.results_resistor(attributes, sql_order_clause)
    powerset = { # Minus the empty-set.
      ["ohm"] => %{
        select
          product_id
        from
          pattr_ohm
        where
          value = #{attributes['ohm']}
      },

      ["watt"] => %{
        select
          product_id
        from
          pattr_watt
        where
          value = #{attributes['watt']}
      },

      ["ohm", "watt"].sort => %{
        select
          pao.product_id
        from
          pattr_ohm as pao
        inner join
          pattr_watt as paw
        on
          pao.product_id = paw.product_id
        where
          pao.value = #{attributes['ohm']}
        and
          paw.value = #{attributes['watt']}
      },

      ["tolerance"] => %{
        select
          product_id
        from
          pattr_tolerance
        where
          value = #{attributes['tolerance']}
      },

      ["ohm", "tolerance"].sort => %{
        select
          pao.product_id
        from
          pattr_ohm as pao
        inner join
          pattr_tolerance as pat
        on
          pao.product_id = pat.product_id
        where
          pao.value = #{attributes['ohm']}
        and
          pat.value = #{attributes['tolerance']}
      },

      ["watt", "tolerance"].sort => %{
        select
          paw.product_id
        from
          pattr_watt as paw
        inner join
          pattr_tolerance as pat
        on
          paw.product_id = pat.product_id
        where
          paw.value = #{attributes['watt']}
        and
          pat.value = #{attributes['tolerance']}
      },

      ["ohm", "watt", "tolerance"].sort => %{
        select
          pao.product_id
        from
          pattr_ohm as pao
        inner join
          pattr_watt as paw
        on
          pao.product_id = paw.product_id
        inner join
          pattr_tolerance as pat
        on
          paw.product_id = pat.product_id
        where
          pao.value = #{attributes['ohm']}
        and
          paw.value = #{attributes['watt']}
        and
          pat.value = #{attributes['tolerance']}
      }
    }

    sub_query = powerset[attributes.keys.sort]

    # The "core" of the query is predicated on our parsing of the user's query;
    # the outer-query is the same one we use when we employ FTS.
    #
    # See the interpolation of "sub_query".
    #
    sql = %{
      select
         r.product_id
        ,r.sku
        ,r.name
        ,r.title
        ,r.slug
        ,r.price
        ,'https://vetco.net/spree/products/' || a.id || '/small/' || a.attachment_file_name as image_src
        , 1 AS rank
      from
        (
          select
             p.id as product_id
            ,v.id as variant_id
            ,v.sku
            ,v.title
            ,p.name
            ,p.slug
            ,prices.amount as price
            ,min(a.position) as min_position
          from
            (
              #{sub_query}
            ) as r
          left join
            spree_products as p
          on
            r.product_id = p.id
          left join
            spree_variants as v
          on
            p.id = v.product_id
          and
            v.is_master = true
          left join
            spree_prices as prices
          on
            v.id = prices.variant_id
          left join
            spree_assets as a
          on
            a.viewable_type = 'Spree::Variant'
          and
            a.viewable_id = v.id
          group by
            1, 2, 3, 4, 5, 6, 7
        ) as r
      left join
        spree_assets as a
      on
        r.variant_id = a.viewable_id
      and
        a.viewable_type = 'Spree::Variant'
      and
        r.min_position = a.position
      where
        not exists
          (
            select
              1
            from
              red_dot as rd
            where
              rd.product_id = r.product_id
          )
      order by
         #{sql_order_clause}
      ;
    }

    V3::U.q(sql).to_a
  end

end
