# ServBookshop

Bilingual English/Arabic bookshop backend, with USD catalogue pricing.

## Supabase backend

The initial schema is in `supabase/migrations/20261115000100_initial_schema.sql`.

### Included
- Auth-linked customer profiles and customer/admin roles.
- English and Arabic book metadata.
- USD store settings and shipping configuration.
- Coupons with date, minimum-spend and usage-limit checks.
- Orders, line-item snapshots and payment records.
- Customer reviews with admin moderation.
- Row Level Security policies.
- Atomic `create_order` RPC that calculates prices from database records, validates coupons, locks/decrements stock and creates order/payment records.

### Apply the migration
1. Create a Supabase project and install the Supabase CLI.
2. Run `supabase login`.
3. Link this repository: `supabase link --project-ref YOUR_PROJECT_REF`.
4. Apply the schema: `supabase db push`.
5. Configure Supabase Auth providers, production Site URL and redirect URLs.
6. Create your own account, then promote it to admin in the Supabase SQL editor:
   `update public.profiles set role = 'admin' where id = 'YOUR_AUTH_USER_UUID';`
7. Set shipping fee, WhatsApp number and support email in `store_settings`.

### Frontend checkout integration
Call the authenticated RPC `create_order` with:
- `p_items`: array of `{ "book_id": "UUID", "quantity": 1 }`
- `p_customer_name`, `p_customer_email`, `p_customer_phone`
- `p_shipping_address`: JSON object
- `p_payment_method`: `online`, `manual_transfer` or `cash_on_delivery`
- optional `p_coupon_code` and `p_customer_note`

Do not send trusted prices from the browser; the RPC reads book prices from the database. Read orders and order items only for the signed-in customer (admins can manage all). Customer reviews are private until approved.

### Important launch requirements
This migration stores online-payment records but does not integrate a payment gateway. Before accepting online payments, select a provider that supports your business and settlement country, implement server-side payment initiation and signature-verified webhooks, and test refunds/failure handling. Keep service-role keys and provider secrets on a trusted server only. Manual-transfer proof uploads and admin verification also need a private storage bucket and workflow.

Never expose the Supabase service-role key in frontend code. Test RLS, checkout concurrency, stock rollback, coupon limits and admin access before launch.
