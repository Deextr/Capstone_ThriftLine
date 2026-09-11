-- Phase 4 — Messaging (corrective expansion of Phase 2 conversations).
--
-- Does NOT rewrite 20260909020000_conversations.sql. That file stays in history.
-- This file adds:
--   * product-linked threads (nullable product_id + partial unique indexes)
--   * last_read_at_a / last_read_at_b (authoritative unread state)
--   * sender_id overwrite from auth.uid()
--   * last_message maintained by trigger (clients cannot UPDATE conversations)
--   * mark_conversation_read(uuid)
--   * attachment_path on messages
--   * private message-attachments bucket
--   * Realtime publication for conversations and messages
--
-- Looking For share and I Have This keep product_id NULL (one general thread
-- per pair). Offers stay message_type = offer. No orders. No payments.
-- Idempotent. Safe to re-run.

-- ===========================================================================
-- 1. Schema
-- ===========================================================================

ALTER TABLE public.conversations
  ADD COLUMN IF NOT EXISTS product_id uuid,
  ADD COLUMN IF NOT EXISTS last_read_at_a timestamptz,
  ADD COLUMN IF NOT EXISTS last_read_at_b timestamptz;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'conversations_product_id_fkey'
  ) THEN
    ALTER TABLE public.conversations
      ADD CONSTRAINT conversations_product_id_fkey
      FOREIGN KEY (product_id)
      REFERENCES public.products (product_id)
      ON DELETE SET NULL;
  END IF;
END $$;

ALTER TABLE public.messages
  ADD COLUMN IF NOT EXISTS attachment_path text;

-- Existing threads were pair-unique with no product. Keep them as the
-- general (product_id IS NULL) thread and do not mark them unread.
UPDATE public.conversations
SET last_read_at_a = COALESCE(last_read_at_a, last_message_at, created_at, now()),
    last_read_at_b = COALESCE(last_read_at_b, last_message_at, created_at, now());

ALTER TABLE public.conversations
  ALTER COLUMN last_read_at_a SET DEFAULT now(),
  ALTER COLUMN last_read_at_b SET DEFAULT now();

ALTER TABLE public.conversations
  DROP CONSTRAINT IF EXISTS conversations_pair;

CREATE UNIQUE INDEX IF NOT EXISTS conversations_pair_general_uidx
  ON public.conversations (participant_a, participant_b)
  WHERE product_id IS NULL;

CREATE UNIQUE INDEX IF NOT EXISTS conversations_pair_product_uidx
  ON public.conversations (participant_a, participant_b, product_id)
  WHERE product_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS conversations_product_id_idx
  ON public.conversations (product_id)
  WHERE product_id IS NOT NULL;

-- ===========================================================================
-- 2. Sender is always the authenticated user
-- ===========================================================================

CREATE OR REPLACE FUNCTION public.messages_force_sender()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  NEW.sender_id := auth.uid();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_messages_force_sender ON public.messages;
CREATE TRIGGER trg_messages_force_sender
  BEFORE INSERT ON public.messages
  FOR EACH ROW
  EXECUTE FUNCTION public.messages_force_sender();

-- ===========================================================================
-- 3. Conversation preview + sender last-read (server-owned)
-- ===========================================================================

CREATE OR REPLACE FUNCTION public.messages_touch_conversation()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  preview text;
BEGIN
  preview := CASE
    WHEN NEW.message_type = 'image' THEN COALESCE(NULLIF(btrim(NEW.content), ''), 'Photo')
    WHEN NEW.message_type = 'offer' THEN COALESCE(NULLIF(btrim(NEW.content), ''), 'Offer')
    ELSE left(NEW.content, 200)
  END;

  UPDATE public.conversations
  SET last_message = preview,
      last_message_at = NEW.created_at,
      last_read_at_a = CASE
        WHEN participant_a = NEW.sender_id THEN NEW.created_at
        ELSE last_read_at_a
      END,
      last_read_at_b = CASE
        WHEN participant_b = NEW.sender_id THEN NEW.created_at
        ELSE last_read_at_b
      END
  WHERE conversation_id = NEW.conversation_id;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_messages_touch_conversation ON public.messages;
CREATE TRIGGER trg_messages_touch_conversation
  AFTER INSERT ON public.messages
  FOR EACH ROW
  EXECUTE FUNCTION public.messages_touch_conversation();

-- Participants / product_id must not be rewritten after insert.
CREATE OR REPLACE FUNCTION public.conversations_lock_identity()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.conversation_id := OLD.conversation_id;
  NEW.participant_a := OLD.participant_a;
  NEW.participant_b := OLD.participant_b;
  NEW.product_id := OLD.product_id;
  NEW.created_at := OLD.created_at;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_conversations_lock_identity ON public.conversations;
CREATE TRIGGER trg_conversations_lock_identity
  BEFORE UPDATE ON public.conversations
  FOR EACH ROW
  EXECUTE FUNCTION public.conversations_lock_identity();

-- ===========================================================================
-- 4. Read receipts — only the caller's last_read column
-- ===========================================================================

CREATE OR REPLACE FUNCTION public.mark_conversation_read(p_conversation_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  UPDATE public.conversations
  SET last_read_at_a = CASE
        WHEN participant_a = auth.uid() THEN now()
        ELSE last_read_at_a
      END,
      last_read_at_b = CASE
        WHEN participant_b = auth.uid() THEN now()
        ELSE last_read_at_b
      END
  WHERE conversation_id = p_conversation_id
    AND (participant_a = auth.uid() OR participant_b = auth.uid());
END;
$$;

REVOKE ALL ON FUNCTION public.mark_conversation_read(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.mark_conversation_read(uuid)
  TO authenticated, postgres, service_role;

-- Clients must not UPDATE conversations (last_message / last_read of the
-- other party). Triggers and mark_conversation_read run as DEFINER.
REVOKE UPDATE ON TABLE public.conversations FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT ON TABLE public.conversations TO authenticated;
GRANT ALL ON TABLE public.conversations TO postgres, service_role;

-- Keep the row policy so DEFINER updates with a user JWT still pass FORCE RLS.
DROP POLICY IF EXISTS conversations_update_participant ON public.conversations;
CREATE POLICY conversations_update_participant ON public.conversations
  FOR UPDATE
  USING (auth.uid() = participant_a OR auth.uid() = participant_b)
  WITH CHECK (auth.uid() = participant_a OR auth.uid() = participant_b);

-- Hosted projects often grant ALL on new public tables to authenticated.
-- Phase 2 only added SELECT/INSERT; it did not revoke UPDATE/DELETE.
REVOKE ALL ON TABLE public.messages FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT ON TABLE public.messages TO authenticated;
GRANT ALL ON TABLE public.messages TO postgres, service_role;

-- ===========================================================================
-- 5. Private message attachments
-- ===========================================================================

CREATE OR REPLACE FUNCTION public.message_attachment_conversation_id(object_name text)
RETURNS uuid
LANGUAGE plpgsql
IMMUTABLE
PARALLEL SAFE
AS $$
BEGIN
  IF object_name IS NULL OR btrim(object_name) = '' THEN
    RETURN NULL;
  END IF;
  RETURN split_part(object_name, '/', 1)::uuid;
EXCEPTION
  WHEN invalid_text_representation THEN
    RETURN NULL;
END;
$$;

REVOKE ALL ON FUNCTION public.message_attachment_conversation_id(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.message_attachment_conversation_id(text)
  TO authenticated, anon, postgres, service_role;

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'message-attachments',
  'message-attachments',
  false,
  5242880,
  ARRAY['image/jpeg', 'image/jpg', 'image/png', 'image/webp']
)
ON CONFLICT (id) DO UPDATE
SET public = false,
    file_size_limit = EXCLUDED.file_size_limit,
    allowed_mime_types = EXCLUDED.allowed_mime_types;

DROP POLICY IF EXISTS message_attachments_insert_participant ON storage.objects;
CREATE POLICY message_attachments_insert_participant ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'message-attachments'
    AND split_part(name, '/', 2) = auth.uid()::text
    AND EXISTS (
      SELECT 1
      FROM public.conversations c
      WHERE c.conversation_id = public.message_attachment_conversation_id(name)
        AND (c.participant_a = auth.uid() OR c.participant_b = auth.uid())
    )
  );

DROP POLICY IF EXISTS message_attachments_select_participant ON storage.objects;
CREATE POLICY message_attachments_select_participant ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id = 'message-attachments'
    AND EXISTS (
      SELECT 1
      FROM public.conversations c
      WHERE c.conversation_id = public.message_attachment_conversation_id(name)
        AND (c.participant_a = auth.uid() OR c.participant_b = auth.uid())
    )
  );

DROP POLICY IF EXISTS message_attachments_delete_own ON storage.objects;
CREATE POLICY message_attachments_delete_own ON storage.objects
  FOR DELETE TO authenticated
  USING (
    bucket_id = 'message-attachments'
    AND split_part(name, '/', 2) = auth.uid()::text
    AND EXISTS (
      SELECT 1
      FROM public.conversations c
      WHERE c.conversation_id = public.message_attachment_conversation_id(name)
        AND (c.participant_a = auth.uid() OR c.participant_b = auth.uid())
    )
  );

DROP POLICY IF EXISTS message_attachments_update_own ON storage.objects;
CREATE POLICY message_attachments_update_own ON storage.objects
  FOR UPDATE TO authenticated
  USING (
    bucket_id = 'message-attachments'
    AND split_part(name, '/', 2) = auth.uid()::text
    AND EXISTS (
      SELECT 1
      FROM public.conversations c
      WHERE c.conversation_id = public.message_attachment_conversation_id(name)
        AND (c.participant_a = auth.uid() OR c.participant_b = auth.uid())
    )
  )
  WITH CHECK (
    bucket_id = 'message-attachments'
    AND split_part(name, '/', 2) = auth.uid()::text
    AND EXISTS (
      SELECT 1
      FROM public.conversations c
      WHERE c.conversation_id = public.message_attachment_conversation_id(name)
        AND (c.participant_a = auth.uid() OR c.participant_b = auth.uid())
    )
  );

-- ===========================================================================
-- 6. Realtime — RLS still limits which rows a client can receive
-- ===========================================================================

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'conversations'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.conversations;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'messages'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.messages;
  END IF;
EXCEPTION
  WHEN OTHERS THEN
    NULL;
END;
$$;
