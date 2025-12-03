-- Migration: Add content field to doodles table for base64 storage
-- Run this on your Supabase database to enable the new doodle functionality

-- 1. Make storage_path nullable and add content column
ALTER TABLE public.doodles
  ALTER COLUMN storage_path DROP NOT NULL;

ALTER TABLE public.doodles
  ADD COLUMN IF NOT EXISTS content text;

-- 2. Update the save_doodle function to accept content parameter
CREATE OR REPLACE FUNCTION public.save_doodle(
    p_content text default null,
    p_storage_path text default null
)
RETURNS public.doodles
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    partner_user_id uuid;
    my_pairing_code text;
    partner_pairing_code text;
    v_couple_key text;
    sender_display_name text;
    new_doodle public.doodles%rowtype;
BEGIN
    SELECT partner_id, pairing_code, display_name
    INTO partner_user_id, my_pairing_code, sender_display_name
    FROM public.users WHERE id = auth.uid();

    IF partner_user_id IS NULL THEN
        RAISE EXCEPTION 'no_partner';
    END IF;

    IF partner_user_id = auth.uid() THEN
        RAISE EXCEPTION 'cannot_send_to_self';
    END IF;

    SELECT pairing_code INTO partner_pairing_code
    FROM public.users WHERE id = partner_user_id;

    IF partner_pairing_code IS NULL THEN
        v_couple_key := my_pairing_code;
    ELSIF my_pairing_code IS NULL THEN
        v_couple_key := partner_pairing_code;
    ELSE
        v_couple_key := CASE
            WHEN my_pairing_code <= partner_pairing_code THEN my_pairing_code
            ELSE partner_pairing_code
        END;
    END IF;

    INSERT INTO public.doodles (couple_key, sender_id, sender_name, storage_path, content)
    VALUES (v_couple_key, auth.uid(), COALESCE(sender_display_name, 'Someone'), p_storage_path, p_content)
    RETURNING * INTO new_doodle;

    -- Send push notification to partner
    IF partner_user_id IS NOT NULL THEN
        PERFORM public.send_test_push(
            partner_user_id,
            '🎨 ' || COALESCE(sender_display_name, 'Someone') || ' sent you a doodle',
            'Check it out in the gallery!',
            jsonb_build_object('type', 'doodle', 'doodle_id', new_doodle.id)
        );
    END IF;

    RETURN new_doodle;
END;
$$;

-- 3. Update the grant for the new function signature
GRANT EXECUTE ON FUNCTION public.save_doodle(text, text) TO authenticated;

-- Verify the changes
SELECT column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_name = 'doodles'
ORDER BY ordinal_position;
