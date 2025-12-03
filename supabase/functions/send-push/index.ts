import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.48.1";

const supabaseUrl = Deno.env.get("APP_SUPABASE_URL") ?? "";
const serviceRoleKey = Deno.env.get("APP_SUPABASE_SERVICE_ROLE_KEY") ?? "";
const apnsKeyId = Deno.env.get("APNS_KEY_ID") ?? "";
const apnsTeamId = Deno.env.get("APNS_TEAM_ID") ?? "";
const apnsPrivateKey = (Deno.env.get("APNS_PRIVATE_KEY") ?? "").replace(/\\n/g, "\n");
const apnsBundleId = Deno.env.get("APNS_BUNDLE_ID") ?? "";

if (!supabaseUrl || !serviceRoleKey) {
  throw new Error("Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY.");
}

const supabase = createClient(supabaseUrl, serviceRoleKey);

interface PushRequest {
  targetUserId: string;
  title: string;
  body: string;
  payload?: Record<string, unknown>;
}

interface UserRecord {
  apns_token: string | null;
}

serve(async (req) => {
  if (req.method !== "POST") {
    return new Response("Method Not Allowed", { status: 405 });
  }
  let body: PushRequest;
  try {
    body = await req.json();
  } catch {
    return new Response("Invalid JSON body", { status: 400 });
  }

  const { targetUserId, title, body: message, payload } = body;
  if (!targetUserId || !title || !message) {
    return new Response("Missing targetUserId/title/body", { status: 400 });
  }
  if (!apnsKeyId || !apnsTeamId || !apnsPrivateKey || !apnsBundleId) {
    return new Response("APNs environment variables are not configured.", {
      status: 500,
    });
  }

  const { data, error } = await supabase
    .from<UserRecord>("users")
    .select("apns_token")
    .eq("id", targetUserId)
    .not("apns_token", "is", null);

  if (error) {
    console.error("Supabase lookup error:", error);
    return new Response("Failed to fetch device tokens", { status: 500 });
  }

  if (!data || data.length === 0) {
    return new Response("No device tokens registered for that user.", { status: 404 });
  }

  const tokens = Array.from(
    new Set(
      data
        .map((record) => record.apns_token)
        .filter((token): token is string => Boolean(token)),
    ),
  );

  const sendResults: Record<string, number> = {};

  console.log(`send-push: delivering to ${tokens.length} token(s) for user ${targetUserId}`);
  for (const token of tokens) {
    try {
      const status = await sendApnsPush({
        deviceToken: token,
        title,
        body: message,
        payload,
      });
      sendResults[token] = status;
    } catch (err) {
      console.error("APNs send error:", err);
      sendResults[token] = 0;
    }
  }

  return new Response(JSON.stringify({ tokens: sendResults }), {
    headers: { "Content-Type": "application/json" },
  });
});

interface ApnsPayload {
  deviceToken: string;
  title: string;
  body: string;
  payload?: Record<string, unknown>;
}

async function sendApnsPush({ deviceToken, title, body, payload }: ApnsPayload): Promise<number> {
  const jwt = await buildApnsJwt();
  const aps: Record<string, unknown> = {
    aps: {
      alert: {
        title,
        body,
      },
      sound: "default",
      "content-available": 1,
    },
  };

  if (payload) {
    Object.assign(aps, payload);
  }

  console.log(`send-push: hitting APNs sandbox for token ${deviceToken.slice(0, 6)}...`);
  const response = await fetch(`https://api.sandbox.push.apple.com/3/device/${deviceToken}`, {
    method: "POST",
    body: JSON.stringify(aps),
    headers: {
      "authorization": `bearer ${jwt}`,
      "apns-topic": apnsBundleId,
      "content-type": "application/json",
    },
  });

  const text = await response.text();
  console.log(`send-push: APNs response ${response.status} ${text}`);
  if (!response.ok) {
    throw new Error(`APNs error (${response.status}): ${text}`);
  }
  return response.status;
}

async function buildApnsJwt(): Promise<string> {
  const header = { alg: "ES256", kid: apnsKeyId, typ: "JWT" };
  const payload = { iss: apnsTeamId, iat: Math.floor(Date.now() / 1000) };

  const encoder = new TextEncoder();
  const headerPart = base64UrlEncode(encoder.encode(JSON.stringify(header)));
  const payloadPart = base64UrlEncode(encoder.encode(JSON.stringify(payload)));
  const signingInput = `${headerPart}.${payloadPart}`;

  const key = await importPrivateKey(apnsPrivateKey);
  const signature = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    encoder.encode(signingInput),
  );
  const signaturePart = base64UrlEncode(new Uint8Array(signature));

  return `${signingInput}.${signaturePart}`;
}

async function importPrivateKey(pem: string): Promise<CryptoKey> {
  const cleaned = pem
    .replace("-----BEGIN PRIVATE KEY-----", "")
    .replace("-----END PRIVATE KEY-----", "")
    .replace(/\s+/g, "");

  const binaryDerString = atob(cleaned);
  const binaryDer = new Uint8Array(binaryDerString.length);
  for (let i = 0; i < binaryDer.length; i++) {
    binaryDer[i] = binaryDerString.charCodeAt(i);
  }

  return crypto.subtle.importKey(
    "pkcs8",
    binaryDer.buffer,
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
}

function base64UrlEncode(input: Uint8Array): string {
  return btoa(String.fromCharCode(...input))
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/, "");
}
