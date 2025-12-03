-- Migration: Add gifts feature
-- Run this entire file in Supabase SQL Editor

-- Step 1: Create gifts table
CREATE TABLE IF NOT EXISTS public.gifts (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    couple_key text NOT NULL,
    sender_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    sender_name text NOT NULL,
    recipient_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    recipient_name text NOT NULL,
    gift_type text NOT NULL,
    message text,
    is_opened boolean DEFAULT false,
    created_at timestamptz DEFAULT timezone('utc', now()) NOT NULL
);

-- Step 2: Add RLS policies for gifts table
ALTER TABLE public.gifts ENABLE ROW LEVEL SECURITY;

-- Drop existing policies if they exist (for idempotency)
DROP POLICY IF EXISTS "Users can view their couple's gifts" ON public.gifts;
DROP POLICY IF EXISTS "Users can send gifts to their partner" ON public.gifts;
DROP POLICY IF EXISTS "Users can mark received gifts as opened" ON public.gifts;

-- Users can view gifts in their couple
CREATE POLICY "Users can view their couple's gifts"
    ON public.gifts FOR SELECT
    USING (
        sender_id = auth.uid() OR recipient_id = auth.uid()
    );

-- Users can insert gifts for their partner
CREATE POLICY "Users can send gifts to their partner"
    ON public.gifts FOR INSERT
    WITH CHECK (sender_id = auth.uid());

-- Users can update gifts they received (to mark as opened)
CREATE POLICY "Users can mark received gifts as opened"
    ON public.gifts FOR UPDATE
    USING (recipient_id = auth.uid());

-- Step 3: Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_gifts_couple_key ON public.gifts(couple_key);
CREATE INDEX IF NOT EXISTS idx_gifts_sender_id ON public.gifts(sender_id);
CREATE INDEX IF NOT EXISTS idx_gifts_recipient_id ON public.gifts(recipient_id);
CREATE INDEX IF NOT EXISTS idx_gifts_created_at ON public.gifts(created_at DESC);

-- Step 4: Create send_gift function
CREATE OR REPLACE FUNCTION public.send_gift(
    p_gift_type text,
    p_message text DEFAULT NULL
)
RETURNS public.gifts
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
    partner_display_name text;
    new_gift public.gifts%rowtype;
    current_hearts int;
    gift_cost int;
BEGIN
    -- Get sender info
    SELECT partner_id, pairing_code, display_name
    INTO partner_user_id, my_pairing_code, sender_display_name
    FROM public.users WHERE id = auth.uid();

    -- Check if user has a partner
    IF partner_user_id IS NULL THEN
        RAISE EXCEPTION 'no_partner';
    END IF;

    IF partner_user_id = auth.uid() THEN
        RAISE EXCEPTION 'cannot_send_to_self';
    END IF;

    -- Get partner info
    SELECT pairing_code, display_name
    INTO partner_pairing_code, partner_display_name
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

    -- Determine gift cost based on type
    gift_cost := CASE p_gift_type
        WHEN 'candy' THEN 100
        WHEN 'lollipop' THEN 120
        WHEN 'sweet' THEN 130
        WHEN 'rose' THEN 150
        WHEN 'donut' THEN 160
        WHEN 'star' THEN 170
        WHEN 'toast' THEN 180
        WHEN 'cake' THEN 200
        WHEN 'lipgloss' THEN 220
        WHEN 'juice' THEN 250
        WHEN 'snowman' THEN 280
        WHEN 'xmastree' THEN 350
        WHEN 'pizza' THEN 400
        WHEN 'watch' THEN 450
        WHEN 'necklace' THEN 500
        WHEN 'ring' THEN 600
        ELSE 100
    END;

    -- Check if couple has enough hearts (COUPLE-LEVEL, not user-level)
    SELECT hearts INTO current_hearts
    FROM public.couple_progress WHERE couple_key = v_couple_key;

    IF current_hearts IS NULL OR current_hearts < gift_cost THEN
        RAISE EXCEPTION 'insufficient_hearts';
    END IF;

    -- Deduct hearts from couple (SHARED hearts pool)
    UPDATE public.couple_progress
    SET hearts = hearts - gift_cost
    WHERE couple_key = v_couple_key;

    -- Create gift record
    INSERT INTO public.gifts (
        couple_key,
        sender_id,
        sender_name,
        recipient_id,
        recipient_name,
        gift_type,
        message
    )
    VALUES (
        v_couple_key,
        auth.uid(),
        COALESCE(sender_display_name, 'Someone'),
        partner_user_id,
        COALESCE(partner_display_name, 'Your partner'),
        p_gift_type,
        p_message
    )
    RETURNING * INTO new_gift;

    -- Add gift activity to couple_activity
    INSERT INTO public.couple_activity (
        couple_key,
        actor_id,
        actor_name,
        action_type,
        pet_name
    )
    VALUES (
        v_couple_key,
        auth.uid(),
        COALESCE(sender_display_name, 'Someone'),
        'gift_' || p_gift_type,
        NULL
    );

    -- Send push notification to partner
    IF partner_user_id IS NOT NULL THEN
        PERFORM public.send_test_push(
            partner_user_id,
            '🎁 ' || COALESCE(sender_display_name, 'Someone') || ' sent you a gift!',
            COALESCE('You received a ' || p_gift_type || '!', 'Check it out in the app!'),
            jsonb_build_object('type', 'gift', 'gift_id', new_gift.id)
        );
    END IF;

    RETURN new_gift;
END;
$$;

-- Step 5: Create function to mark gift as opened
CREATE OR REPLACE FUNCTION public.mark_gift_opened(p_gift_id uuid)
RETURNS public.gifts
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    updated_gift public.gifts%rowtype;
BEGIN
    -- Update gift to mark as opened
    UPDATE public.gifts
    SET is_opened = true
    WHERE id = p_gift_id AND recipient_id = auth.uid()
    RETURNING * INTO updated_gift;

    IF updated_gift.id IS NULL THEN
        RAISE EXCEPTION 'gift_not_found_or_unauthorized';
    END IF;

    RETURN updated_gift;
END;
$$;

-- Step 6: Create function to load gifts for a couple
CREATE OR REPLACE FUNCTION public.load_couple_gifts()
RETURNS TABLE (
    id uuid,
    couple_key text,
    sender_id uuid,
    sender_name text,
    recipient_id uuid,
    recipient_name text,
    gift_type text,
    message text,
    is_opened boolean,
    created_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    my_pairing_code text;
    partner_user_id uuid;
    partner_pairing_code text;
    v_couple_key text;
BEGIN
    -- Get user's pairing code and partner
    SELECT users.pairing_code, users.partner_id
    INTO my_pairing_code, partner_user_id
    FROM public.users
    WHERE users.id = auth.uid();

    -- If no partner, return empty
    IF partner_user_id IS NULL THEN
        RETURN;
    END IF;

    -- Get partner's pairing code
    SELECT users.pairing_code
    INTO partner_pairing_code
    FROM public.users
    WHERE users.id = partner_user_id;

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

    -- Return all gifts for this couple
    RETURN QUERY
    SELECT
        g.id,
        g.couple_key,
        g.sender_id,
        g.sender_name,
        g.recipient_id,
        g.recipient_name,
        g.gift_type,
        g.message,
        g.is_opened,
        g.created_at
    FROM public.gifts g
    WHERE g.couple_key = v_couple_key
    ORDER BY g.created_at DESC;
END;
$$;
