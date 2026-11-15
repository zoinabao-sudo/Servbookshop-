# ServBookshop Supabase backend

## Database setup
1. Open your Supabase project.
2. Go to SQL Editor and create a new query.
3. Paste and run `supabase/migrations/0001_initial_schema.sql`.
4. Create your first account through the app, then promote it to admin using the commented SQL statement at the bottom of the migration. Find the user's UUID under Authentication > Users.
5. In Project Settings > API, copy the Project URL and the publishable/anon key into your local `.env` file. Never put the service-role/secret key in frontend code or commit credentials.

## Included tables
Profiles, categories, products, orders, order_items, reviews, coupons and coupon_redemptions. RLS policies separate customer access from administrator access.

## Important production notes
This migration is a secure starting point, not a complete commerce engine. Before accepting live payments, add a trusted server-side checkout function that recalculates prices, validates coupons, checks/reserves stock and writes order totals atomically. Payment provider secrets and payment verification must remain server-side. Do not trust prices, discounts, totals or payment status submitted by a browser.
