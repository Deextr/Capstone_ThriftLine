-- Admin SQL helpers for auction bid risk events (capstone demo).
-- Run in Supabase SQL Editor as an admin user, or use Admin → Reports → Bid risk events.

-- Recent blocked or flagged bids
SELECT
  event_id,
  user_id,
  auction_id,
  attempted_amount,
  risk_level,
  action_taken,
  reasons,
  created_at
FROM public.auction_bid_risk_events
WHERE action_taken IN ('blocked', 'flagged')
ORDER BY created_at DESC
LIMIT 50;

-- Risk events for one user
-- SELECT * FROM public.auction_bid_risk_events
-- WHERE user_id = 'USER_UUID_HERE'
-- ORDER BY created_at DESC;
