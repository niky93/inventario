create extension if not exists pgcrypto;

create table if not exists public.products (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  name text not null check (char_length(trim(name)) between 1 and 100),
  code text not null check (char_length(trim(code)) between 1 and 40),
  category text not null default '' check (char_length(category) <= 60),
  description text not null default '' check (char_length(description) <= 400),
  quantity integer not null default 0 check (quantity >= 0),
  min_stock integer not null default 0 check (min_stock >= 0),
  purchase_price numeric(12, 2) not null default 0 check (purchase_price >= 0),
  sale_price numeric(12, 2) not null default 0 check (sale_price >= 0),
  sold_units integer not null default 0 check (sold_units >= 0),
  profit_total numeric(12, 2) not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists products_owner_code_unique
  on public.products (owner_id, lower(code));

create index if not exists products_owner_id_index
  on public.products (owner_id);

create table if not exists public.movements (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  product_id uuid references public.products(id) on delete set null,
  product_name text not null,
  type text not null check (type in ('initial', 'entry', 'exit', 'adjustment', 'edit')),
  quantity integer not null,
  note text not null default '' check (char_length(note) <= 500),
  created_at timestamptz not null default now()
);

create index if not exists movements_owner_created_index
  on public.movements (owner_id, created_at desc);

alter table public.products enable row level security;
alter table public.movements enable row level security;

revoke all on table public.products from anon;
revoke all on table public.movements from anon;
grant select, insert, update, delete on table public.products to authenticated;
grant select, insert on table public.movements to authenticated;

drop policy if exists "Users can read own products" on public.products;
create policy "Users can read own products"
  on public.products for select
  to authenticated
  using ((select auth.uid()) = owner_id);

drop policy if exists "Users can create own products" on public.products;
create policy "Users can create own products"
  on public.products for insert
  to authenticated
  with check ((select auth.uid()) = owner_id);

drop policy if exists "Users can update own products" on public.products;
create policy "Users can update own products"
  on public.products for update
  to authenticated
  using ((select auth.uid()) = owner_id)
  with check ((select auth.uid()) = owner_id);

drop policy if exists "Users can delete own products" on public.products;
create policy "Users can delete own products"
  on public.products for delete
  to authenticated
  using ((select auth.uid()) = owner_id);

drop policy if exists "Users can read own movements" on public.movements;
create policy "Users can read own movements"
  on public.movements for select
  to authenticated
  using ((select auth.uid()) = owner_id);

drop policy if exists "Users can create own movements" on public.movements;
create policy "Users can create own movements"
  on public.movements for insert
  to authenticated
  with check ((select auth.uid()) = owner_id);

create or replace function public.create_inventory_product(
  p_name text,
  p_code text,
  p_category text,
  p_description text,
  p_min_stock integer,
  p_purchase_price numeric,
  p_sale_price numeric,
  p_initial_stock integer
)
returns uuid
language plpgsql
security invoker
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  new_product_id uuid;
begin
  if current_user_id is null then
    raise exception 'Debes iniciar sesion.';
  end if;

  if p_initial_stock < 0 then
    raise exception 'El stock inicial no puede ser negativo.';
  end if;

  insert into public.products (
    owner_id, name, code, category, description, quantity, min_stock, purchase_price, sale_price
  )
  values (
    current_user_id, trim(p_name), trim(p_code), trim(p_category), trim(p_description),
    p_initial_stock, p_min_stock, p_purchase_price, p_sale_price
  )
  returning id into new_product_id;

  if p_initial_stock > 0 then
    insert into public.movements (owner_id, product_id, product_name, type, quantity, note)
    values (current_user_id, new_product_id, trim(p_name), 'initial', p_initial_stock, 'Stock inicial');
  end if;

  return new_product_id;
end;
$$;

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

revoke all on function public.create_inventory_product(text, text, text, text, integer, numeric, numeric, integer) from public;
grant execute on function public.create_inventory_product(text, text, text, text, integer, numeric, numeric, integer) to authenticated;

revoke all on function public.register_inventory_movement(uuid, text, integer, text) from public;
grant execute on function public.register_inventory_movement(uuid, text, integer, text) to authenticated;

revoke all on function public.update_inventory_product(uuid, text, text, text, text, integer, numeric, numeric) from public;
grant execute on function public.update_inventory_product(uuid, text, text, text, text, integer, numeric, numeric) to authenticated;

notify pgrst, 'reload schema';
