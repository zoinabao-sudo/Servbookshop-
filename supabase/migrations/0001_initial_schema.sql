-- ServBookshop initial schema for Supabase
-- Run in Supabase SQL Editor. Never expose the service_role key in the browser.

create extension if not exists pgcrypto;

create type public.user_role as enum ('customer', 'admin');
create type public.order_status as enum ('pending', 'confirmed', 'processing', 'shipped', 'delivered', 'cancelled');
create type public.payment_status as enum ('unpaid', 'pending', 'paid', 'failed', 'refunded');

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text,
  phone text,
  preferred_language text not null default 'en' check (preferred_language in ('en','ar')),
  role public.user_role not null default 'customer',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.categories (
  id uuid primary key default gen_random_uuid(),
  name_en text not null,
  name_ar text not null,
  slug text not null unique,
  created_at timestamptz not null default now()
);

create table public.products (
  id uuid primary key default gen_random_uuid(),
  category_id uuid references public.categories(id) on delete set null,
  title_en text not null,
  title_ar text not null,
  author_en text,
  author_ar text,
  description_en text,
  description_ar text,
  sku text unique,
  price_usd numeric(10,2) not null check (price_usd >= 0),
  stock_quantity integer not null default 0 check (stock_quantity >= 0),
  image_url text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.orders (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references public.profiles(id),
  order_number bigint generated always as identity unique,
  customer_name text not null,
  email text,
  phone text not null,
  shipping_address text not null,
  notes text,
  currency text not null default 'USD' check (currency = 'USD'),
  subtotal_usd numeric(10,2) not null default 0 check (subtotal_usd >= 0),
  discount_usd numeric(10,2) not null default 0 check (discount_usd >= 0),
  total_usd numeric(10,2) not null default 0 check (total_usd >= 0),
  status public.order_status not null default 'pending',
  payment_status public.payment_status not null default 'unpaid',
  payment_method text,
  payment_reference text,
  coupon_code text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  product_id uuid references public.products(id) on delete set null,
  product_title text not null,
  quantity integer not null check (quantity > 0),
  unit_price_usd numeric(10,2) not null check (unit_price_usd >= 0),
  line_total_usd numeric(10,2) generated always as (quantity * unit_price_usd) stored
);

create table public.reviews (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.products(id) on delete cascade,
  customer_id uuid not null references public.profiles(id) on delete cascade,
  rating integer not null check (rating between 1 and 5),
  title text,
  body text,
  is_approved boolean not null default false,
  created_at timestamptz not null default now(),
  unique(product_id, customer_id)
);

create table public.coupons (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  description text,
  discount_percent numeric(5,2) check (discount_percent > 0 and discount_percent <= 100),
  discount_amount_usd numeric(10,2) check (discount_amount_usd >= 0),
  minimum_order_usd numeric(10,2) not null default 0,
  usage_limit integer check (usage_limit > 0),
  used_count integer not null default 0 check (used_count >= 0),
  starts_at timestamptz,
  expires_at timestamptz,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  check ((discount_percent is not null) <> (discount_amount_usd is not null))
);

create table public.coupon_redemptions (
  id uuid primary key default gen_random_uuid(),
  coupon_id uuid not null references public.coupons(id),
  customer_id uuid not null references public.profiles(id),
  order_id uuid not null unique references public.orders(id),
  redeemed_at timestamptz not null default now(),
  unique(coupon_id, customer_id, order_id)
);

create index products_category_idx on public.products(category_id);
create index products_active_idx on public.products(is_active);
create index orders_customer_idx on public.orders(customer_id, created_at desc);
create index orders_status_idx on public.orders(status);
create index order_items_order_idx on public.order_items(order_id);
create index reviews_product_approved_idx on public.reviews(product_id, is_approved);

create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger profiles_updated_at before update on public.profiles
for each row execute function public.set_updated_at();
create trigger products_updated_at before update on public.products
for each row execute function public.set_updated_at();
create trigger orders_updated_at before update on public.orders
for each row execute function public.set_updated_at();

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  insert into public.profiles (id, full_name)
  values (new.id, coalesce(new.raw_user_meta_data ->> 'full_name', ''));
  return new;
end;
$$;

create trigger on_auth_user_created after insert on auth.users
for each row execute procedure public.handle_new_user();

create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.profiles
    where id = (select auth.uid()) and role = 'admin'
  );
$$;

alter table public.profiles enable row level security;
alter table public.categories enable row level security;
alter table public.products enable row level security;
alter table public.orders enable row level security;
alter table public.order_items enable row level security;
alter table public.reviews enable row level security;
alter table public.coupons enable row level security;
alter table public.coupon_redemptions enable row level security;

create policy "Customers read own profile" on public.profiles
for select to authenticated using (id = (select auth.uid()) or public.is_admin());
create policy "Customers update own profile" on public.profiles
for update to authenticated using (id = (select auth.uid())) with check (id = (select auth.uid()) and role = 'customer');
create policy "Admins manage profiles" on public.profiles
for all to authenticated using (public.is_admin()) with check (public.is_admin());

create policy "Anyone reads categories" on public.categories
for select using (true);
create policy "Admins manage categories" on public.categories
for all to authenticated using (public.is_admin()) with check (public.is_admin());

create policy "Anyone reads active products" on public.products
for select using (is_active or public.is_admin());
create policy "Admins manage products" on public.products
for all to authenticated using (public.is_admin()) with check (public.is_admin());

create policy "Customers read own orders" on public.orders
for select to authenticated using (customer_id = (select auth.uid()) or public.is_admin());
create policy "Customers create own orders" on public.orders
for insert to authenticated with check (customer_id = (select auth.uid()) and status = 'pending' and payment_status = 'unpaid');
create policy "Admins manage orders" on public.orders
for all to authenticated using (public.is_admin()) with check (public.is_admin());

create policy "Customers read own order items" on public.order_items
for select to authenticated using (
  exists (select 1 from public.orders o where o.id = order_id and (o.customer_id = (select auth.uid()) or public.is_admin()))
);
create policy "Customers add items to own pending orders" on public.order_items
for insert to authenticated with check (
  exists (select 1 from public.orders o where o.id = order_id and o.customer_id = (select auth.uid()) and o.status = 'pending')
);
create policy "Admins manage order items" on public.order_items
for all to authenticated using (public.is_admin()) with check (public.is_admin());

create policy "Anyone reads approved reviews" on public.reviews
for select using (is_approved or customer_id = (select auth.uid()) or public.is_admin());
create policy "Customers create own reviews" on public.reviews
for insert to authenticated with check (customer_id = (select auth.uid()) and is_approved = false);
create policy "Customers update own pending reviews" on public.reviews
for update to authenticated using (customer_id = (select auth.uid()) and not is_approved)
with check (customer_id = (select auth.uid()) and not is_approved);
create policy "Admins moderate reviews" on public.reviews
for all to authenticated using (public.is_admin()) with check (public.is_admin());

create policy "Customers read active coupons" on public.coupons
for select to authenticated using (is_active and (starts_at is null or starts_at <= now()) and (expires_at is null or expires_at > now()) or public.is_admin());
create policy "Admins manage coupons" on public.coupons
for all to authenticated using (public.is_admin()) with check (public.is_admin());

create policy "Customers read own coupon redemptions" on public.coupon_redemptions
for select to authenticated using (customer_id = (select auth.uid()) or public.is_admin());
create policy "Admins manage coupon redemptions" on public.coupon_redemptions
for all to authenticated using (public.is_admin()) with check (public.is_admin());

grant usage on schema public to anon, authenticated;
grant select on public.categories to anon, authenticated;
grant select on public.products to anon, authenticated;
grant select on public.reviews to anon, authenticated;
grant select on public.coupons to authenticated;
grant select, update on public.profiles to authenticated;
grant insert, select on public.orders to authenticated;
grant insert, select on public.order_items to authenticated;
grant insert, select, update on public.reviews to authenticated;
grant select on public.coupon_redemptions to authenticated;
grant all on public.categories, public.products, public.orders, public.order_items, public.reviews, public.coupons, public.coupon_redemptions to authenticated;

-- After creating your own account, promote it from the SQL editor:
-- update public.profiles set role = 'admin' where id = 'YOUR_AUTH_USER_UUID';
