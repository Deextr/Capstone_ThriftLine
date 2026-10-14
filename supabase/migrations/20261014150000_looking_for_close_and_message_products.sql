-- Buyer manual Looking For closure + product attachments in chat messages.

-- ---------------------------------------------------------------------------
-- 1. Close / mark fulfilled (owner-only, RPC — clients cannot UPDATE posts)
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.close_looking_for_request(p_post_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_post public.looking_for_posts%ROWTYPE;
BEGIN
  IF v_uid IS NULL THEN
    RETURN public.looking_for_fail('Please sign in to close this request.');
  END IF;

  SELECT * INTO v_post
  FROM public.looking_for_posts
  WHERE post_id = p_post_id;

  IF NOT FOUND OR v_post.user_id <> v_uid THEN
    RETURN public.looking_for_fail('That request could not be closed.');
  END IF;

  IF v_post.moderation_removed_at IS NOT NULL THEN
    RETURN public.looking_for_fail(
      'This request was removed by ThriftLine and cannot be updated.'
    );
  END IF;

  IF v_post.owner_deleted_at IS NOT NULL THEN
    RETURN public.looking_for_fail('This request is no longer available.');
  END IF;

  IF v_post.status IN (
    'closed'::public.looking_for_status_enum,
    'fulfilled'::public.looking_for_status_enum
  ) THEN
    RETURN public.looking_for_fail('This request is already closed.');
  END IF;

  IF v_post.expires_at <= now() THEN
    RETURN public.looking_for_fail(
      'This request has expired. Repost it from Inactive Requests if you still need it.'
    );
  END IF;

  PERFORM set_config('thriftline.lf_write', '1', true);
  UPDATE public.looking_for_posts
  SET status = 'fulfilled'::public.looking_for_status_enum
  WHERE post_id = p_post_id
    AND user_id = v_uid;

  RETURN jsonb_build_object('success', true, 'post_id', p_post_id);
END;
$$;

REVOKE ALL ON FUNCTION public.close_looking_for_request(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.close_looking_for_request(uuid)
  TO authenticated, postgres, service_role;

-- ---------------------------------------------------------------------------
-- 2. Product reference on messages
-- ---------------------------------------------------------------------------

ALTER TABLE public.messages
  ADD COLUMN IF NOT EXISTS product_id uuid;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'messages_product_id_fkey'
      AND conrelid = 'public.messages'::regclass
  ) THEN
    ALTER TABLE public.messages
      ADD CONSTRAINT messages_product_id_fkey
      FOREIGN KEY (product_id)
      REFERENCES public.products (product_id)
      ON DELETE SET NULL;
  END IF;
END $$;

ALTER TABLE public.messages
  DROP CONSTRAINT IF EXISTS messages_type_check;

ALTER TABLE public.messages
  ADD CONSTRAINT messages_type_check CHECK (
    message_type = ANY (
      ARRAY[
        'text'::text,
        'looking_for'::text,
        'offer'::text,
        'image'::text,
        'product'::text
      ]
    )
  );

CREATE OR REPLACE FUNCTION public.messages_validate_product_share()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NEW.message_type = 'product' THEN
    IF NEW.product_id IS NULL THEN
      RAISE EXCEPTION 'Product share requires a product.'
        USING ERRCODE = '23514';
    END IF;
    IF auth.uid() IS NULL THEN
      RAISE EXCEPTION 'Not authenticated'
        USING ERRCODE = '42501';
    END IF;
    IF NOT EXISTS (
      SELECT 1
      FROM public.products p
      WHERE p.product_id = NEW.product_id
        AND p.seller_id = auth.uid()
        AND p.status = 'active'::public.product_status_enum
    ) THEN
      RAISE EXCEPTION 'You can only share active items from your shop.'
        USING ERRCODE = '42501';
    END IF;
  ELSIF NEW.product_id IS NOT NULL THEN
    NEW.product_id := NULL;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_messages_validate_product_share ON public.messages;
CREATE TRIGGER trg_messages_validate_product_share
  BEFORE INSERT ON public.messages
  FOR EACH ROW
  EXECUTE FUNCTION public.messages_validate_product_share();

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
    WHEN NEW.message_type = 'product' THEN COALESCE(NULLIF(btrim(NEW.content), ''), 'Shared a product')
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
