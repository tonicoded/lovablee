-- Migration: Add cooldown columns and update functions for love notes and doodles

-- Step 1: Add cooldown columns for love notes and doodles
ALTER TABLE public.pet_status
ADD COLUMN IF NOT EXISTS last_note_sent_at timestamptz,
ADD COLUMN IF NOT EXISTS last_doodle_created_at timestamptz;

-- Step 2: Update send_love_note function to add hearts and cooldown
CREATE OR REPLACE FUNCTION public.send_love_note(p_message text)
RETURNS public.love_notes
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
    new_note public.love_notes%rowtype;
    v_last_note_sent_at timestamptz;
    v_cooldown_hours int := 1;
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

    -- Check cooldown
    SELECT last_note_sent_at INTO v_last_note_sent_at
    FROM public.pet_status WHERE user_id = auth.uid();

    IF v_last_note_sent_at IS NOT NULL AND
       v_last_note_sent_at > (now() - (v_cooldown_hours || ' hours')::interval) THEN
        RAISE EXCEPTION 'cooldown_active';
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

    INSERT INTO public.love_notes (couple_key, sender_id, sender_name, message)
    VALUES (v_couple_key, auth.uid(), COALESCE(sender_display_name, 'Someone'), p_message)
    RETURNING * INTO new_note;

    -- Award +10 hearts to couple (SHARED hearts pool)
    UPDATE public.couple_progress
    SET hearts = hearts + 10
    WHERE couple_key = v_couple_key;

    -- Update cooldown timestamp
    UPDATE public.pet_status
    SET last_note_sent_at = now()
    WHERE user_id = auth.uid();

    -- Send push notification to partner
    IF partner_user_id IS NOT NULL THEN
        PERFORM public.send_test_push(
            partner_user_id,
            '💌 ' || COALESCE(sender_display_name, 'Someone') || ' sent you a love note',
            LEFT(p_message, 100),
            jsonb_build_object('type', 'love_note', 'note_id', new_note.id)
        );
    END IF;

    RETURN new_note;
END;
$$;

-- Step 3: Update save_doodle function to add hearts and cooldown
CREATE OR REPLACE FUNCTION public.save_doodle(
    p_content text DEFAULT NULL,
    p_storage_path text DEFAULT NULL
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
    v_last_doodle_created_at timestamptz;
    v_cooldown_minutes int := 15;
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

    -- Check cooldown
    SELECT last_doodle_created_at INTO v_last_doodle_created_at
    FROM public.pet_status WHERE user_id = auth.uid();

    IF v_last_doodle_created_at IS NOT NULL AND
       v_last_doodle_created_at > (now() - (v_cooldown_minutes || ' minutes')::interval) THEN
        RAISE EXCEPTION 'cooldown_active';
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

    -- Award +10 hearts to couple (SHARED hearts pool)
    UPDATE public.couple_progress
    SET hearts = hearts + 10
    WHERE couple_key = v_couple_key;

    -- Update cooldown timestamp
    UPDATE public.pet_status
    SET last_doodle_created_at = now()
    WHERE user_id = auth.uid();

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
