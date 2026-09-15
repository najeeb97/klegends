# ClubMatch pilot

Mobile-first football club match, attendance and payment tracker. React + Vite on Vercel, Supabase Database/Auth/RPC.

## Phone verification

This pilot uses manual verification through the club admin and WhatsApp, with no paid OTP service.

1. Open a private invite link, enter a name and an Indian/GCC phone number.
2. The request remains **Unverified**. The app shows an eight-character request code.
3. Send that code directly to the club admin on WhatsApp **from the submitted number**.
4. Admin opens **Members**, checks the actual WhatsApp sender number against the request, enters the received code and approves.
5. Player taps **I’ve been approved — check again**. The browser retains the session.

A WhatsApp link or a correctly formatted phone number is not proof of ownership. The admin's sender-number check is essential. The app does not automatically query WhatsApp account existence or send messages.

Unverified members cannot use business RPCs, including reading match details, creating matches or joining matches. Direct table access remains denied. Approval requires an existing verified admin and the matching request code. Codes rotate after a correction, approval or revocation. The old verification toggle cannot approve new requests. Verified accounts cannot be recovered or transferred simply by entering the same phone number in another browser.

Existing verified members retain access. Existing unverified players must complete this flow. Pending requests can correct their own number from the same browser. The admin should help with duplicate-number or lost-browser cases; automatic account recovery is not included.

## Deployment

The SQL file in `supabase/migrations` upgrades the existing pilot database; this repository does not contain the original base schema. Apply the migration with the corresponding frontend update. Do not run the old pilot schema afterward, since it would overwrite the authorization checks.

A verified admin must already exist. Public signup no longer makes the first applicant an admin. An owner must provision the initial administrator through a trusted database setup for a fresh club.

Vercel uses `VITE_SUPABASE_URL` and `VITE_SUPABASE_PUBLISHABLE_KEY`. Never add a service-role key to frontend environment variables.

## Validation

- `npm ci`
- `npm run typecheck`
- `npm test` (phone formatting, selected-country consistency and safe return URLs)
- `npm run build`
- Run `tests/verification.sql` inside `BEGIN` / `ROLLBACK` against an upgraded database. It uses temporary test fixtures and exercises pending access denial, admin-only approval, direct table bypass denial, duplicate phones, corrected-code invalidation, approval replay, admin lockout prevention, cross-club denial and revocation. Never commit the fixture transaction.

The app retains the pilot rules: ₹50 per actual player, payment approval, two-unpaid-match join restriction, match-scoped collectors and WhatsApp-shareable pending-payment image.
