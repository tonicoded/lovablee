-- Patch: keep love note / doodle cooldowns per-user in refresh_pet_status
-- Run this entire file in the Supabase SQL editor

CREATE OR REPLACE FUNCTION public.refresh_pet_status()
RETURNS public.pet_status
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    current_status public.pet_status%rowtype;
    partner_status public.pet_status%rowtype;
    base_status public.pet_status%rowtype;
    couple_row public.couple_progress%rowtype;
    now_utc timestamptz := timezone('utc', now());
    hours_since_update numeric;
    hydration_decay integer;
    play_decay integer;
    next_hydration integer;
    next_play integer;
    partner_user_id uuid;
    my_pairing_code text;
    partner_pairing_code text;
    v_couple_key text;
BEGIN
    current_status := public.ensure_pet_status();

    SELECT partner_id, pairing_code INTO partner_user_id, my_pairing_code FROM public.users WHERE id = auth.uid();
    IF partner_user_id = auth.uid() THEN
        partner_user_id := NULL;
    END IF;
    IF partner_user_id IS NOT NULL THEN
        SELECT pairing_code INTO partner_pairing_code FROM public.users WHERE id = partner_user_id;
        SELECT * INTO partner_status FROM public.pet_status WHERE user_id = partner_user_id;
    END IF;

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
    IF v_couple_key IS NOT NULL THEN
        INSERT INTO public.couple_progress (couple_key)
        VALUES (v_couple_key)
        ON CONFLICT (couple_key) DO NOTHING;

        SELECT * INTO couple_row FROM public.couple_progress WHERE couple_key = v_couple_key;
    END IF;

    -- Start from this user's row, copy only shared stats from partner if fresher
    base_status := current_status;
    IF partner_status.updated_at IS NOT NULL AND (current_status.updated_at IS NULL OR partner_status.updated_at > current_status.updated_at) THEN
        base_status.hydration_level := partner_status.hydration_level;
        base_status.playfulness_level := partner_status.playfulness_level;
        base_status.mood := partner_status.mood;
        base_status.pet_name := partner_status.pet_name;
        base_status.last_watered_at := partner_status.last_watered_at;
        base_status.last_played_at := partner_status.last_played_at;
        base_status.last_plant_watered_at := partner_status.last_plant_watered_at;
        base_status.last_fed_at := partner_status.last_fed_at;
        base_status.updated_at := partner_status.updated_at;
    END IF;

    IF couple_row.couple_key IS NOT NULL THEN
        base_status.hearts := COALESCE(couple_row.hearts, base_status.hearts);
        base_status.streak_count := COALESCE(couple_row.streak_count, base_status.streak_count);
        base_status.last_active_date := COALESCE(couple_row.last_active_date, base_status.last_active_date);
    END IF;

    IF base_status.user_id IS NULL THEN
        RETURN base_status;
    END IF;

    IF base_status.updated_at IS NULL THEN
        RETURN base_status;
    END IF;

    hours_since_update := GREATEST(
        0,
        EXTRACT(EPOCH FROM now_utc - base_status.updated_at) / 3600
    );

    IF hours_since_update <= 0 THEN
        RETURN base_status;
    END IF;

    hydration_decay := FLOOR(hours_since_update * 3);
    play_decay := FLOOR(hours_since_update * 4);

    IF hydration_decay <= 0 AND play_decay <= 0 THEN
        RETURN base_status;
    END IF;

    next_hydration := GREATEST(0, COALESCE(base_status.hydration_level, 0) - hydration_decay);
    next_play := GREATEST(0, COALESCE(base_status.playfulness_level, 0) - play_decay);

    UPDATE public.pet_status
    SET hydration_level = next_hydration,
        playfulness_level = next_play,
        mood = public.compute_pet_mood(next_hydration, next_play),
        updated_at = now_utc
    WHERE user_id = current_status.user_id
    RETURNING * INTO current_status;

    IF partner_user_id IS NOT NULL THEN
        INSERT INTO public.pet_status (user_id) VALUES (partner_user_id)
        ON CONFLICT (user_id) DO NOTHING;

        UPDATE public.pet_status
        SET hydration_level = next_hydration,
            playfulness_level = next_play,
            mood = public.compute_pet_mood(next_hydration, next_play),
            pet_name = base_status.pet_name,
            last_watered_at = base_status.last_watered_at,
            last_played_at = base_status.last_played_at,
            last_plant_watered_at = base_status.last_plant_watered_at,
            last_fed_at = base_status.last_fed_at,
            updated_at = now_utc
        WHERE user_id = partner_user_id;
    END IF;

    IF couple_row.couple_key IS NOT NULL THEN
        current_status.hearts := COALESCE(couple_row.hearts, 0);
        current_status.streak_count := COALESCE(couple_row.streak_count, 0);
        current_status.last_active_date := couple_row.last_active_date;
    END IF;

    RETURN current_status;
END;
$$;
