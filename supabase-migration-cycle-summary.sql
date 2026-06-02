create or replace function public.register_inventory_movement(
  p_product_id uuid,
  p_type text,
  p_quantity integer,
  p_note text default ''
)
returns void
language plpgsql
security invoker
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  current_product public.products%rowtype;
  difference integer;
  movement_note text;
begin
  if current_user_id is null then
    raise exception 'Debes iniciar sesion.';
  end if;

  if p_type not in ('entry', 'exit', 'adjustment') then
    raise exception 'Tipo de movimiento no valido.';
  end if;

  if p_quantity < 0 or (p_type <> 'adjustment' and p_quantity = 0) then
    raise exception 'La cantidad indicada no es valida.';
  end if;

  select *
    into current_product
    from public.products
    where id = p_product_id and owner_id = current_user_id
    for update;

  if not found then
    raise exception 'Producto no encontrado.';
  end if;

  difference := case
    when p_type = 'exit' then -p_quantity
    when p_type = 'adjustment' then p_quantity - current_product.quantity
    else p_quantity
  end;

  if current_product.quantity + difference < 0 then
    raise exception 'No hay existencias suficientes para registrar esa salida.';
  end if;

  movement_note := trim(p_note);
  if current_product.quantity + difference = 0 then
    movement_note := concat_ws(
      '; ',
      nullif(movement_note, ''),
      format(
        'Cierre de ciclo: vendidos %s; ganancias Bs %s',
        current_product.sold_units + case when p_type = 'exit' then p_quantity else 0 end,
        current_product.profit_total + case
          when p_type = 'exit' then p_quantity * (current_product.sale_price - current_product.purchase_price)
          else 0
        end
      )
    );
  end if;

  update public.products
    set quantity = quantity + difference,
        sold_units = case
          when quantity + difference = 0 then 0
          else sold_units + case when p_type = 'exit' then p_quantity else 0 end
        end,
        profit_total = case
          when quantity + difference = 0 then 0
          else profit_total + case
            when p_type = 'exit' then p_quantity * (sale_price - purchase_price)
            else 0
          end
        end,
        updated_at = now()
    where id = current_product.id;

  insert into public.movements (owner_id, product_id, product_name, type, quantity, note)
    values (current_user_id, current_product.id, current_product.name, p_type, difference, movement_note);
end;
$$;

notify pgrst, 'reload schema';
