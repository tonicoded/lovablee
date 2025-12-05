// deno-lint-ignore-file no-explicit-any
import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.2";

const supabaseUrl =
  Deno.env.get("APP_SUPABASE_URL") ??
  Deno.env.get("SUPABASE_URL") ??
  "";
const serviceRoleKey =
  Deno.env.get("APP_SUPABASE_SERVICE_ROLE_KEY") ??
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ??
  "";

serve(async (req) => {
  if (!supabaseUrl || !serviceRoleKey) {
    return new Response(
      JSON.stringify({ error: "Missing Supabase env configuration" }),
      { status: 500, headers: corsHeaders() },
    );
  }

  if (req.method === "OPTIONS") {
    return new Response("ok", { status: 200, headers: corsHeaders() });
  }

  const authHeader = req.headers.get("Authorization") ?? "";
  const accessToken = authHeader.replace("Bearer ", "");
  if (!accessToken) {
    return new Response(JSON.stringify({ error: "Unauthorized" }), {
      status: 401,
      headers: corsHeaders(),
    });
  }

  const supabase = createClient(supabaseUrl, serviceRoleKey);

  const {
    data: { user },
    error: userError,
  } = await supabase.auth.getUser(accessToken);

  if (userError || !user) {
    return new Response(JSON.stringify({ error: "Invalid user token" }), {
      status: 401,
      headers: corsHeaders(),
    });
  }

  const { error: deleteError } = await supabase.auth.admin.deleteUser(user.id);
  if (deleteError) {
    return new Response(
      JSON.stringify({ error: "Failed to delete auth user" }),
      { status: 500, headers: corsHeaders() },
    );
  }

  return new Response(JSON.stringify({ success: true }), {
    status: 200,
    headers: corsHeaders(),
  });
});

function corsHeaders() {
  return {
    "Content-Type": "application/json",
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "*",
  };
}
