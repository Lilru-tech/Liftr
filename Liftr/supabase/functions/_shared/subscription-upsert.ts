import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";

export type SubscriptionUpsertInput = {
  user_id: string;
  status: string;
  provider: string;
  original_transaction_id: string;
  expires_at: string;
};

export async function upsertUserSubscription(
  supabase: SupabaseClient,
  payload: SubscriptionUpsertInput,
): Promise<{ error: string | null }> {
  const nowIso = new Date().toISOString();
  const { error } = await supabase.from("user_subscriptions").upsert(
    {
      user_id: payload.user_id,
      status: payload.status,
      provider: payload.provider,
      original_transaction_id: payload.original_transaction_id,
      expires_at: payload.expires_at,
      updated_at: nowIso,
    },
    { onConflict: "user_id" },
  );
  return { error: error?.message ?? null };
}
