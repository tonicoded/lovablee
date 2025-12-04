-- Patch: grants and together_since upsert for anniversaries & gifts
-- Run this entire file in the Supabase SQL editor

-- Ensure anniversary RPCs are callable
GRANT EXECUTE ON FUNCTION public.set_together_since(timestamptz) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.add_custom_anniversary(text, timestamptz) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.load_anniversaries() TO authenticated, service_role;

-- Allow API access to anniversary table when RLS passes
GRANT SELECT, INSERT, DELETE ON public.custom_anniversaries TO authenticated;

-- Harden set_together_since: create the couple_progress row if missing
CREATE OR REPLACE FUNCTION public.set_together_since(p_date timestamptz)
RETURNS public.couple_progress
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_couple_key text;
    my_pairing_code text;
    partner_user_id uuid;
    partner_pairing_code text;
    updated_progress public.couple_progress%rowtype;
BEGIN
    SELECT pairing_code, partner_id
    INTO my_pairing_code, partner_user_id
    FROM public.users WHERE id = auth.uid();

    IF partner_user_id IS NULL THEN
        RAISE EXCEPTION 'no_partner';
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

    IF v_couple_key IS NULL THEN
        RAISE EXCEPTION 'no_couple_key';
    END IF;

    INSERT INTO public.couple_progress (couple_key, together_since)
    VALUES (v_couple_key, p_date)
    ON CONFLICT (couple_key) DO UPDATE
    SET together_since = EXCLUDED.together_since
    RETURNING * INTO updated_progress;

    RETURN updated_progress;
END;
$$;

-- Ensure gift RPCs are callable
GRANT EXECUTE ON FUNCTION public.send_gift(text, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.mark_gift_opened(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.load_couple_gifts() TO authenticated, service_role;

-- Allow API access to gifts table when RLS passes
GRANT SELECT, INSERT, UPDATE ON public.gifts TO authenticated;
