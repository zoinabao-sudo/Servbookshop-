-- ServBookshop starter schema for Supabase (PostgreSQL)
create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text,
  phone text,
  preferred_language text not null default 'en' check (preferred_language in ('en','ar')),
  created_at timestamptz not null default now()
);

create table if not exists public.books (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  title_ar text,
  description text,
  description_ar text,
  category text not null default 'Books',
  price numeric(10,2) not null check (price >= 0),
  stock integer not null default 0 check (stock >= 0),
  image_url text,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.orders (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete set null,
  customer_name text not null,
  phone text not null,
  email text,
  address text,
  status text not null default 'pending' check (status in ('pending','confirmed','processing','shipped','delivered','cancelled')),
  subtotal numeric(10,2) not null default 0 check (subtotal >= 0),
  discount numeric(10,2) not null default 0 check (discount >= 0),
  total numeric(10,2) not null default 0 check (total >= 0),
  currency text not null default 'USD',
  created_at timestamptz not null default now()
);

create table if not exists public.order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  book_id uuid references public.books(id) on delete set null,
  item_title text not null,
  quantity integer not null check (quantity > 0),
  unit_price numeric(10,2) not null check (unit_price >= 0)
);

create table if not exists public.reviews (
  id uuid primary key default gen_random_uuid(),
  book_id uuid not null references public.books(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  rating integer not null check (rating between 1 and 5),
  comment text,
  approved boolean not null default false,
  created_at timestamptz not null default now(),
  unique(book_id,user_id)
);

create table if not exists public.coupons (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  discount_percent integer not null check (discount_percent between 1 and 100),
  active boolean not null default true,
  expires_at timestamptz,
  created_at timestamptz not null default now()
);

alter table public.profiles enable row level security;
alter table public.books enable row level security;
alter table public.orders enable row level security;
alter table public.order_items enable row level security;
alter table public.reviews enable row level security;
alter table public.coupons enable row level security;

create policy "Profiles: users read own" on public.profiles for select to authenticated using (auth.uid() = id);
create policy "Profiles: users insert own" on public.profiles for insert to authenticated with check (auth.uid() = id);
create policy "Profiles: users update own" on public.profiles for update to authenticated using (auth.uid() = id) with check (auth.uid() = id);

create policy "Books: public read active" on public.books for select to anon, authenticated using (active = true);
create policy "Orders: customers read own" on public.orders for select to authenticated using (auth.uid() = user_id);
create policy "Orders: signed-in customers create own" on public.orders for insert to authenticated with check (auth.uid() = user_id);
create policy "Order items: customers read own order items" on public.order_items for select to authenticated using (exists (select 1 from public.orders o where o.id = order_id and o.user_id = auth.uid()));
create policy "Reviews: public read approved" on public.reviews for select to anon, authenticated using (approved = true or auth.uid() = user_id);
create policy "Reviews: signed-in users create own" on public.reviews for insert to authenticated with check (auth.uid() = user_id);
create policy "Reviews: users update own pending review" on public.reviews for update to authenticated using (auth.uid() = user_id and approved = false) with check (auth.uid() = user_id and approved = false);
create policy "Coupons: public read active" on public.coupons for select to anon, authenticated using (active = true and (expires_at is null or expires_at > now()));

-- Admin write access should be added only after an admin role is configured securely.
-- Never put the Supabase service_role key in browser JavaScript.
