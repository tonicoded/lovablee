-- Migration: Add anniversaries feature
-- Run this entire file in Supabase SQL Editor

-- Step 1: Add together_since column to couple_progress table
ALTER TABLE public.couple_progress
ADD COLUMN IF NOT EXISTS together_since timestamptz;

-- Step 2: Create custom_anniversaries table
CREATE TABLE IF NOT EXISTS public.custom_anniversaries (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    couple_key text NOT NULL,
    name text NOT NULL,
    anniversary_date timestamptz NOT NULL,
    created_at timestamptz DEFAULT timezone('utc', now()) NOT NULL
);

-- Step 3: Add RLS policies for custom_anniversaries table
ALTER TABLE public.custom_anniversaries ENABLE ROW LEVEL SECURITY;

-- Drop existing policies if they exist (for idempotency)
DROP POLICY IF EXISTS "Users can view their couple's anniversaries" ON public.custom_anniversaries;
DROP POLICY IF EXISTS "Users can add anniversaries for their couple" ON public.custom_anniversaries;
DROP POLICY IF EXISTS "Users can delete their couple's anniversaries" ON public.custom_anniversaries;

-- Users can view anniversaries in their couple
CREATE POLICY "Users can view their couple's anniversaries"
    ON public.custom_anniversaries FOR SELECT
    USING (
        couple_key IN (
            SELECT CASE
                WHEN u1.pairing_code <= u2.pairing_code THEN u1.pairing_code
                ELSE u2.pairing_code
            END
            FROM public.users u1
            LEFT JOIN public.users u2 ON u1.partner_id = u2.id
            WHERE u1.id = auth.uid()
        )
    );

-- Users can insert anniversaries for their couple
CREATE POLICY "Users can add anniversaries for their couple"
    ON public.custom_anniversaries FOR INSERT
    WITH CHECK (
        couple_key IN (
            SELECT CASE
                WHEN u1.pairing_code <= u2.pairing_code THEN u1.pairing_code
                ELSE u2.pairing_code
            END
            FROM public.users u1
            LEFT JOIN public.users u2 ON u1.partner_id = u2.id
            WHERE u1.id = auth.uid()
        )
    );

-- Users can delete their couple's anniversaries
CREATE POLICY "Users can delete their couple's anniversaries"
    ON public.custom_anniversaries FOR DELETE
    USING (
        couple_key IN (
            SELECT CASE
                WHEN u1.pairing_code <= u2.pairing_code THEN u1.pairing_code
                ELSE u2.pairing_code
            END
            FROM public.users u1
            LEFT JOIN public.users u2 ON u1.partner_id = u2.id
            WHERE u1.id = auth.uid()
        )
    );

-- Step 4: Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_custom_anniversaries_couple_key ON public.custom_anniversaries(couple_key);
CREATE INDEX IF NOT EXISTS idx_custom_anniversaries_date ON public.custom_anniversaries(anniversary_date);

-- Step 5: Create function to set together_since date
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
    -- Get user's pairing code and partner
    SELECT pairing_code, partner_id
    INTO my_pairing_code, partner_user_id
    FROM public.users WHERE id = auth.uid();

    -- Check if user has a partner
    IF partner_user_id IS NULL THEN
        RAISE EXCEPTION 'no_partner';
    END IF;

    -- Get partner's pairing code
    SELECT pairing_code INTO partner_pairing_code
    FROM public.users WHERE id = partner_user_id;

    -- Calculate couple key
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

    -- Update together_since date
    UPDATE public.couple_progress
    SET together_since = p_date
    WHERE couple_key = v_couple_key
    RETURNING * INTO updated_progress;

    RETURN updated_progress;
END;
$$;

-- Step 6: Create function to add custom anniversary
CREATE OR REPLACE FUNCTION public.add_custom_anniversary(
    p_name text,
    p_date timestamptz
)
RETURNS public.custom_anniversaries
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_couple_key text;
    my_pairing_code text;
    partner_user_id uuid;
    partner_pairing_code text;
    new_anniversary public.custom_anniversaries%rowtype;
BEGIN
    -- Get user's pairing code and partner
    SELECT pairing_code, partner_id
    INTO my_pairing_code, partner_user_id
    FROM public.users WHERE id = auth.uid();

    -- Check if user has a partner
    IF partner_user_id IS NULL THEN
        RAISE EXCEPTION 'no_partner';
    END IF;

    -- Get partner's pairing code
    SELECT pairing_code INTO partner_pairing_code
    FROM public.users WHERE id = partner_user_id;

    -- Calculate couple key
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

    -- Insert new anniversary
    INSERT INTO public.custom_anniversaries (couple_key, name, anniversary_date)
    VALUES (v_couple_key, p_name, p_date)
    RETURNING * INTO new_anniversary;

    RETURN new_anniversary;
END;
$$;

-- Step 7: Create function to load anniversaries
CREATE OR REPLACE FUNCTION public.load_anniversaries()
RETURNS TABLE (
    together_since timestamptz,
    custom_anniversaries json
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_couple_key text;
    my_pairing_code text;
    partner_user_id uuid;
    partner_pairing_code text;
    v_together_since timestamptz;
    v_custom_anniversaries json;
BEGIN
    -- Get user's pairing code and partner
    SELECT pairing_code, partner_id
    INTO my_pairing_code, partner_user_id
    FROM public.users WHERE id = auth.uid();

    -- If no partner, return empty
    IF partner_user_id IS NULL THEN
        RETURN QUERY SELECT NULL::timestamptz, '[]'::json;
        RETURN;
    END IF;

    -- Get partner's pairing code
    SELECT pairing_code INTO partner_pairing_code
    FROM public.users WHERE id = partner_user_id;

    -- Calculate couple key
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

    -- Get together_since date
    SELECT cp.together_since INTO v_together_since
    FROM public.couple_progress cp
    WHERE cp.couple_key = v_couple_key;

    -- Get custom anniversaries as JSON
    SELECT COALESCE(json_agg(json_build_object(
        'id', ca.id,
        'name', ca.name,
        'date', ca.anniversary_date
    ) ORDER BY ca.anniversary_date DESC), '[]'::json)
    INTO v_custom_anniversaries
    FROM public.custom_anniversaries ca
    WHERE ca.couple_key = v_couple_key;

    RETURN QUERY SELECT v_together_since, v_custom_anniversaries;
END;
$$;
