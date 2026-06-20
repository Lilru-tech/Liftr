import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const RESEND_API_KEY = Deno.env.get("RESEND_API_KEY");
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const ADMIN_EMAIL = "d.g.sanc@gmail.com";

const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

type WorkoutRecord = {
  id: number;
  user_id: string;
  kind: string;
  state: string;
  title: string | null;
  ended_at: string | null;
  started_at: string | null;
};

type WebhookPayload = {
  type: "INSERT" | "UPDATE" | "DELETE";
  record: WorkoutRecord;
  old_record?: WorkoutRecord | null;
};

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function isPublishTransition(payload: WebhookPayload): boolean {
  const { type, record, old_record: oldRecord } = payload;
  if (record.state !== "published") return false;
  if (type === "INSERT") return true;
  if (type === "UPDATE") {
    return oldRecord?.state !== "published";
  }
  return false;
}

function kindLabel(kind: string): string {
  switch (kind) {
    case "strength":
      return "Fuerza";
    case "cardio":
      return "Cardio";
    case "sport":
      return "Deporte";
    default:
      return kind;
  }
}

Deno.serve(async (req) => {
  try {
    if (!RESEND_API_KEY) {
      return jsonResponse({ error: "RESEND_API_KEY not configured" }, 500);
    }

    const payload = (await req.json()) as WebhookPayload;

    if (!isPublishTransition(payload)) {
      return jsonResponse({ skipped: true, reason: "not_a_publish_transition" });
    }

    const record = payload.record;

    const { count, error: countError } = await supabase
      .from("workouts")
      .select("id", { count: "exact", head: true })
      .eq("user_id", record.user_id)
      .eq("state", "published");

    if (countError) {
      return jsonResponse({ error: countError.message }, 500);
    }

    if (count !== 1) {
      return jsonResponse({ skipped: true, reason: "not_first_published_workout", count });
    }

    const { error: milestoneError } = await supabase
      .from("admin_notification_milestones")
      .insert({
        user_id: record.user_id,
        first_workout_id: record.id,
      });

    if (milestoneError) {
      if (milestoneError.code === "23505") {
        return jsonResponse({ skipped: true, reason: "already_notified" });
      }
      return jsonResponse({ error: milestoneError.message }, 500);
    }

    const { data: authData, error: authError } = await supabase.auth.admin.getUserById(
      record.user_id,
    );

    if (authError) {
      return jsonResponse({ error: authError.message }, 500);
    }

    const userEmail = authData.user?.email ?? "desconocido";

    const { data: profile } = await supabase
      .from("profiles")
      .select("username")
      .eq("user_id", record.user_id)
      .maybeSingle();

    const username = profile?.username ?? "sin username";
    const workoutTitle = record.title?.trim() || "Sin título";
    const eventAt = record.ended_at ?? record.started_at ?? new Date().toISOString();

    const res = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${RESEND_API_KEY}`,
      },
      body: JSON.stringify({
        from: "Supabase <onboarding@resend.dev>",
        to: [ADMIN_EMAIL],
        subject: "🏋️ ¡Primer entrenamiento en Liftr!",
        html: `
          <h1>¡Un usuario acaba de completar su primer entrenamiento!</h1>
          <p><strong>Username:</strong> ${username}</p>
          <p><strong>Email:</strong> ${userEmail}</p>
          <p><strong>ID de usuario:</strong> ${record.user_id}</p>
          <p><strong>ID de entrenamiento:</strong> ${record.id}</p>
          <p><strong>Tipo:</strong> ${kindLabel(record.kind)}</p>
          <p><strong>Título:</strong> ${workoutTitle}</p>
          <p><strong>Fecha:</strong> ${new Date(eventAt).toLocaleString("es-ES")}</p>
        `,
      }),
    });

    const data = await res.json();

    if (!res.ok) {
      await supabase
        .from("admin_notification_milestones")
        .delete()
        .eq("user_id", record.user_id);
      return jsonResponse({ error: "resend_failed", details: data }, 502);
    }

    return jsonResponse({ sent: true, resend: data });
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    return jsonResponse({ error: message }, 500);
  }
});
