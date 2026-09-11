# ClubMatch pilot

Mobile-first football club match, attendance and payment tracker.

Stack: React + Vite on Vercel, Supabase Database/Auth/RPC.

Pilot rules include ₹50 per actual player, payment approval, 2-unpaid-match join restriction, match-scoped collectors, and a WhatsApp-shareable pending-payment image.

## First use

The club owner must be the first person to open the private invite URL:

`/login?invite=our-football-club`

The first member becomes the initial Admin. Do not share the invite broadly until that first admin registration is complete.
