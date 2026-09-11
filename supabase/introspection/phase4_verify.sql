-- Structural checks for Phase 4 messaging. Every row should be PASS
-- after 20260910010000_phase4_messaging.sql is applied.

WITH checks AS (
  SELECT 1 AS seq, 'conversations.product_id exists' AS check_name,
         EXISTS (
           SELECT 1 FROM information_schema.columns
           WHERE table_schema = 'public' AND table_name = 'conversations'
             AND column_name = 'product_id'
         ) AS ok
  UNION ALL SELECT 2, 'conversations.last_read_at_a exists',
         EXISTS (
           SELECT 1 FROM information_schema.columns
           WHERE table_schema = 'public' AND table_name = 'conversations'
             AND column_name = 'last_read_at_a'
         )
  UNION ALL SELECT 3, 'conversations.last_read_at_b exists',
         EXISTS (
           SELECT 1 FROM information_schema.columns
           WHERE table_schema = 'public' AND table_name = 'conversations'
             AND column_name = 'last_read_at_b'
         )
  UNION ALL SELECT 4, 'messages.attachment_path exists',
         EXISTS (
           SELECT 1 FROM information_schema.columns
           WHERE table_schema = 'public' AND table_name = 'messages'
             AND column_name = 'attachment_path'
         )
  UNION ALL SELECT 5, 'pair UNIQUE constraint is gone',
         NOT EXISTS (
           SELECT 1 FROM pg_constraint
           WHERE conrelid = 'public.conversations'::regclass
             AND conname = 'conversations_pair'
         )
  UNION ALL SELECT 6, 'general pair unique index exists',
         EXISTS (
           SELECT 1 FROM pg_indexes
           WHERE schemaname = 'public'
             AND indexname = 'conversations_pair_general_uidx'
         )
  UNION ALL SELECT 7, 'product pair unique index exists',
         EXISTS (
           SELECT 1 FROM pg_indexes
           WHERE schemaname = 'public'
             AND indexname = 'conversations_pair_product_uidx'
         )
  UNION ALL SELECT 8, 'mark_conversation_read exists',
         (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
          WHERE n.nspname = 'public' AND p.proname = 'mark_conversation_read') = 1
  UNION ALL SELECT 9, 'authenticated can EXECUTE mark_conversation_read',
         has_function_privilege(
           'authenticated',
           'public.mark_conversation_read(uuid)',
           'EXECUTE'
         )
  UNION ALL SELECT 10, 'authenticated cannot UPDATE conversations',
         NOT has_table_privilege('authenticated', 'public.conversations', 'UPDATE')
  UNION ALL SELECT 11, 'authenticated can INSERT messages',
         has_table_privilege('authenticated', 'public.messages', 'INSERT')
  UNION ALL SELECT 12, 'authenticated cannot UPDATE messages',
         NOT has_table_privilege('authenticated', 'public.messages', 'UPDATE')
  UNION ALL SELECT 13, 'sender overwrite trigger exists',
         EXISTS (
           SELECT 1 FROM pg_trigger
           WHERE tgname = 'trg_messages_force_sender' AND NOT tgisinternal
         )
  UNION ALL SELECT 14, 'conversation preview trigger exists',
         EXISTS (
           SELECT 1 FROM pg_trigger
           WHERE tgname = 'trg_messages_touch_conversation' AND NOT tgisinternal
         )
  UNION ALL SELECT 15, 'conversations and messages are in supabase_realtime',
         (SELECT count(*) FROM pg_publication_tables
          WHERE pubname = 'supabase_realtime'
            AND tablename IN ('conversations', 'messages')) = 2
  UNION ALL SELECT 16, 'message-attachments bucket is private',
         EXISTS (
           SELECT 1 FROM storage.buckets
           WHERE id = 'message-attachments' AND public IS FALSE
         )
  UNION ALL SELECT 17, 'message attachment select policy exists',
         EXISTS (
           SELECT 1 FROM pg_policies
           WHERE schemaname = 'storage' AND tablename = 'objects'
             AND policyname = 'message_attachments_select_participant'
         )
)
SELECT seq,
       CASE WHEN ok THEN 'PASS' ELSE 'FAIL' END AS status,
       check_name
FROM checks
ORDER BY seq;
