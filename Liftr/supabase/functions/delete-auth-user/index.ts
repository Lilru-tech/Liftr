import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

Deno.serve(async (req) => {
  try {
    const url = Deno.env.get("SUPABASE_URL")!;
    const anon = Deno.env.get("SUPABASE_ANON_KEY")!;
    const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

    const userClient = createClient(url, anon, {
      global: { headers: { Authorization: req.headers.get("Authorization")! } },
    });
    const { data: { user }, error: getUserErr } = await userClient.auth.getUser();
    if (getUserErr || !user) return new Response("Unauthorized", { status: 401 });

    const admin = createClient(url, service);
    const { error: delErr } = await admin.auth.admin.deleteUser(user.id);
    if (delErr) return new Response(delErr.message, { status: 500 });

    return new Response("ok", { status: 200 });
  } catch (e) {
    console.error(e);
    return new Response("Internal error", { status: 500 });
  }
});
