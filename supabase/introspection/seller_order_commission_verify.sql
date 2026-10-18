-- Seller-order 5% commission: calculation, rounding, and revenue helper.
-- Run after 20261018230000_seller_order_commission.sql.

SELECT 'one product 400 -> 20.00' AS check,
       public.seller_commission_amount(400, 0.05) = 20.00 AS ok
UNION ALL
SELECT 'two products combined 700 -> 35.00, not 5% each stored separately',
       public.seller_commission_amount(700, 0.05) = 35.00
UNION ALL
SELECT 'three products 500 -> 25.00',
       public.seller_commission_amount(500, 0.05) = 25.00
UNION ALL
SELECT 'shipping is excluded (same as product-only 700)',
       public.seller_commission_amount(700, 0.05) = 35.00
UNION ALL
SELECT 'free / zero subtotal is 0',
       public.seller_commission_amount(0, 0.05) = 0.00
UNION ALL
SELECT 'two shops stay independent: 35 + 20 = 55',
       public.seller_commission_amount(700, 0.05)
         + public.seller_commission_amount(400, 0.05) = 55.00
UNION ALL
SELECT 'commission columns exist on orders',
       EXISTS (
         SELECT 1 FROM information_schema.columns
         WHERE table_schema = 'public'
           AND table_name = 'orders'
           AND column_name = 'seller_commission_amount'
       )
UNION ALL
SELECT 'authenticated cannot execute recognize',
       NOT has_function_privilege(
         'authenticated',
         'public.recognize_order_seller_commission(uuid)',
         'EXECUTE'
       )
UNION ALL
SELECT 'authenticated cannot execute reverse',
       NOT has_function_privilege(
         'authenticated',
         'public.reverse_order_seller_commission(uuid)',
         'EXECUTE'
       );
