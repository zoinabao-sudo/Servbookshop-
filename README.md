# ServBookshop

A bilingual (English / Arabic) starter storefront for books, stationery and school supplies.

## What's in this repository

- `index.html` — storefront page
- `styles.css` — responsive styling and RTL support
- `app.js` — catalogue demo, cart, sample coupon and WhatsApp-order handoff
- `supabase/schema.sql` — starter database tables and row-level security policies
- `.github/workflows/deploy-pages.yml` — GitHub Pages deployment workflow

## Current status

This is a **starter/demo storefront**, not yet a production-ready shop. The displayed products are sample data. Customer accounts, live inventory, order creation/tracking, reviews, admin tools and payment processing still need application integration and testing against a real Supabase project. WhatsApp ordering needs the shop's WhatsApp number configured in `app.js`.

## Publish with GitHub Pages

The workflow deploys the repository root when changes are pushed to `main`. In the repository's **Settings → Pages**, set the build and deployment source to **GitHub Actions** if it is not already selected. Then check the **Actions** tab for a successful deployment.

## Supabase setup

1. Create a Supabase project.
2. Open **SQL Editor** and run `supabase/schema.sql`.
3. Copy the project URL and publishable/anon key into the application only when the Supabase integration is added.
4. Never place a Supabase `service_role` key in browser code.

The SQL file is a starting schema and should be reviewed and tested before production use.
