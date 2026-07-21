# Backend API Notes

## Security choice

The mobile app should never store the Supabase service role key. The React Native app sends requests to FastAPI. FastAPI uses the Supabase service role key only on the server to upload profile images.

## Matching logic

The matching algorithm is simple and explainable for MVP:

- Shared interests
- Same major
- Shared looking-for goals
- Complementary language exchange
- Same class year

This is better than a hidden complex model at the beginning because the app can show human-friendly reasons like "You both like basketball." 

## Safety logic

- Messaging only happens after a match.
- Blocks prevent discovery and messaging.
- Reports are stored for admin review.
- Discovery excludes hidden profiles, suspended users, blocked users, existing matches, and pending requests.

## Future improvement

After the MVP works, replace `scripts/init_db.py` table creation with Alembic migrations for production-grade schema changes.
