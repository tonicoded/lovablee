-- Migration: Add plant watering feature with 15-minute cooldown

-- Add last_plant_watered_at column to pet_status table
ALTER TABLE public.pet_status
ADD COLUMN IF NOT EXISTS last_plant_watered_at timestamptz;
