import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "https://lisciandraj.github.io",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Vary": "Origin",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, "content-type": "application/json" } });
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { status: 200, headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const auth = req.headers.get("Authorization");
  if (!auth) return json({ error: "unauthorized" }, 401);

  const url = Deno.env.get("SUPABASE_URL")!;
  const anon = Deno.env.get("SUPABASE_ANON_KEY")!;
  const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const userClient = createClient(url, anon, { global: { headers: { Authorization: auth } } });

  const { data: { user }, error: userError } = await userClient.auth.getUser();
  if (userError || !user) return json({ error: "unauthorized" }, 401);

  const { data: profile } = await userClient.from("profiles").select("role,active").eq("id", user.id).maybeSingle();
  if (!profile || !profile.active || profile.role !== "administrador") return json({ error: "forbidden" }, 403);

  let body: Record<string, unknown>;
  try { body = await req.json(); } catch { return json({ error: "invalid_json" }, 400); }

  const email = String(body.email || "").trim().toLowerCase();
  const password = String(body.password || "");
  const full_name = String(body.full_name || "").trim();
  const role = String(body.role || "");
  // «Responsable RH» (rrhh) es un perfil de base como los demás.
  if (!email || password.length < 8 || !full_name || !["administrador", "comercial", "almacenero", "rrhh", "cliente"].includes(role)) {
    return json({ error: "invalid_input", message: "Nombre, email, contraseña (mínimo 8 caracteres) y rol válido son obligatorios." }, 400);
  }

  const admin = createClient(url, service);
  const { data: created, error: createError } = await admin.auth.admin.createUser({ email, password, email_confirm: true, user_metadata: { full_name, role } });
  if (createError || !created.user) return json({ error: createError?.message || "create_failed" }, 400);

  // El disparador gama_on_auth_user_created ya insertó el perfil en cuanto se
  // creó el usuario, con rol 'cliente' y active=false. Un insert aquí chocaba
  // contra profiles_pkey y hacía fracasar TODA creación de cuenta: la función
  // borraba el usuario recién creado y devolvía "duplicate key value violates
  // unique constraint profiles_pkey". Con upsert se corrige esa fila con el
  // rol elegido y se activa la cuenta, y si algún día no hubiera disparador,
  // la crearía igual.
  const { error: profileError } = await admin.from("profiles").upsert({ id: created.user.id, full_name, role, active: true }, { onConflict: "id" });
  if (profileError) {
    await admin.auth.admin.deleteUser(created.user.id);
    return json({ error: profileError.message }, 400);
  }
  return json({ id: created.user.id, email, full_name, role }, 201);
});
