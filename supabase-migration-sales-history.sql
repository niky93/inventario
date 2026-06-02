alter table public.products
  add column if not exists sold_units integer not null default 0 check (sold_units >= 0),
  add column if not exists profit_total numeric(12, 2) not null default 0;

alter table public.movements
  drop constraint if exists movements_type_check;

alter table public.movements
  drop constraint if exists movements_note_check;

alter table public.movements
  add constraint movements_type_check
  check (type in ('initial', 'entry', 'exit', 'adjustment', 'edit'));

alter table public.movements
  add constraint movements_note_check
  check (char_length(note) <= 500);

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

  update public.products
    set quantity = quantity + difference,
        sold_units = sold_units + case when p_type = 'exit' then p_quantity else 0 end,
        profit_total = profit_total + case
          when p_type = 'exit' then p_quantity * (sale_price - purchase_price)
          else 0
        end,
        updated_at = now()
    where id = current_product.id;

  insert into public.movements (owner_id, product_id, product_name, type, quantity, note)
    values (current_user_id, current_product.id, current_product.name, p_type, difference, trim(p_note));
end;
$$;

create or replace function public.update_inventory_product(
  p_product_id uuid,
  p_name text,
  p_code text,
  p_category text,
  p_description text,
  p_min_stock integer,
  p_purchase_price numeric,
  p_sale_price numeric
)
returns void
language plpgsql
security invoker
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  current_product public.products%rowtype;
  changes text[] := array[]::text[];
begin
  if current_user_id is null then
    raise exception 'Debes iniciar sesion.';
  end if;

  select *
    into current_product
    from public.products
    where id = p_product_id and owner_id = current_user_id
    for update;

  if not found then
    raise exception 'Producto no encontrado.';
  end if;

  if current_product.name is distinct from trim(p_name) then
    changes := array_append(changes, format('Nombre: "%s" -> "%s"', current_product.name, trim(p_name)));
  end if;
  if current_product.purchase_price is distinct from p_purchase_price then
    changes := array_append(changes, format('Compra: Bs %s -> Bs %s', current_product.purchase_price, p_purchase_price));
  end if;
  if current_product.sale_price is distinct from p_sale_price then
    changes := array_append(changes, format('Venta: Bs %s -> Bs %s', current_product.sale_price, p_sale_price));
  end if;

  update public.products
    set name = trim(p_name),
        code = trim(p_code),
        category = trim(p_category),
        description = trim(p_description),
        min_stock = p_min_stock,
        purchase_price = p_purchase_price,
        sale_price = p_sale_price,
        updated_at = now()
    where id = current_product.id;

  if cardinality(changes) > 0 then
    insert into public.movements (owner_id, product_id, product_name, type, quantity, note)
      values (current_user_id, current_product.id, trim(p_name), 'edit', 0, array_to_string(changes, '; '));
  end if;
end;
$$;

revoke all on function public.update_inventory_product(uuid, text, text, text, text, integer, numeric, numeric) from public;
grant execute on function public.update_inventory_product(uuid, text, text, text, text, integer, numeric, numeric) to authenticated;
