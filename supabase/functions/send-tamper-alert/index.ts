import { createClient } from "npm:@supabase/supabase-js@2";
import { importPKCS8, SignJWT } from "npm:jose@5";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function jsonResponse(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

Deno.serve(async (request: Request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (request.method !== "POST") {
    return jsonResponse(405, { error: "Method not allowed." });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const serviceAccountValue = Deno.env.get("FCM_SERVICE_ACCOUNT");
  const authorization = request.headers.get("Authorization");
  if (!supabaseUrl || !anonKey || !serviceRoleKey || !serviceAccountValue) {
    return jsonResponse(503, {
      error: "Supabase push alert service is not fully configured.",
    });
  }
  if (!authorization?.startsWith("Bearer ")) {
    return jsonResponse(401, { error: "Sign in to the Child app first." });
  }

  const caller = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authorization } },
    auth: { autoRefreshToken: false, persistSession: false },
  });
  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  const { data: authData, error: authError } = await caller.auth.getUser();
  if (authError || !authData.user) {
    return jsonResponse(401, { error: "Your Child app session has expired." });
  }

  let body: Record<string, unknown>;
  try {
    body = await request.json();
  } catch {
    return jsonResponse(400, { error: "Invalid request body." });
  }
  const eventId = typeof body.event_id === "string" ? body.event_id : "";
  const alertType = body.alert_type === "zone_event" ? "zone_event" : "tamper";
  if (!eventId) {
    return jsonResponse(400, { error: "An alert event ID is required." });
  }

  type AlertEvent = {
    id: string;
    child_id: string;
    family_id: string;
    event_type: string;
    zone_id?: string;
    package_name?: string | null;
  };
  let event: AlertEvent | null;
  let eventError: { message: string } | null;
  if (alertType === "zone_event") {
    const result = await admin
      .from("zone_events")
      .select("id, child_id, family_id, zone_id, event_type, package_name")
      .eq("id", eventId)
      .eq("child_id", authData.user.id)
      .in("event_type", ["entered", "exited", "off_task_app"])
      .maybeSingle();
    event = result.data;
    eventError = result.error;
  } else {
    const result = await admin
      .from("child_tamper_events")
      .select("id, child_id, family_id, event_type")
      .eq("id", eventId)
      .eq("child_id", authData.user.id)
      .maybeSingle();
    event = result.data;
    eventError = result.error;
  }
  if (eventError || !event) {
    return jsonResponse(404, { error: "The tamper event was not found." });
  }

  const { data: family, error: familyError } = await admin
    .from("families")
    .select("owner_id")
    .eq("id", event.family_id)
    .maybeSingle();
  if (familyError || !family) {
    return jsonResponse(404, { error: "The parent family was not found." });
  }

  let notificationTitle = "Family Guard protection alert";
  let notificationBody =
    "A child's protection setting changed. Open the Parent app to review.";
  if (alertType === "zone_event") {
    const { data: zone, error: zoneError } = await admin
      .from("family_zones")
      .select("name")
      .eq("id", event.zone_id)
      .eq("family_id", event.family_id)
      .maybeSingle();
    if (zoneError || !zone) {
      return jsonResponse(404, { error: "The focus zone was not found." });
    }
    if (event.event_type === "entered") {
      notificationTitle = `Arrived at ${zone.name}`;
      notificationBody = `Your child arrived at ${zone.name}.`;
    } else if (event.event_type === "exited") {
      notificationTitle = `Left ${zone.name}`;
      notificationBody = `Your child left ${zone.name}.`;
    } else {
      notificationTitle = `Off-task app opened in ${zone.name}`;
      notificationBody =
        `${event.package_name ?? "An app"} was opened in a focus zone.`;
    }
  } else {
    const messages: Record<string, string> = {
      vpn_disabled: "VPN protection was turned off.",
      vpn_enabled: "VPN protection was restored.",
      usage_access_revoked: "App usage monitoring was turned off.",
      usage_access_restored: "App usage monitoring was restored.",
      accessibility_disabled: "App blocking was turned off.",
      accessibility_restored: "App blocking was restored.",
      location_sharing_disabled: "Location sharing was turned off.",
      location_sharing_enabled: "Location sharing was turned on.",
    };
    notificationBody = messages[event.event_type] ??
      "A child's protection setting changed. Open the Parent app to review.";
  }

  const { data: tokens, error: tokenError } = await admin
    .from("parent_push_tokens")
    .select("id, token")
    .eq("parent_id", family.owner_id);
  if (tokenError) {
    return jsonResponse(500, { error: "Could not load parent push devices." });
  }
  if (!tokens?.length) {
    return jsonResponse(200, { delivered: 0 });
  }

  let serviceAccount: {
    client_email?: string;
    private_key?: string;
    project_id?: string;
  };
  try {
    serviceAccount = JSON.parse(serviceAccountValue);
  } catch {
    return jsonResponse(500, { error: "FCM service account JSON is invalid." });
  }
  const { client_email, private_key, project_id } = serviceAccount;
  if (!client_email || !private_key || !project_id) {
    return jsonResponse(500, {
      error: "FCM service account is missing required fields.",
    });
  }

  let accessToken: string;
  try {
    const key = await importPKCS8(private_key, "RS256");
    const assertion = await new SignJWT({
      scope: "https://www.googleapis.com/auth/firebase.messaging",
    })
      .setProtectedHeader({ alg: "RS256", typ: "JWT" })
      .setIssuer(client_email)
      .setAudience("https://oauth2.googleapis.com/token")
      .setIssuedAt()
      .setExpirationTime("1h")
      .sign(key);
    const tokenResponse = await fetch("https://oauth2.googleapis.com/token", {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
        assertion,
      }),
    });
    const tokenBody = await tokenResponse.json();
    if (!tokenResponse.ok || typeof tokenBody.access_token !== "string") {
      return jsonResponse(502, { error: "Could not authenticate with FCM." });
    }
    accessToken = tokenBody.access_token;
  } catch {
    return jsonResponse(502, { error: "Could not create FCM authorization." });
  }

  let delivered = 0;
  const invalidTokens: string[] = [];
  for (const token of tokens) {
    const response = await fetch(
      `https://fcm.googleapis.com/v1/projects/${project_id}/messages:send`,
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${accessToken}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          message: {
            token: token.token,
            notification: {
              title: notificationTitle,
              body: notificationBody,
            },
            data: {
              type: alertType === "zone_event"
                ? "child_zone_event"
                : "child_tamper_event",
              event_id: event.id,
            },
            android: { priority: "high" },
          },
        }),
      },
    );
    if (response.ok) {
      delivered += 1;
      continue;
    }
    const responseBody = await response.json().catch(() => ({}));
    const errorCode = responseBody?.error?.details?.find(
      (detail: Record<string, unknown>) =>
        detail.errorCode === "UNREGISTERED" ||
        detail.errorCode === "INVALID_ARGUMENT",
    )?.errorCode;
    if (errorCode === "UNREGISTERED") {
      invalidTokens.push(token.id);
    }
  }

  if (invalidTokens.length > 0) {
    const { error: deleteError } = await admin
      .from("parent_push_tokens")
      .delete()
      .in("id", invalidTokens);
    if (deleteError) {
      return jsonResponse(500, {
        error: "Could not remove expired parent push tokens.",
      });
    }
  }

  if (delivered === 0) {
    return jsonResponse(502, {
      error: "The alert was recorded, but FCM could not deliver it.",
    });
  }
  return jsonResponse(200, { delivered });
});
