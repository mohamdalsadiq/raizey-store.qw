# RAIZEY STORE — Replit Project

## Overview
RAIZEY STORE is an Arabic digital game store for top-ups (PUBG Mobile shards, Free Fire gems, Google Play cards, subscriptions). The app was imported from Vercel and ported to Replit's pnpm workspace.

## Architecture
- **Frontend** (`artifacts/digital-store/`): Static multi-page HTML/CSS/JS app served via Vite dev server. All pages are in `public/` so Vite serves them without transformation.
- **Backend** (`artifacts/api-server/`): Express server scaffolded but not yet used by the store (the store connects directly to Supabase).
- **Database**: Supabase (external). Client config in `artifacts/digital-store/public/assets/js/supabase-client.js`.

## Key Files
- Store pages: `artifacts/digital-store/public/*.html`
- Styles: `artifacts/digital-store/public/assets/css/style.css`
- JS: `artifacts/digital-store/public/assets/js/`
- Supabase client: `artifacts/digital-store/public/assets/js/supabase-client.js`

## User Preferences
- Do not push to GitHub unless explicitly asked.
- Commit and push changes only when the user explicitly requests it.
