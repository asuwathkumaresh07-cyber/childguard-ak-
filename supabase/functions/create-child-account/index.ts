import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function jsonResponse(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function defaultKeyFromEnv(name: string): string | undefined {
  const raw = Deno.env.get(name);
  if (!raw) return undefined;
  try {
    const keys = JSON.parse(raw) as Record<string, string>;
    return keys.default ?? Object.values(keys)[0];
  } catch {
    return undefined;
  }
}

Deno.serve(async (request: Request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (request.method !== "POST") {
    return jsonResponse(405, { error: "Method not allowed" });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ??
    defaultKeyFromEnv("SUPABASE_PUBLISHABLE_KEYS");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ??
    defaultKeyFromEnv("SUPABASE_SECRET_KEYS");
  const authorization = request.headers.get("Authorization");
  if (!supabaseUrl || !anonKey || !serviceRoleKey) {
    return jsonResponse(500, { error: "Child account service is not configured." });
  }
  if (!authorization?.startsWith("Bearer ")) {
    return jsonResponse(401, { error: "Sign in to the Parent app first." });
  }

  const callerClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authorization } },
    auth: { autoRefreshToken: false, persistSession: false },
  });
  const adminClient = createClient(supabaseUrl, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  const { data: authData, error: authError } = await callerClient.auth.getUser();
  const parent = authData.user;
  if (authError || !parent) {
    return jsonResponse(401, { error: "Your session expired. Sign in again." });
  }

  const { data: parentProfile, error: profileError } = await adminClient
    .from("profiles")
    .select("role")
    .eq("id", parent.id)
    .maybeSingle();
  if (profileError || parentProfile?.role !== "parent") {
    return jsonResponse(403, { error: "Only a parent can create a child account." });
  }

  let body: Record<string, unknown>;
  try {
    body = await request.json();
  } catch {
    return jsonResponse(400, { error: "Invalid request body." });
  }
  const email = typeof body.email === "string" ? body.email.trim().toLowerCase() : "";
  const password = typeof body.password === "string" ? body.password : "";
  const displayName = typeof body.display_name === "string"
    ? body.display_name.trim()
    : "";
  if (!email || !email.includes("@") || password.length < 6) {
    return jsonResponse(400, {
      error: "Enter a valid child email address and a password of at least 6 characters.",
    });
  }

  let { data: family, error: familyError } = await adminClient
    .from("families")
    .select("id")
    .eq("owner_id", parent.id)
    .limit(1)
    .maybeSingle();
  if (familyError) {
    return jsonResponse(500, { error: "Could not load the parent family." });
  }
  if (!family) {
    const createdFamily = await adminClient
      .from("families")
      .insert({ owner_id: parent.id, name: "My Family" })
      .select("id")
      .single();
    if (createdFamily.error || !createdFamily.data) {
      return jsonResponse(500, { error: "Could not create the parent family." });
    }
    family = createdFamily.data;
  }

  const name = displayName || "Child";
  const createdUser = await adminClient.auth.admin.createUser({
    email,
    password,
    email_confirm: true,
    user_metadata: { display_name: name },
    app_metadata: {
      family_guard_role: "child",
      family_guard_created_by: parent.id,
    },
  });
  const child = createdUser.data.user;
  if (createdUser.error || !child) {
    return jsonResponse(400, {
      error: createdUser.error?.message ?? "Could not create the child account.",
    });
  }

  const profileResult = await adminClient.from("profiles").upsert({
    id: child.id,
    role: "child",
    display_name: name,
  });
  const memberResult = profileResult.error
    ? null
    : await adminClient.from("family_members").upsert({
      family_id: family.id,
      profile_id: child.id,
    }, { onConflict: "family_id,profile_id" });

  if (profileResult.error || memberResult?.error) {
    await adminClient.auth.admin.deleteUser(child.id);
    return jsonResponse(500, { error: "The child account could not be linked to the family." });
  }

  return jsonResponse(201, {
    id: child.id,
    role: "child",
    display_name: name,
    email: child.email ?? email,
  });
});
