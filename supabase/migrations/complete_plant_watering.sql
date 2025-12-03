-- Complete Plant Watering Setup Migration
-- Run this entire file in Supabase SQL Editor

-- Step 1: Add last_plant_watered_at column to pet_status table
ALTER TABLE public.pet_status
ADD COLUMN IF NOT EXISTS last_plant_watered_at timestamptz;

-- Step 2: Update record_pet_action function with plant support
CREATE OR REPLACE FUNCTION public.record_pet_action(action_type text)
RETURNS public.pet_status
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    updated_status public.pet_status%rowtype;
    now_utc timestamptz := timezone('utc', now());
    water_cooldown interval := interval '1 hour';
    play_cooldown interval := interval '15 minutes';
    today date := timezone('utc', now())::date;
    hearts_reward integer := 5;
    new_hearts integer;
    new_streak integer;
    last_active date;
    partner_user_id uuid;
    v_couple_key text;
    couple_row public.couple_progress%rowtype;
    my_pairing_code text;
    partner_pairing_code text;
    source_hearts integer;
    source_streak integer;
    source_last_active date;
    partner_status public.pet_status%rowtype;
    base_status public.pet_status%rowtype;
    new_hydration integer;
    new_play integer;
    actor_name text;
    pet_label text;
BEGIN
    SELECT partner_id, pairing_code INTO partner_user_id, my_pairing_code FROM public.users WHERE id = auth.uid();
    IF partner_user_id = auth.uid() THEN
        partner_user_id := null;
    END IF;

    IF partner_user_id IS NOT NULL THEN
        SELECT pairing_code INTO partner_pairing_code FROM public.users WHERE id = partner_user_id;
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

    INSERT INTO public.couple_progress (couple_key)
    VALUES (v_couple_key)
    ON CONFLICT (couple_key) DO NOTHING;

    SELECT * INTO couple_row FROM public.couple_progress WHERE couple_key = v_couple_key;

    IF coalesce(couple_row.hearts, 0) = 0 AND coalesce(couple_row.streak_count, 0) = 0 THEN
        SELECT coalesce(max(hearts), 0),
               coalesce(max(streak_count), 0),
               max(last_active_date)
        INTO source_hearts, source_streak, source_last_active
        FROM public.couple_progress
        WHERE couple_key IN (
            my_pairing_code,
            partner_pairing_code
        );

        UPDATE public.couple_progress
        SET hearts = greatest(couple_row.hearts, source_hearts),
            streak_count = greatest(couple_row.streak_count, source_streak),
            last_active_date = coalesce(source_last_active, couple_row.last_active_date)
        WHERE couple_key = v_couple_key;

        SELECT * INTO couple_row FROM public.couple_progress WHERE couple_key = v_couple_key;
    END IF;

    -- Fetch pet status for both partners and pick the freshest
    SELECT * INTO updated_status FROM public.pet_status WHERE user_id = auth.uid();
    IF partner_user_id IS NOT NULL THEN
        SELECT * INTO partner_status FROM public.pet_status WHERE user_id = partner_user_id;
    END IF;

    base_status := updated_status;
    IF partner_status.updated_at IS NOT NULL AND (updated_status.updated_at IS NULL OR partner_status.updated_at > updated_status.updated_at) THEN
        base_status := partner_status;
    END IF;
    IF base_status.user_id IS NULL THEN
        base_status := updated_status;
    END IF;
    pet_label := coalesce(base_status.pet_name, 'Bubba');
    SELECT display_name INTO actor_name FROM public.users WHERE id = auth.uid();

    last_active := couple_row.last_active_date;
    IF last_active = today THEN
        new_streak := coalesce(couple_row.streak_count, 0);
    ELSIF last_active = (today - 1) THEN
        new_streak := coalesce(couple_row.streak_count, 0) + 1;
    ELSE
        new_streak := 1;
    END IF;
    new_hearts := coalesce(couple_row.hearts, 0) + hearts_reward;

    UPDATE public.couple_progress
    SET hearts = new_hearts,
        streak_count = new_streak,
        last_active_date = today
    WHERE couple_key = v_couple_key
    RETURNING * INTO couple_row;

    updated_status.hearts := couple_row.hearts;
    updated_status.streak_count := couple_row.streak_count;
    updated_status.last_active_date := couple_row.last_active_date;

    IF action_type = 'water' THEN
        IF base_status.last_watered_at IS NOT NULL
            AND now_utc - base_status.last_watered_at < water_cooldown THEN
            RAISE EXCEPTION 'pet_action_cooldown'
                USING detail = 'water';
        END IF;

        new_hydration := least(100, coalesce(base_status.hydration_level, 0) + 20);
        new_play := greatest(0, coalesce(base_status.playfulness_level, 0) - 4);

        UPDATE public.pet_status
        SET hydration_level = new_hydration,
            playfulness_level = new_play,
            last_watered_at = now_utc,
            mood = public.compute_pet_mood(new_hydration, new_play),
            updated_at = now_utc
        WHERE user_id = auth.uid()
        RETURNING * INTO updated_status;

        updated_status.hearts := couple_row.hearts;
        updated_status.streak_count := couple_row.streak_count;
        updated_status.last_active_date := couple_row.last_active_date;

        IF partner_user_id IS NOT NULL THEN
            INSERT INTO public.pet_status (user_id) VALUES (partner_user_id)
            ON CONFLICT (user_id) DO NOTHING;

            UPDATE public.pet_status
            SET hydration_level = new_hydration,
                playfulness_level = new_play,
                last_watered_at = now_utc,
                mood = public.compute_pet_mood(new_hydration, new_play),
                pet_name = base_status.pet_name,
                updated_at = now_utc
            WHERE user_id = partner_user_id;
        END IF;
    ELSIF action_type = 'play' THEN
        IF base_status.last_played_at IS NOT NULL
            AND now_utc - base_status.last_played_at < play_cooldown THEN
            RAISE EXCEPTION 'pet_action_cooldown'
                USING detail = 'play';
        END IF;

        new_play := least(100, coalesce(base_status.playfulness_level, 0) + 22);
        new_hydration := greatest(0, coalesce(base_status.hydration_level, 0) - 6);

        UPDATE public.pet_status
        SET playfulness_level = new_play,
            hydration_level = new_hydration,
            last_played_at = now_utc,
            mood = public.compute_pet_mood(new_hydration, new_play),
            updated_at = now_utc
        WHERE user_id = auth.uid()
        RETURNING * INTO updated_status;

        updated_status.hearts := couple_row.hearts;
        updated_status.streak_count := couple_row.streak_count;
        updated_status.last_active_date := couple_row.last_active_date;

        IF partner_user_id IS NOT NULL THEN
            INSERT INTO public.pet_status (user_id) VALUES (partner_user_id)
            ON CONFLICT (user_id) DO NOTHING;

            UPDATE public.pet_status
            SET playfulness_level = new_play,
                hydration_level = new_hydration,
                last_played_at = now_utc,
                mood = public.compute_pet_mood(new_hydration, new_play),
                pet_name = base_status.pet_name,
                updated_at = now_utc
            WHERE user_id = partner_user_id;
        END IF;
    ELSIF action_type = 'plant' THEN
        -- Plant watering: 15 minute cooldown, no stat changes, just awards hearts (already done above)
        IF base_status.last_plant_watered_at IS NOT NULL
            AND now_utc - base_status.last_plant_watered_at < play_cooldown THEN
            RAISE EXCEPTION 'pet_action_cooldown'
                USING detail = 'plant';
        END IF;

        -- Update timestamp to mark activity
        UPDATE public.pet_status
        SET last_plant_watered_at = now_utc,
            updated_at = now_utc
        WHERE user_id = auth.uid()
        RETURNING * INTO updated_status;

        updated_status.hearts := couple_row.hearts;
        updated_status.streak_count := couple_row.streak_count;
        updated_status.last_active_date := couple_row.last_active_date;

        IF partner_user_id IS NOT NULL THEN
            INSERT INTO public.pet_status (user_id) VALUES (partner_user_id)
            ON CONFLICT (user_id) DO NOTHING;

            UPDATE public.pet_status
            SET last_plant_watered_at = now_utc,
                updated_at = now_utc
            WHERE user_id = partner_user_id;
        END IF;
    ELSE
        RAISE EXCEPTION 'unknown_pet_action';
    END IF;

    IF v_couple_key IS NOT NULL THEN
        INSERT INTO public.couple_activity (couple_key, actor_id, actor_name, action_type, pet_name)
        VALUES (v_couple_key, auth.uid(), actor_name, action_type, pet_label);
    END IF;

    RETURN updated_status;
END;
$$;

GRANT EXECUTE ON FUNCTION public.record_pet_action(text) TO authenticated;
