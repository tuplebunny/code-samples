# ~1300 LOC.
#
# Around 2010 I read a book called "Object Thinking", by David West.
#
# And it screwed me up.
#
# I started asking existential questions about my objects.
#
# Should a Mail class mail itself? Or interact with a Postman? Mailbox?
#
# None of that crap matters. Do the work. Abstract later, if there's an actual
# need.
#
# See Brian Will's "Object Oriented Programming is Garbage" for a more detailed,
# eloquent expose that fairly accurately reflects my mindset (2019).
#
# https://www.youtube.com/watch?v=QM1iUe6IofM

#  ::::::::  :::::::::: :::        ::::::::::  ::::::::  :::::::::::
# :+:    :+: :+:        :+:        :+:        :+:    :+:     :+:
# +:+        +:+        +:+        +:+        +:+            +:+
# +#++:++#++ +#++:++#   +#+        +#++:++#   +#+            +#+
#        +#+ +#+        +#+        +#+        +#+            +#+
# #+#    #+# #+#        #+#        #+#        #+#    #+#     #+#
#  ########  ########## ########## ##########  ########      ###
#  ::::::::  :::    ::: ::::::::::: :::::::::  :::::::::  ::::::::::: ::::    :::  ::::::::
# :+:    :+: :+:    :+:     :+:     :+:    :+: :+:    :+:     :+:     :+:+:   :+: :+:    :+:
# +:+        +:+    +:+     +:+     +:+    +:+ +:+    +:+     +:+     :+:+:+  +:+ +:+
# +#++:++#++ +#++:++#++     +#+     +#++:++#+  +#++:++#+      +#+     +#+ +:+ +#+ :#:
#        +#+ +#+    +#+     +#+     +#+        +#+            +#+     +#+  +#+#+# +#+   +#+#
# #+#    #+# #+#    #+#     #+#     #+#        #+#            #+#     #+#   #+#+# #+#    #+#
#  ########  ###    ### ########### ###        ###        ########### ###    ####  ########
# ::::    ::::  :::::::::: ::::::::::: :::    :::  ::::::::  :::::::::
# +:+:+: :+:+:+ :+:            :+:     :+:    :+: :+:    :+: :+:    :+:
# +:+ +:+:+ +:+ +:+            +:+     +:+    +:+ +:+    +:+ +:+    +:+
# +#+  +:+  +#+ +#++:++#       +#+     +#++:++#++ +#+    +:+ +#+    +:+
# +#+       +#+ +#+            +#+     +#+    +#+ +#+    +#+ +#+    +#+
# #+#       #+# #+#            #+#     #+#    #+# #+#    #+# #+#    #+#
# ###       ### ##########     ###     ###    ###  ########  #########


# This function invoked when agent clicks "Select Shipping Option and
# Continue" from the cart-page.
#
# This is the singular path-way to the actual check-out-page.
#
# It is a required-step!
#
# If any of the 5-tuples that should have been created from
# controller-action v3_cart are missing, we have a problem, and we need
# to immediately halt the process.
#
# ?!?!?!?!?! DO WE ACTUALLY WANT TO DO THE BELOW, OR SHOULD WE CONDITIONALLY
# REDIRECT IMMEDIATELY TO CHECKOUT IF WE CAN???
#
# Successful-exection of this function ALWAYS redirects agent to the
# registration-controller.
#
def v3_select_shipping_method
  cart = JSON.parse(session[:cart] || '{}')

  if cart.empty?
    flash[:notice] = %{Your cart is empty. Find something cool to add to it!}
    redirect_to('/')
    return
  end

  # This should never happen that an agent reaches this page without
  # reference to an order-tuple.
  #
  # When it happens, re-direct agent back to the cart-page.
  #
  if session[:v3_order_id].blank?
    flash[:notice] = %{Please select a shipping-option.}
    redirect_to('/v3/cart')
    return
  end

  # We re-build the cart because later in this function we will create
  # line-item-tuples and attach them to our order-tuple.
  #
  @cart = V3::U.qq(%{SELECT * FROM shopping_cart_content($1);}, [cart.to_json]).to_a

  tuple = V3::U.qq('SELECT * FROM retrieve_new_order($1);', [session[:v3_order_id]]).to_a[0]

  if tuple.nil?
    # WARNING:
    #
    # session[:v3_order_id] exists, but we cannot find all 5 tuples we
    # created earlier.
    #
    # What do we do in this scenario?
    #
    # For now let's reset-session and redirect to root.
    #
    reset_session
    flash[:notice] = %{Error: Session reset.}
    return
  end

  # This value comes to us from v3_cart, and although there should always
  # be a shipping-option selected by default, let's be extra-careful
  # and direct the agent back to their cart if it's missing.
  #
  selected_shipping_method_id = params[:selected_shipping_method].to_i

  if selected_shipping_method_id <= 0
    flash[:notice] = %{Please select a shipping-option to continue.}
    redirect_to('/v3/cart')
    return
  end

  # QUESTION:
  #
  # IF WE KNOW THE AGENT IS ALREADY LOGGED-IN, DOES IT MAKE SENSE TO DIRECT
  # THEM TO THE REGISTRATION-PAGE?????
  #
  # If agent is a guest, their e-mail has been set during the registration-
  # form-submission, so we don't need to bind their e-mail to the order.
  #
  # Logged-in agents, however, have their e-mail and user-ID associated with
  # the order here.
  #
  # This block is written for the singular scenario wherein an agent has
  # logged-into-their-account PRIOR to clicking "Select Shipping Option
  # and Continue".
  #
  # This binds their registered-account to the order-tuple created in v3_cart.
  #
  if spree_current_user
    V3::U.qq(%{
      UPDATE spree_orders SET
         user_id = $1
        ,email = $2
      WHERE
        id = $3
      ;
    }, [spree_current_user.id, spree_current_user.email, session[:v3_order_id]])
  end

  # Reset order's line-items, adjustments, inventory-units.
  #
  # We do this because we want a clean-slate when calculating the $-values
  # of the order; far easier to calculate-and-save, rather than re-calculate-
  # and-update.
  #
  V3::U.qq(%{DELETE FROM spree_line_items WHERE order_id = $1;}, [session[:v3_order_id]])
  V3::U.qq(%{DELETE FROM spree_inventory_units WHERE order_id = $1;}, [session[:v3_order_id]])
  V3::U.qq(%{DELETE FROM spree_adjustments WHERE order_id = $1;}, [session[:v3_order_id]])

  V3::U.qq(%{
    UPDATE spree_shipping_rates SET
      selected = FALSE
    WHERE
      shipment_id = $1
    ;
  }, [session[:v3_shipment_id]])

  V3::U.qq(%{
    UPDATE spree_shipping_rates SET
      selected = TRUE
    WHERE
      shipment_id = $1
    AND
      id = $2
    ;
  }, [session[:v3_shipment_id], selected_shipping_method_id])

  # Determine whether the order is taxable based on the data in the
  # shipping-address-tuple.
  #
  # I have exactly 1 record of an error occuring here, specifically:
  #
  #   tuple['country_iso']
  #
  # Because there was no address-tuple for the ID provided.
  #
  # I have-not been able to re-produce this error.
  #
  # However, recent editions to v3_cart, etc., should make that
  # particular error an impossibility.
  #
  tuple = V3::U.qq(%{
    SELECT
       c.iso  AS country_iso
      ,s.abbr AS state_abbr
    FROM
      spree_addresses AS a
    LEFT JOIN
      spree_countries AS c
    ON
      a.country_id = c.id
    LEFT JOIN
      spree_states AS s
    ON
      a.state_id = s.id
    WHERE
      a.id = $1
    ;
  }, [session[:v3_shipping_address_id]]).to_a[0]

  country_iso = tuple['country_iso']
  state_abbr  = tuple['state_abbr']

  if country_iso == 'US' && state_abbr == 'WA'
    tax_rate = V3::U.q(%{
      SELECT amount FROM spree_tax_rates WHERE name = 'Wa State Sales Tax';
    }).to_a[0]['amount']

    tax_rate = BigDecimal.new(tax_rate.to_s)
  else
    tax_rate = 0
  end

  selected_shipping_rate = V3::U.qq(%{
    SELECT
       sr.id
      ,sr.cost
      ,sm.name
      ,sr.selected
      ,sm.flat_rate > 0 AS flat_rate -- Are taxables applicable to this method?
      ,sm.carrier
    FROM
      spree_shipping_rates AS sr
    LEFT JOIN
      spree_shipping_methods AS sm
    ON
      sr.shipping_method_id = sm.id
    WHERE
      sr.shipment_id = $1
    AND
      selected = TRUE
    ORDER BY
      sr.cost ASC
    ;
  }, [session[:v3_shipment_id]]).to_a[0]

  # 2018-07-16; Github-issue-375.
  #
  # Remember the agent's selection. We do this because agent's on the back-end
  # may modify the order, which forces a re-calculation for shipping-rates, and
  # when possible, we want to preserve the original selection.
  #
  V3::U.qq(%{
    INSERT INTO previous_shipping_method
      (order_id, shipping_method)
    VALUES
      ($1, $2)
    ;
  }, [session[:v3_order_id], selected_shipping_rate['name']])

  shipping_cost = BigDecimal.new(selected_shipping_rate['cost'])

  # Update tuple in `spree_shipments` to reflect cost, tax, etc.
  #
  V3::U.qq(%{
    UPDATE spree_shipments SET
       cost = $1
      ,adjustment_total = 0
      ,additional_tax_total = $2
      ,promo_total = 0
      ,included_tax_total = $3
      ,pre_tax_amount = $1
    WHERE
      id = $4
    ;
  }, [shipping_cost, shipping_cost * tax_rate, (shipping_cost * tax_rate) + shipping_cost, session[:v3_shipment_id]])

  # Compute line-items.
  #
  line_items = []

  # 2018-11-01; Github-issue-449.
  #
  # Regarding line-items; I think attributes `adjustment_total` and `additional_tax_total`
  # are ridiculous; they are "cached values", and push us in the direction of update-anomalies.
  #
  # I am going to leave this code as-is right now; and...???

  @cart.each do |p|
    if tax_rate > 0
      tax = (BigDecimal.new(p['quantity_price']) * tax_rate).to_f

      line_items << V3::U.qq(%{
        INSERT INTO spree_line_items
          (order_id, variant_id, quantity, price, pre_tax_amount, adjustment_total, additional_tax_total, tax_category_id, created_at, updated_at)
        VALUES
          ($1, $2, $3, $4, $5, 0, 0, 1, NOW() AT TIME ZONE 'utc', NOW() AT TIME ZONE 'utc')
        RETURNING
          id, variant_id, quantity
        ;
      }, [session[:v3_order_id], p['product_id'], p['quantity'], p['unit_price'], p['quantity_price']]).to_a[0]
    else
      line_items << V3::U.qq(%{
        INSERT INTO spree_line_items
          (order_id, variant_id, quantity, price, pre_tax_amount, adjustment_total, additional_tax_total, tax_category_id, created_at, updated_at)
        VALUES
          ($1, $2, $3, $4, $5, 0, 0, 1, NOW() AT TIME ZONE 'utc', NOW() AT TIME ZONE 'utc')
        RETURNING
          id, variant_id, quantity
        ;
      }, [session[:v3_order_id], p['product_id'], p['quantity'], p['unit_price'], p['quantity_price']]).to_a[0]
    end
  end

  line_items.each do |li|
    V3::U.qq(%{
      INSERT INTO spree_inventory_units
        (state, variant_id, order_id, shipment_id, created_at, updated_at, pending, line_item_id, quantity)
      VALUES
        ('on_hand', $1, $2, $3, NOW() AT TIME ZONE 'utc', NOW() AT TIME ZONE 'utc', DEFAULT, $4, $5)
      ;
    }, [li['variant_id'], session[:v3_order_id], session[:v3_shipment_id], li['id'], li['quantity']])
  end

  # 2018-09-18; Github-issue-419.
  #
  # Re-instating the low-order-fee; this time, admins can toggle
  # fee-application from the back-end.
  #
  lof = V3::U.q(%{
    SELECT minimum::TEXT, fee::TEXT FROM low_order_fee WHERE active = TRUE ORDER BY minimum ASC LIMIT 1;
  }).values.flatten.compact

  if lof.any?
    # Remember PG-Numeric gets cast to Ruby-float. BigDecimal is more
    # accurate than float.
    #
    min = BigDecimal.new(lof[0])
    fee = BigDecimal.new(lof[1])

    sub_total = V3::U.qq(%{
      SELECT
        SUM(li.price * li.quantity)
      FROM
        spree_line_items AS li
      WHERE
        li.order_id = $1
      ;
    }, [session[:v3_order_id]]).values.flatten.compact[0]

    sub_total = BigDecimal.new(sub_total)

    if min > sub_total
      lof_applicable = true
      lof_label      = %{Low Order Fee (less than #{number_to_currency(min)})}

      V3::U.qq(%{
        INSERT INTO spree_adjustments
          (source_id, source_type, adjustable_id, adjustable_type, amount, label, created_at, updated_at, order_id)
        VALUES
          (-2, 'Low Order Fee', $1, 'Spree::Order', $2, $4, NOW() AT TIME ZONE 'utc', NOW() AT TIME ZONE 'utc', $3)
        ;
      }, [session[:v3_order_id], fee, session[:v3_order_id], lof_label])
    else
      lof_applicable = false
    end
  end

  # Attempt to create the singular tuple that represents the discounted-
  # value for the set of line-items.
  #
  discount = false

  if session[:v3_coupon_code]
    discount = V3::U.qq(%{
      SELECT apply_coupon_discount($1, $2);
    }, [session[:v3_order_id], session[:v3_coupon_code]]).values.flatten.compact[0]
  end

  # Compute adjustments.
  #
  # Generally, adjustments are only required when the order is taxable.
  #
  # When the order is taxable, generally, you need:
  #
  #   1. 1 adjustment per line-item.
  #   2. 1 adjustment for the selected shipping-rate.
  #
  # 2018-11-01; Github-issue-449.
  #
  # In implementing coupons (discount-codes), we make use of the
  # `adjustments`-relation.
  #
  if tax_rate > 0
    if discount
      V3::U.qq(%{
        SELECT apply_taxes_to_discounted_line_items($1, $2, $3);
      }, [session[:v3_order_id], tax_rate, session[:v3_coupon_code]])
    else
      # Passing tax-rate into this function is stupid, because the database
      # can, with `order_id`, already figure out what the tax-rate should be.
      #
      # However, given the way I wrote this controller-action, I basically
      # said "fuck you" to the database. And so we stack shit on shit...
      #
      # Regardless, this change is an improvement, arithematically, because
      # it will avoid rounding-errors, at least with respect to
      # line-item-tax-total.
      #
      V3::U.qq(%{
        SELECT apply_taxes_to_line_items($1, $2);
      }, [session[:v3_order_id], tax_rate])
    end



    # 1 tax-adjustment per line-item.
    #
    # This feels wrong; rounding-errors could creep in.
    #
    # V3::U.qq(%{
    #   INSERT INTO spree_adjustments
    #     (source_id, source_type, adjustable_id, adjustable_type, amount, label, created_at, updated_at, order_id)

    #   SELECT
    #      1
    #     ,'Spree::TaxRate'
    #     ,id
    #     ,'Spree::LineItem'
    #     ,5
    #     ,'Line Item Tax'
    #     ,NOW() AT TIME ZONE 'utc'
    #     ,NOW() AT TIME ZONE 'utc'
    #     ,order_id
    #   FROM
    #     spree_line_items
    #   WHERE
    #     order_id = $1
    #   ;
    # }, [session[:v3_order_id]])

    # This is TAX on the low-order-fee; not the LOF.
    #
    if lof.any? && lof_applicable
      V3::U.qq(%{
        INSERT INTO spree_adjustments
          (source_id, source_type, adjustable_id, adjustable_type, amount, label, created_at, updated_at, order_id)
        VALUES
          (1, 'Spree::TaxRate', $1, 'Spree::Order', $2, 'Low Order Fee Tax', NOW() AT TIME ZONE 'utc', NOW() AT TIME ZONE 'utc', $1)
        ;
      }, [session[:v3_order_id], fee * tax_rate])
    end

    if ! selected_shipping_rate['flat_rate']
      V3::U.qq(%{
        INSERT INTO spree_adjustments
          (source_id, source_type, adjustable_id, adjustable_type, amount, label, created_at, updated_at, order_id)

        SELECT
           1
          ,'Spree::TaxRate'
          ,id
          ,'Spree::Shipment'
          ,additional_tax_total
          ,'Shipment Tax'
          ,NOW() AT TIME ZONE 'utc'
          ,NOW() AT TIME ZONE 'utc'
          ,order_id
        FROM
          spree_shipments
        WHERE
          id = $1
        ;
      }, [session[:v3_shipment_id]])
    end
  end

  # Compute the order-tuple $-values.
  #
  V3::U.qq(%{
    UPDATE spree_orders SET
       item_total           = r.item_total
      ,total                = r.total
      ,adjustment_total     = r.adjustment_total
      ,shipment_total       = r.shipment_total
      ,additional_tax_total = r.additional_tax_total
      ,item_count           = r.item_count
    FROM
      (
        SELECT
           r1.item_total
          ,r1.item_total + r2.shipment_total + r3.adjustment_total AS total
          ,r3.adjustment_total
          ,r2.shipment_total
          ,r3.adjustment_total AS additional_tax_total
          ,r4.item_count
        FROM
          (
            SELECT
              SUM(li.price * li.quantity) AS item_total
            FROM
              spree_line_items AS li
            WHERE
              li.order_id = $1
          ) AS r1
        CROSS JOIN
          (
            SELECT
              COALESCE(cost, 0) AS shipment_total
            FROM
              spree_shipments AS s
            WHERE
              s.order_id = $1
          ) AS r2
        CROSS JOIN
          (
            SELECT
              COALESCE(SUM(amount), 0) AS adjustment_total
            FROM
              spree_adjustments AS a
            WHERE
              order_id = $1
          ) AS r3
        CROSS JOIN
          (
            SELECT
              SUM(li.quantity) AS item_count
            FROM
              spree_line_items AS li
            WHERE
              order_id = $1
          ) AS r4
      ) AS r
    WHERE
      spree_orders.id = $1
    ;
  }, [session[:v3_order_id]])

  redirect_to('/checkout/registration')
end



#  ::::::::  :::    ::: ::::::::::  ::::::::  :::    :::  ::::::::  :::    ::: :::::::::::
# :+:    :+: :+:    :+: :+:        :+:    :+: :+:   :+:  :+:    :+: :+:    :+:     :+:
# +:+        +:+    +:+ +:+        +:+        +:+  +:+   +:+    +:+ +:+    +:+     +:+
# +#+        +#++:++#++ +#++:++#   +#+        +#++:++    +#+    +:+ +#+    +:+     +#+
# +#+        +#+    +#+ +#+        +#+        +#+  +#+   +#+    +#+ +#+    +#+     +#+
# #+#    #+# #+#    #+# #+#        #+#    #+# #+#   #+#  #+#    #+# #+#    #+#     #+#
#  ########  ###    ### ##########  ########  ###    ###  ########   ########      ###



def v3_check_out
  # This should never happen that an agent reaches this page without
  # reference to an order-tuple.
  #
  # When it happens, re-direct agent back to the cart-page.
  #
  if session[:v3_order_id].blank?
    flash[:notice] = %{Please select a shipping-option.}
    redirect_to('/v3/cart')
    return
  end

  # GOD FUCKING DAMN IT SPREE.
  #
  # Spree deletes the address-IDs associated with the order after they
  # register for a new account. Restore them here.
  #
  V3::U.qq(%{
    UPDATE
      spree_orders
    SET
       ship_address_id = $1
      ,bill_address_id = $2
    WHERE
      id = $3
    ;
  }, [session[:v3_shipping_address_id], session[:v3_billing_address_id], session[:v3_order_id]])

  tuple = V3::U.qq('SELECT * FROM retrieve_new_order($1);', [session[:v3_order_id]]).to_a[0]

  if tuple.nil?
    # WARNING:
    #
    # session[:v3_order_id] exists, but we cannot find all 5 tuples we
    # created earlier.
    #
    # What do we do in this scenario?
    #
    # For now let's reset-session and redirect to root.
    #
    reset_session
    flash[:notice] = %{Error: Session reset.}
    redirect_to('/v3/cart')
    return
  end

  # Here we associate an agent's credentials, whether authenticated or guest,
  # with their order.
  #
  # For authenticated agents, we associate their user-ID and e-mail with their
  # order-tuple.
  #
  # For guests, we associated their e-mail with their order-tuple.
  #
  # THIS IS THE ONLY PLACE WHERE THIS HAPPENS.
  #
  if spree_current_user
    V3::U.qq(%{
      UPDATE spree_orders SET
         user_id = $1
        ,email   = $2
      WHERE
        id = $3
      ;
    }, [spree_current_user.id, spree_current_user.email, session[:v3_order_id]])
  elsif session[:v3_guest_email].present?
    V3::U.qq(%{
      UPDATE spree_orders SET
        email = $1
      WHERE
        id = $2
      ;
    }, [session[:v3_guest_email], session[:v3_order_id]])
  else
    # WARNING:
    #
    # Agent made it this far but we have no account-credentials or guest-e-mail
    # to associate their order to.
    #
    # Re-direct agent back to v3_cart!
    #
    flash[:notice] = %{Please select a shipping-option.}
    redirect_to('/v3/cart')
    return
  end



  addresses_equal = true
  payment_method  = 'credit-card'

  errors = {
    shipping_address: {},
    billing_address: {},
    card: {}
  }

  if request.post?
    if ! params.has_key?('addresses_equal')
      addresses_equal = false
    end

    payment_method = params[:payment_method]

    if params[:po_number].present?
      V3::U.qq(%{
        UPDATE spree_orders SET
          po_number = $1
        WHERE
          id = $2
        ;
      }, [params[:po_number], session[:v3_order_id]])
    end

    if params[:order_comments].present?
      V3::U.qq(%{
        UPDATE spree_orders SET
          comments = $1
        WHERE
          id = $2
        ;
      }, [params[:order_comments], session[:v3_order_id]])
    end

    if params[:shipping_address][:name].blank?
      errors[:shipping_address][:name] = %{Please tell us your name.}
    end

    if params[:shipping_address][:address1].blank?
      errors[:shipping_address][:address1] = %{Please tell us your address.}
    end

    if params[:shipping_address][:city].blank?
      errors[:shipping_address][:city] = %{Please tell us your city.}
    end

    if params[:shipping_address][:phone].blank?
      errors[:shipping_address][:phone] = %{Please tell us your phone number.}
    end

    if params[:shipping_address][:state_id].blank?
      errors[:shipping_address][:state_id] = %{Please select a state.}
    end

    if params[:shipping_address][:zipcode].blank?
      errors[:shipping_address][:zipcode] = %{Please tell us your zip-code.}
    end

    sql_args = [
      params[:shipping_address][:company],
      params[:shipping_address][:name],
      params[:shipping_address][:address1],
      params[:shipping_address][:address2],
      params[:shipping_address][:city],
      params[:shipping_address][:phone],
      params[:shipping_address][:state_id].to_i,
      params[:shipping_address][:zipcode],
      session[:v3_shipping_address_id]
    ]



    V3::U.qq(%{
      UPDATE spree_addresses SET
         company   = $1
        ,name      = $2
        ,address1  = $3
        ,address2  = $4
        ,city      = $5
        ,phone     = $6
        ,state_id  = $7
        ,zipcode   = $8
      WHERE
        id = $9
      ;
    }, sql_args)

    # 2018-05-15; Github-issue-354.
    #
    # Copy shipping-address into customer-address.
    #
    # Presently, customer-address isn't created along with the 5 other
    # tuples. Create it here.
    #
    sql_args = [
      params[:shipping_address][:company],
      params[:shipping_address][:name],
      params[:shipping_address][:address1],
      params[:shipping_address][:address2],
      params[:shipping_address][:city],
      params[:shipping_address][:state_id].to_i,
      params[:shipping_address][:zipcode],
      params[:shipping_address][:country_id],
      params[:shipping_address][:phone]
    ]

    # This will continually create new addresses and continually attach the
    # newest one to the order. Not ideal, and... I don't care right now.
    #
    cust_address_id = V3::U.qq(%{
      INSERT INTO spree_addresses
        (company, name, address1, address2, city, state_id, zipcode, country_id, phone, created_at, updated_at)
      VALUES
        ($1, $2, $3, $4, $5, $6, $7, $8, $9, NOW() AT TIME ZONE 'utc', NOW() AT TIME ZONE 'utc')
      RETURNING
        id
      ;
    }, sql_args).values.flatten[0]

    # Update our order-tuple with the customer-address ID.
    #
    V3::U.qq(%{
      UPDATE spree_orders SET
        cust_address_id = $1
      WHERE
        id = $2
      ;
    }, [cust_address_id, session[:v3_order_id]])

    if ! addresses_equal
      # 2018-03-19.
      #
      # Even if billing-address is distinct from shipping-address, do-not
      # validate agent's entries.

      sql_args = [
        params[:billing_address][:company],
        params[:billing_address][:name],
        params[:billing_address][:address1],
        params[:billing_address][:address2],
        params[:billing_address][:city],
        params[:billing_address][:country_id],
        params[:billing_address][:state_id].to_i,
        params[:billing_address][:zipcode],
        params[:billing_address][:phone],
        session[:v3_billing_address_id]
      ]

      V3::U.qq(%{
        UPDATE spree_addresses SET
           company    = $1
          ,name       = $2
          ,address1   = $3
          ,address2   = $4
          ,city       = $5
          ,country_id = $6
          ,state_id   = $7
          ,zipcode    = $8
          ,phone      = $9
        WHERE
          id = $10
        ;
      }, sql_args)
    else
      # Update agent's billing-address with the data in our shipping-address.
      #
      sql_args = [
        params[:shipping_address][:company],
        params[:shipping_address][:name],
        params[:shipping_address][:address1],
        params[:shipping_address][:address2],
        params[:shipping_address][:city],
        params[:shipping_address][:state_id].to_i,
        params[:shipping_address][:zipcode],
        params[:shipping_address][:country_id],
        params[:shipping_address][:phone],
        session[:v3_billing_address_id]
      ]

      V3::U.qq(%{
        UPDATE spree_addresses SET
           company    = $1
          ,name       = $2
          ,address1   = $3
          ,address2   = $4
          ,city       = $5
          ,state_id   = $6
          ,zipcode    = $7
          ,country_id = $8
          ,phone      = $9
        WHERE
          id = $10
        ;
      }, sql_args)
    end

    # Reset credit-cards, sensitive-credit-cards.
    #
    cc_id = V3::U.qq(%{
      SELECT source_id FROM spree_payments AS p WHERE id = $1;
    }, [session[:v3_payment_id]]).values.flatten[0]

    # source_id will be nil when this is a new order with no previous
    # payment-methods attached, e.g. when the agent selects PayPal or
    # "other".
    #
    if ! cc_id.nil?
      V3::U.q(%{
        DELETE FROM spree_credit_cards WHERE id = #{cc_id} RETURNING id;
      }).values.flatten[0]

      V3::U.q(%{
        DELETE FROM spree_sensitive_credit_cards WHERE credit_card_id = (#{cc_id});
      })
    end

    if params[:payment_method] == 'credit-card'
      payment_method_id   = 2 # Authorize.net
      payment_source_type = 'Spree::CreditCard'

      cc_data = {
        name:               params[:card][:name],
        month:              params[:card][:month],
        year:               params[:card][:year],
        number:             params[:card][:number],
        verification_value: params[:card][:security_code]
      }

      if cc_data[:number].length < 15
        errors[:card][:number] = %{Please enter a valid credit card number.}
      end

      # Rely on ActiveMerchant to determine card-validity.
      #
      cc = ActiveMerchant::Billing::CreditCard.new(cc_data)

      if ! cc.valid?
        if cc.errors.has_key?('name') or params[:card][:name].blank?
          errors[:card][:name] = %{Please provide the full name on the credit card.}
        end

        # I have literally been told to do this.
        #
        # if cc.errors.has_key?('number')
        #   errors[:card][:number] = %{Please enter a valid credit card number.}
        # end

        if cc.errors.has_key?('verification_value')
          errors[:card][:security_code] = %{Please enter a valid security code.}
        end

        if cc.errors.has_key?('year') || cc.errors.has_key?('month')
          errors[:card][:expiration_date] = %{Please enter a valid expiration date.}
        end
      end

      # byebug

      cc_id = V3::U.qq(%{
        INSERT INTO spree_credit_cards
          (month, year, cc_type, last_digits, cvv, name, user_id, payment_method_id, "default", created_at, updated_at)
        VALUES
          ($1, $2, $3, $4, $5, $6, $7, $8, TRUE, NOW() AT TIME ZONE 'utc', NOW() AT TIME ZONE 'utc')
        RETURNING
          id
        ;
      }, [params[:card][:month], params[:card][:year], cc.brand, params[:card][:number].last(4), params[:card][:security_code], params[:card][:name], nil, session[:v3_payment_method_id]]).values.flatten[0]

      V3::U.qq(%{
        INSERT INTO spree_sensitive_credit_cards
          (number, cvv, credit_card_id)
        VALUES
          ($1, $2, $3)
        ;
      }, [params[:card][:number], params[:card][:security_code], cc_id])

      V3::U.qq(%{
        UPDATE spree_payments SET
           source_id         = $1
          ,source_type       = $2
          ,payment_method_id = $3
        WHERE
          id = $4
        ;
      }, [cc_id, payment_source_type, payment_method_id, session[:v3_payment_id]])

      V3::U.qq(%{
        UPDATE spree_payments SET
           source_id = $1
          ,source_type = $2
          ,payment_method_id = $3
        WHERE
          id = $4
        ;
      }, [cc_id, 'Spree::CreditCard', 2, session[:v3_payment_id]])
    elsif params[:payment_method] == 'paypal'
      payment_method_id   = 3 # PayPal
      payment_source_type = 'Spree::PaypalExpressCheckout'

      paypal_id = V3::U.q(%{
        INSERT INTO spree_paypal_express_checkouts
          (created_at)
        VALUES
          (NOW() AT TIME ZONE 'utc')
        RETURNING
          id
        ;
      }).values.flatten[0]

      V3::U.qq(%{
        UPDATE spree_payments SET
           source_id         = $1
          ,source_type       = $2
          ,payment_method_id = $3
        WHERE
          id = $4
        ;
      }, [paypal_id, payment_source_type, payment_method_id, session[:v3_payment_id]])
    else # other
      payment_method_id = 4 # Other

      V3::U.qq(%{
        UPDATE spree_payments SET
          payment_method_id = $1
        WHERE
          id = $2
        ;
      }, [payment_method_id, session[:v3_payment_id]])
    end

    if errors[:shipping_address].empty? && errors[:billing_address].empty? && errors[:card].empty?
      if params[:payment_method] == 'paypal'
        redirect_to(controller: 'paypal', action: 'express')
        return
      end

      order_number = V3::U.qq(%{
        UPDATE spree_orders SET
           state = 'complete'
          ,completed_at = NOW() AT TIME ZONE 'utc'
        WHERE
          id = $1
        RETURNING
          number
        ;
      }, [session[:v3_order_id]]).to_a[0]['number']

      if params[:order_comments].strip.present?
        V3::U.qq(%{
          INSERT INTO spree_legacy_statuses
            (customer_notified, status, order_id, created_at, updated_at, external_comments)
          VALUES
            (FALSE, 0, $1, NOW() AT TIME ZONE 'utc', NOW() AT TIME ZONE 'utc', $2)
          ;
        }, [session[:v3_order_id], params[:order_comments]])
      else
        V3::U.qq(%{
          INSERT INTO spree_legacy_statuses
            (customer_notified, status, order_id, created_at, updated_at)
          VALUES
            (FALSE, 0, $1, NOW() AT TIME ZONE 'utc', NOW() AT TIME ZONE 'utc')
          ;
        }, [session[:v3_order_id]])
      end



      # 2018-08-31; Github-issue-391.
      #
      # Mail-server stopped working ~48 hours ago.
      #
      # Christopher signed-up for hosted Microsoft Exchange, and that works
      # well-enough for Thunderbird, etc.
      #
      # It also worked fine with Ruby Mail Gem, when executed "directly".
      #
      # I couldn't integrate hosted Microsoft Exchange with ActionMailer
      # and DelayedJob and Rails-environment-config, so I wrote my own.
      #
      # Spree::OrderMailer.confirm_email(session[:v3_order_id]).deliver_later
      V3::Email.queue('order_confirmation', {order_id: session[:v3_order_id]})

      # 2018-09-28; Github-issue-423.
      #
      # Decrement `in_stock` accordingly.
      #
      V3::U.qq(%{
        UPDATE spree_variants SET
          in_stock = in_stock - r.quantity
        FROM
          (
            SELECT
                v.id
              , li.quantity
            FROM
              spree_orders AS o
            INNER JOIN
              spree_line_items AS li
            ON
              o.id = li.order_id
            INNER JOIN
              spree_variants AS v
            ON
              li.variant_id = v.id
            AND
              v.in_stock_enforced = TRUE
            WHERE
              o.id = $1
          ) AS r
        WHERE
          spree_variants.id = r.id
        ;
      }, [session[:v3_order_id]])

      # Reset ALL our v3 session-values.
      #
      session[:cart]                                        = nil
      session[:v3_order_id]                                 = nil
      session[:v3_shipping_address_id]                      = nil
      session[:v3_billing_address_id]                       = nil
      session[:v3_payment_id]                               = nil
      session[:v3_shipment_id]                              = nil
      session[:v3_zipcode]                                  = nil
      session[:v3_country]                                  = nil
      session[:v3_residential]                              = nil
      session[:v3_guest_email]                              = nil
      session[:redirect_authenticated_agent_to_checkout]    = nil
      session[:redirect_newly_registered_agent_to_checkout] = nil
      session[:v3_coupon_code]                              = nil

      # 2018-12-18; Github-issue-469.
      #
      # This is an attempt to protect order-confirmation-screens.
      #
      # Right now, going to /orders/thank-you/V26657, and changing the
      # order-number yields the addresses, products, etc., an agent has
      # placed.
      #
      # General idea is to:
      #
      #   a) Guest-check-out: limited-access to this screen; limited to
      #      session-duration.
      #
      #   b) Registered-check-out: check that the order-number-reuqested
      #      belongs to the current-agent.
      #
      session[:v3_order_conf] = order_number

      redirect_to('/orders/thank-you/' + order_number)
      return
    else
      flash.now[:notice] = %{Please review the errors below.}
    end
  end # if request.post?

  po_number, order_comments = V3::U.qq(%{
    SELECT COALESCE(po_number, '') AS po_number, COALESCE(comments, '') AS order_comments FROM spree_orders WHERE id = $1;
  }, [session[:v3_order_id]]).values.flatten

  shipping_address = V3::U.qq(%{
    SELECT
       a.name
      ,address1
      ,address2
      ,city
      ,zipcode
      ,phone
      ,company
      ,s.name       AS state_name
      ,s.id::TEXT   AS state_id
      ,c.name       AS country_name
      ,c.id::TEXT   AS country_id
      ,state_locked
    FROM
      spree_orders AS o
    LEFT JOIN
      spree_addresses AS a
    ON
      o.ship_address_id = a.id
    LEFT JOIN
      spree_countries AS c
    ON
      a.country_id = c.id
    LEFT JOIN
      spree_states AS s
    ON
      a.state_id = s.id
    WHERE
      o.id = $1
    ;
  }, [session[:v3_order_id]]).to_a[0]

  billing_address = V3::U.qq(%{
    SELECT
       a.name
      ,address1
      ,address2
      ,city
      ,zipcode
      ,phone
      ,company
      ,s.name AS state_name
      ,s.id::TEXT   AS state_id
      ,c.name AS country_name
      ,c.id::TEXT   AS country_id
    FROM
      spree_orders AS o
    LEFT JOIN
      spree_addresses AS a
    ON
      o.bill_address_id = a.id
    LEFT JOIN
      spree_countries AS c
    ON
      a.country_id = c.id
    LEFT JOIN
      spree_states AS s
    ON
      a.state_id = s.id
    WHERE
      o.id = $1
    ;
  }, [session[:v3_order_id]]).to_a[0]

  @states = V3::U.qq(%{
    SELECT
       id::TEXT
      ,name
    FROM
      spree_states
    WHERE
      country_id = $1
    ;
  }, [shipping_address['country_id']])

  credit_card = V3::U.qq(%{
    SELECT
       COALESCE(cc.name, '')    AS name
      ,COALESCE(cc.year, '')    AS year
      ,COALESCE(cc.month, '')   AS month
      ,COALESCE(scc.number, '') AS number
      ,COALESCE(scc.cvv, '')    AS security_code
    FROM
      spree_payments AS p
    LEFT JOIN
      spree_credit_cards AS cc
    ON
      p.source_type = 'Spree::CreditCard'
    AND
      p.source_id = cc.id
    LEFT JOIN
      spree_sensitive_credit_cards AS scc
    ON
      scc.credit_card_id = cc.id
    WHERE
      p.id = $1
    ;
  }, [session[:v3_payment_id]]).to_a[0]

  if credit_card.nil?
    credit_card = {
      name: '',
      year: '',
      month: '',
      number: '',
      security_code: ''
    }
  end

  @cart = V3::U.qq(%{
    SELECT
       r.product_id
      ,r.title
      ,r.quantity
      ,r.unit_price
      ,r.quantity_price
      ,'/spree/products/' || a.id || '/mini/' || a.attachment_file_name AS image
    FROM
      (
        SELECT
           r.product_id
          ,r.title
          ,r.quantity
          ,r.unit_price
          ,r.quantity_price
          ,MIN(a.position) AS minima
        FROM
          (
            SELECT
               v.id AS product_id
              ,v.title
              ,li.quantity
              ,li.price               AS unit_price
              ,li.price * li.quantity AS quantity_price
            FROM
              spree_orders AS o
            LEFT JOIN
              spree_line_items AS li
            ON
              o.id = li.order_id
            LEFT JOIN
              spree_variants AS v
            ON
              li.variant_id = v.id
            WHERE
              o.id = $1
          ) AS r
        LEFT JOIN
          spree_assets AS a
        ON
          a.viewable_id = r.product_id
        AND
          a.viewable_type = 'Spree::Variant'
        GROUP BY
           r.product_id
          ,r.title
          ,r.quantity
          ,r.unit_price
          ,r.quantity_price
      ) AS r
    LEFT JOIN
      spree_assets AS a
    ON
      r.product_id = a.viewable_id
    AND
      r.minima = a.position
    ;
  }, [session[:v3_order_id]]).to_a



  @subtotal = @cart.collect { |li| BigDecimal.new(li['quantity_price']) }.sum

  @discount = V3::U.qq(%{
    SELECT
        a.label
      , a.amount
    FROM
      spree_adjustments AS a
    WHERE
      a.order_id = $1
    AND
      a.source_type = 'Coupon'
    LIMIT
      1
    ;
  }, [session[:v3_order_id]]).to_a[0]

  @shipping_rate = V3::U.qq(%{
    SELECT
       sm.name
      ,s.cost
    FROM
      spree_shipments AS s
    LEFT JOIN
      spree_shipping_rates AS sr
    ON
      s.id = sr.shipment_id
    AND
      sr.selected = TRUE
    LEFT JOIN
      spree_shipping_methods AS sm
    ON
      sr.shipping_method_id = sm.id
    WHERE
      s.order_id = $1
    ;
  }, [session[:v3_order_id]]).to_a[0]

  @all_countries = V3::U.q(%{
    SELECT
       id::TEXT   AS country_id
      ,iso  AS country_iso
      ,name AS country_name
    FROM
      spree_countries AS c
    ORDER BY
      position
    ;
  }).to_a

  @all_states = V3::U.q(%{
    SELECT
       id::TEXT AS state_id
      ,name AS state_name
      ,country_id::TEXT AS country_id
    FROM
      spree_states
    ORDER BY
       country_id
      ,name
    ;
  }).to_a.group_by { |state| state['country_id'] }

  lof = V3::U.qq(%{
    SELECT
        amount::TEXT
      , label
    FROM
      spree_adjustments AS a
    WHERE
      a.order_id = $1
    AND
      a.label ILIKE 'Low Order Fee (%'
    LIMIT
      1
    ;
  }, [session[:v3_order_id]]).to_a[0]

  if lof.nil?
    @lof = 0
  else
    @lof = BigDecimal.new(lof['amount'])
    @lol = lof['label']
  end

  @sales_tax = V3::U.qq(%{
    SELECT
      COALESCE(SUM(amount), 0) AS sales_tax
    FROM
      spree_adjustments AS a
    WHERE
      order_id = $1
    AND
      a.source_type = 'Spree::TaxRate'
    ;
  }, [session[:v3_order_id]]).to_a[0]['sales_tax']

  @grand_total = V3::U.qq(%{
    SELECT
      total AS grand_total
    FROM
      spree_orders AS o
    WHERE
      id = $1
    ;
  }, [session[:v3_order_id]]).to_a[0]['grand_total']

  @vue_data = {
    shipping_address: shipping_address,
    billing_address:  billing_address,
    card:             credit_card,
    payment_method:   payment_method,
    addresses_equal:  addresses_equal,
    errors:           errors,
    all_countries:    @all_countries,
    all_states:       @all_states,
    po_number:        po_number,
    order_comments:   order_comments
  }

  render(layout: 'spree/layouts/master', template: 'spree/static_page/v3_check_out_mobile')
end
