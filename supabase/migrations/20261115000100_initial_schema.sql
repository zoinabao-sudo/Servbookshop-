-- ServBookshop Supabase schema
-- Apply with: supabase db push (or paste into the Supabase SQL editor).
create extension if not exists pgcrypto;

create type public.app_role as enum ('customer','admin');
create type public.order_status as enum ('pending','confirmed','processing','shipped','delivered','cancelled');
create type public.payment_status as enum ('pending','paid','failed','refunded');
create type public.payment_method as enum ('online','manual_transfer','cash_on_delivery');

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text,
  phone text,
  preferred_language text not null default 'en' check (preferred_language in ('en','ar')),
  role public.app_role not null default 'customer',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.books (
  id uuid primary key default gen_random_uuid(),
  slug text unique not null,
  title_en text not null,
  title_ar text,
  author_en text,
  author_ar text,
  description_en text,
  description_ar text,
  category_en text,
  category_ar text,
  isbn text,
  cover_image_url text,
  price_usd numeric(12,2) not null check (price_usd >= 0),
  compare_at_price_usd numeric(12,2) check (compare_at_price_usd is null or compare_at_price_usd >= price_usd),
  stock integer not null default 0 check (stock >= 0),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index books_active_category_idx on public.books(is_active, category_en);
create index books_title_en_idx on public.books using gin (to_tsvector('english', title_en || ' ' || coalesce(author_en,'')));

create table public.store_settings (
  id boolean primary key default true check (id),
  currency text not null default 'USD' check (currency = 'USD'),
  shipping_fee_usd numeric(12,2) not null default 0 check (shipping_fee_usd >= 0),
  whatsapp_number text,
  support_email text,
  updated_at timestamptz not null default now()
);
insert into public.store_settings(id) values (true) on conflict do nothing;

create table public.coupons (
  id uuid primary key default gen_random_uuid(),
  code text unique not null,
  discount_type text not null check (discount_type in ('percent','fixed')),
  discount_value numeric(12,2) not null check (discount_value > 0),
  minimum_order_usd numeric(12,2) not null default 0 check (minimum_order_usd >= 0),
  max_uses integer check (max_uses is null or max_uses > 0),
  uses_count integer not null default 0 check (uses_count >= 0),
  starts_at timestamptz,
  expires_at timestamptz,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create table public.orders (
  id uuid primary key default gen_random_uuid(),
  order_number text unique not null default ('SB-' || upper(substr(replace(gen_random_uuid()::text,'-',''),1,10))),
  user_id uuid not null references public.profiles(id),
  status public.order_status not null default 'pending',
  payment_method public.payment_method not null,
  payment_status public.payment_status not null default 'pending',
  customer_name text not null,
  customer_email text not null,
  customer_phone text not null,
  shipping_address jsonb not null,
  coupon_code text,
  subtotal_usd numeric(12,2) not null check (subtotal_usd >= 0),
  discount_usd numeric(12,2) not null default 0 check (discount_usd >= 0),
  shipping_usd numeric(12,2) not null default 0 check (shipping_usd >= 0),
  total_usd numeric(12,2) not null check (total_usd >= 0),
  customer_note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index orders_user_created_idx on public.orders(user_id, created_at desc);
create index orders_status_created_idx on public.orders(status, created_at desc);

create table public.order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  book_id uuid references public.books(id) on delete set null,
  title_snapshot text not null,
  quantity integer not null check (quantity > 0),
  unit_price_usd numeric(12,2) not null check (unit_price_usd >= 0),
  line_total_usd numeric(12,2) not null check (line_total_usd >= 0)
);

create table public.payments (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  provider text,
  provider_reference text unique,
  amount_usd numeric(12,2) not null check (amount_usd >= 0),
  status public.payment_status not null default 'pending',
  proof_image_url text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.reviews (
  id uuid primary key default gen_random_uuid(),
  book_id uuid not null references public.books(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  rating integer not null check (rating between 1 and 5),
  review_text text,
  is_approved boolean not null default false,
  created_at timestamptz not null default now(),
  unique(book_id, user_id)
);

create table public.coupon_redemptions (
  id uuid primary key default gen_random_uuid(),
  coupon_id uuid not null references public.coupons(id),
  order_id uuid not null unique references public.orders(id) on delete cascade,
  user_id uuid not null references public.profiles(id),
  redeemed_at timestamptz not null default now()
);

create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end;
$$;

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles(id, full_name)
  values (new.id, coalesce(new.raw_user_meta_data ->> 'full_name',''))
  on conflict (id) do nothing;
  return new;
end;
$$;
create trigger on_auth_user_created after insert on auth.users
for each row execute procedure public.handle_new_user();

create trigger profiles_updated before update on public.profiles for each row execute function public.set_updated_at();
create trigger books_updated before update on public.books for each row execute function public.set_updated_at();
create trigger orders_updated before update on public.orders for each row execute function public.set_updated_at();
create trigger payments_updated before update on public.payments for each row execute function public.set_updated_at();

create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = ''
as $$ select exists(select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin'); $$;

-- Atomic checkout: prices, stock, coupon and shipping are read on the server.
create or replace function public.create_order(
  p_items jsonb,
  p_customer_name text,
  p_customer_email text,
  p_customer_phone text,
  p_shipping_address jsonb,
  p_payment_method public.payment_method,
  p_coupon_code text default null,
  p_customer_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_item jsonb;
  v_book public.books%rowtype;
  v_order_id uuid;
  v_order_number text;
  v_subtotal numeric(12,2) := 0;
  v_discount numeric(12,2) := 0;
  v_shipping numeric(12,2) := 0;
  v_total numeric(12,2);
  v_qty integer;
  v_coupon public.coupons%rowtype;
  v_coupon_id uuid := null;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then raise exception 'Cart is empty'; end if;
  if length(trim(coalesce(p_customer_name,''))) = 0 or length(trim(coalesce(p_customer_phone,''))) = 0 then raise exception 'Customer name and phone are required'; end if;
  if p_shipping_address is null or jsonb_typeof(p_shipping_address) <> 'object' then raise exception 'A shipping address is required'; end if;

  select shipping_fee_usd into v_shipping from public.store_settings where id = true;
  v_shipping := coalesce(v_shipping,0);

  for v_item in select value from jsonb_array_elements(p_items) loop
    if (v_item->>'book_id') is null then raise exception 'Invalid book in cart'; end if;
    v_qty := (v_item->>'quantity')::integer;
    if v_qty < 1 or v_qty > 50 then raise exception 'Invalid quantity'; end if;
    select * into v_book from public.books where id = (v_item->>'book_id')::uuid and is_active = true for update;
    if not found then raise exception 'A selected book is unavailable'; end if;
    if v_book.stock < v_qty then raise exception 'Insufficient stock for %', v_book.title_en; end if;
    v_subtotal := v_subtotal + v_book.price_usd * v_qty;
  end loop;

  if p_coupon_code is not null and length(trim(p_coupon_code)) > 0 then
    select * into v_coupon from public.coupons
    where upper(code) = upper(trim(p_coupon_code)) and is_active = true
      and (starts_at is null or starts_at <= now())
      and (expires_at is null or expires_at > now())
      and (max_uses is null or uses_count < max_uses)
    for update;
    if not found then raise exception 'Coupon is invalid or expired'; end if;
    if v_subtotal < v_coupon.minimum_order_usd then raise exception 'Order does not meet coupon minimum'; end if;
    if v_coupon.discount_type = 'percent' then
      if v_coupon.discount_value > 100 then raise exception 'Invalid coupon configuration'; end if;
      v_discount := round(v_subtotal * v_coupon.discount_value / 100, 2);
    else
      v_discount := least(v_subtotal, v_coupon.discount_value);
    end if;
    v_coupon_id := v_coupon.id;
  end if;

  v_total := greatest(0, v_subtotal - v_discount + v_shipping);
  insert into public.orders(user_id,payment_method,customer_name,customer_email,customer_phone,shipping_address,coupon_code,subtotal_usd,discount_usd,shipping_usd,total_usd,customer_note)
  values (v_user,p_payment_method,trim(p_customer_name),lower(trim(p_customer_email)),trim(p_customer_phone),p_shipping_address,
    case when v_coupon_id is null then null else v_coupon.code end,v_subtotal,v_discount,v_shipping,v_total,p_customer_note)
  returning id, order_number into v_order_id, v_order_number;

  for v_item in select value from jsonb_array_elements(p_items) loop
    v_qty := (v_item->>'quantity')::integer;
    select * into v_book from public.books where id = (v_item->>'book_id')::uuid and is_active = true for update;
    update public.books set stock = stock - v_qty where id = v_book.id;
    insert into public.order_items(order_id,book_id,title_snapshot,quantity,unit_price_usd,line_total_usd)
    values (v_order_id,v_book.id,v_book.title_en,v_qty,v_book.price_usd,v_book.price_usd*v_qty);
  end loop;

  if v_coupon_id is not null then
    update public.coupons set uses_count = uses_count + 1 where id = v_coupon_id;
    insert into public.coupon_redemptions(coupon_id,order_id,user_id) values (v_coupon_id,v_order_id,v_user);
  end if;
  insert into public.payments(order_id,provider,amount_usd,status)
  values (v_order_id,p_payment_method::text,v_total,'pending');

  return jsonb_build_object('id',v_order_id,'order_number',v_order_number,'subtotal_usd',v_subtotal,
    'discount_usd',v_discount,'shipping_usd',v_shipping,'total_usd',v_total,'payment_status','pending');
end;
$$;

alter table public.profiles enable row level security;
alter table public.books enable row level security;
alter table public.store_settings enable row level security;
alter table public.coupons enable row level security;
alter table public.orders enable row level security;
alter table public.order_items enable row level security;
alter table public.payments enable row level security;
alter table public.reviews enable row level security;
alter table public.coupon_redemptions enable row level security;

create policy "Profiles readable by owner or admin" on public.profiles for select to authenticated using (id = auth.uid() or public.is_admin());
create policy "Customers update own profile" on public.profiles for update to authenticated using (id = auth.uid()) with check (id = auth.uid() and role = (select p.role from public.profiles p where p.id = auth.uid()));
create policy "Active books are public" on public.books for select using (is_active = true or public.is_admin());
create policy "Admins manage books" on public.books for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy "Store settings are public" on public.store_settings for select using (true);
create policy "Admins manage settings" on public.store_settings for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy "Admins manage coupons" on public.coupons for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy "Orders visible to owner or admin" on public.orders for select to authenticated using (user_id = auth.uid() or public.is_admin());
create policy "Admins update orders" on public.orders for update to authenticated using (public.is_admin()) with check (public.is_admin());
create policy "Order items visible to order owner or admin" on public.order_items for select to authenticated using (exists(select 1 from public.orders o where o.id = order_id and (o.user_id = auth.uid() or public.is_admin())));
create policy "Payments visible to order owner or admin" on public.payments for select to authenticated using (exists(select 1 from public.orders o where o.id = order_id and (o.user_id = auth.uid() or public.is_admin())));
create policy "Admins update payments" on public.payments for update to authenticated using (public.is_admin()) with check (public.is_admin());
create policy "Approved reviews are public" on public.reviews for select using (is_approved = true or user_id = auth.uid() or public.is_admin());
create policy "Customers submit own reviews" on public.reviews for insert to authenticated with check (user_id = auth.uid() and is_approved = false);
create policy "Customers edit own pending reviews" on public.reviews for update to authenticated using (user_id = auth.uid() and is_approved = false) with check (user_id = auth.uid() and is_approved = false);
create policy "Admins moderate reviews" on public.reviews for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy "Redemptions visible to owner or admin" on public.coupon_redemptions for select to authenticated using (user_id = auth.uid() or public.is_admin());

revoke all on function public.create_order(jsonb,text,text,text,jsonb,public.payment_method,text,text) from public;
grant execute on function public.create_order(jsonb,text,text,text,jsonb,public.payment_method,text,text) to authenticated;
grant execute on function public.is_admin() to anon, authenticated;

-- Set the first administrator manually in the SQL editor after creating their account:
-- update public.profiles set role = 'admin' where id = '<auth.users UUID>';
