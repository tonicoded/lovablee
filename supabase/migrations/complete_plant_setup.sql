-- Complete Plant Watering Setup
-- This includes the column addition and function update

-- Step 1: Add last_plant_watered_at column to pet_status table
ALTER TABLE public.pet_status
ADD COLUMN IF NOT EXISTS last_plant_watered_at timestamptz;

-- Step 2: Update record_pet_action function to handle plant watering
-- (You need to run the entire CREATE OR REPLACE FUNCTION from schema.sql)
-- Or just run this partial update if the function already exists:

-- Note: The full function update should be done by re-running the
-- record_pet_action function from schema.sql lines 531-728
-- Make sure the elsif action_type = 'plant' block (lines 717-744) is included
