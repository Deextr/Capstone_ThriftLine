-- Minimal direct messages so Looking For share / "I Have This" can persist.
-- Phase 4 can add realtime, read receipts, and image attachments on these tables.

CREATE TABLE IF NOT EXISTS public.conversations (
  conversation_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  participant_a uuid NOT NULL REFERENCES public.users (user_id) ON DELETE CASCADE,
  participant_b uuid NOT NULL REFERENCES public.users (user_id) ON DELETE CASCADE,
  last_message text,
  last_message_at timestamptz NOT NULL DEFAULT now(),
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT conversations_no_self CHECK (participant_a <> participant_b),
  CONSTRAINT conversations_ordered CHECK (participant_a < participant_b),
  CONSTRAINT conversations_pair UNIQUE (participant_a, participant_b)
);

CREATE INDEX IF NOT EXISTS conversations_participant_a_idx
  ON public.conversations (participant_a, last_message_at DESC);
CREATE INDEX IF NOT EXISTS conversations_participant_b_idx
  ON public.conversations (participant_b, last_message_at DESC);

CREATE TABLE IF NOT EXISTS public.messages (
  message_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  conversation_id uuid NOT NULL REFERENCES public.conversations (conversation_id) ON DELETE CASCADE,
  sender_id uuid NOT NULL REFERENCES public.users (user_id) ON DELETE CASCADE,
  content text NOT NULL,
  message_type text NOT NULL DEFAULT 'text',
  looking_for_post_id uuid REFERENCES public.looking_for_posts (post_id) ON DELETE SET NULL,
  offer_amount numeric,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT messages_type_check CHECK (
    message_type IN ('text', 'looking_for', 'offer', 'image')
  )
);

CREATE INDEX IF NOT EXISTS messages_conversation_created_idx
  ON public.messages (conversation_id, created_at);

ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversations FORCE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS conversations_select_participant ON public.conversations;
CREATE POLICY conversations_select_participant ON public.conversations
  FOR SELECT TO authenticated
  USING (auth.uid() = participant_a OR auth.uid() = participant_b);

DROP POLICY IF EXISTS conversations_insert_participant ON public.conversations;
CREATE POLICY conversations_insert_participant ON public.conversations
  FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = participant_a OR auth.uid() = participant_b);

DROP POLICY IF EXISTS conversations_update_participant ON public.conversations;
CREATE POLICY conversations_update_participant ON public.conversations
  FOR UPDATE TO authenticated
  USING (auth.uid() = participant_a OR auth.uid() = participant_b)
  WITH CHECK (auth.uid() = participant_a OR auth.uid() = participant_b);

DROP POLICY IF EXISTS messages_select_participant ON public.messages;
CREATE POLICY messages_select_participant ON public.messages
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM public.conversations c
      WHERE c.conversation_id = messages.conversation_id
        AND (c.participant_a = auth.uid() OR c.participant_b = auth.uid())
    )
  );

DROP POLICY IF EXISTS messages_insert_sender ON public.messages;
CREATE POLICY messages_insert_sender ON public.messages
  FOR INSERT TO authenticated
  WITH CHECK (
    auth.uid() = sender_id
    AND EXISTS (
      SELECT 1
      FROM public.conversations c
      WHERE c.conversation_id = messages.conversation_id
        AND (c.participant_a = auth.uid() OR c.participant_b = auth.uid())
    )
  );

GRANT SELECT, INSERT, UPDATE ON public.conversations TO authenticated;
GRANT SELECT, INSERT ON public.messages TO authenticated;

-- Owner-only edits already exist; keep user_id from being reassigned on UPDATE.
DROP POLICY IF EXISTS looking_for_posts_update_own_admin ON public.looking_for_posts;
CREATE POLICY looking_for_posts_update_own_admin ON public.looking_for_posts
  FOR UPDATE
  USING (auth.uid() = user_id OR public.is_admin())
  WITH CHECK (auth.uid() = user_id OR public.is_admin());
