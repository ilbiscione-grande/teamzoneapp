// The withdrawal function's server side: what the person can withdraw from,
// and the withdrawal itself. The message counts from the moment it is stored,
// so the Stripe cancellation and the mails come after and may be retried.
import type { SupabaseClient } from "npm:@supabase/supabase-js@2.57.4";
import type Stripe from "npm:stripe@22.0.0";
import {
  latestPurchase,
  purchaseInterval,
  withdrawalLastDay,
  withdrawalOpen,
  withdrawalReceipt,
  withdrawalSupportMail,
} from "../_shared/tacticsboard_withdrawal.ts";

const supportAddress = "support@teamzoneapp.se";

type Context = {
  admin: SupabaseClient;
  stripe: Stripe;
  livemode: boolean;
  profileId: string;
  email: string;
};

async function findPurchase({ admin, stripe, livemode, profileId }: Context) {
  const { data: customer, error } = await admin.schema("api").rpc(
    "tacticsboard_billing_customer",
    { target_profile_id: profileId, target_livemode: livemode },
  );
  if (error) throw new Error("customer_failed");
  if (typeof customer !== "string") return null;
  const subscriptions = [];
  for await (
    const item of stripe.subscriptions.list({ customer, status: "all" })
  ) subscriptions.push(item);
  return latestPurchase(subscriptions);
}

async function storedWithdrawal(admin: SupabaseClient, reference: string) {
  const { data, error } = await admin.schema("api").rpc(
    "tacticsboard_withdrawal",
    { target_subscription_ref: reference },
  );
  if (error) throw new Error("withdrawal_read_failed");
  return data as
    | { id: string; received_at: string; receipt_sent_at: string | null }
    | null;
}

const receivedAnswer = (
  stored: { received_at: string; receipt_sent_at: string | null },
) => ({
  state: "received",
  received_at: stored.received_at,
  receipt_sent: stored.receipt_sent_at !== null,
});

export async function withdrawalStatus(context: Context) {
  const purchase = await findPurchase(context);
  if (!purchase) return { state: "none" };
  const stored = await storedWithdrawal(context.admin, purchase.id);
  if (stored) return receivedAnswer(stored);
  return {
    state: withdrawalOpen(purchase.start_date) ? "open" : "expired",
    interval: purchaseInterval(purchase),
    purchased_at: new Date(purchase.start_date * 1000).toISOString(),
    last_day: withdrawalLastDay(purchase.start_date),
    email: context.email,
  };
}

async function sendMail(
  key: string,
  from: string,
  to: string,
  idempotencyKey: string,
  mail: { subject: string; text: string },
) {
  const response = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      authorization: `Bearer ${key}`,
      "content-type": "application/json",
      "idempotency-key": idempotencyKey,
    },
    body: JSON.stringify({ from, to: [to], ...mail }),
  });
  return response.ok;
}

export async function withdraw(context: Context, name: string) {
  const { admin, stripe, livemode, profileId, email } = context;
  const purchase = await findPurchase(context);
  if (!purchase) return { state: "none" };
  let stored = await storedWithdrawal(admin, purchase.id);
  if (!stored && !withdrawalOpen(purchase.start_date)) {
    return { state: "expired", last_day: withdrawalLastDay(purchase.start_date) };
  }
  if (!stored) {
    const { data, error } = await admin.schema("api").rpc(
      "record_tacticsboard_withdrawal",
      {
        target_profile_id: profileId,
        target_livemode: livemode,
        target_subscription_ref: purchase.id,
        target_name: name,
        target_email: email,
        target_purchased_at: new Date(purchase.start_date * 1000).toISOString(),
      },
    );
    if (error || !data) throw new Error("withdrawal_record_failed");
    stored = data as NonNullable<typeof stored>;
  }
  if (stored.receipt_sent_at) return receivedAnswer(stored);

  let cancelled = ["canceled", "incomplete_expired"].includes(purchase.status);
  if (!cancelled) {
    try {
      await stripe.subscriptions.cancel(purchase.id);
      cancelled = true;
    } catch {
      cancelled = false;
    }
  }

  const resendKey = Deno.env.get("RESEND_API_KEY");
  const from = Deno.env.get("SUPPORT_EMAIL_FROM") ??
    "TeamZone <support@teamzoneapp.se>";
  const item = {
    name,
    email,
    receivedAt: stored.received_at,
    purchasedAtSeconds: purchase.start_date,
    interval: purchaseInterval(purchase),
  };
  const period = (purchase.items.data[0] as { current_period_start?: number })
    ?.current_period_start ?? null;
  const paidFrom = purchase.status === "trialing" ? null : period;
  const sent = !!resendKey && await sendMail(
    resendKey,
    from,
    email,
    `teamzone-withdrawal-receipt-${stored.id}`,
    withdrawalReceipt(item),
  );
  if (resendKey) {
    await sendMail(
      resendKey,
      from,
      supportAddress,
      `teamzone-withdrawal-support-${stored.id}`,
      withdrawalSupportMail({
        ...item,
        subscriptionRef: purchase.id,
        subscriptionStatus: purchase.status,
        cancelled,
        paidPeriodStartSeconds: paidFrom,
      }),
    );
  }
  if (sent) {
    await admin.schema("api").rpc("mark_tacticsboard_withdrawal_receipt", {
      target_withdrawal_id: stored.id,
    });
  }
  return {
    state: "received",
    received_at: stored.received_at,
    receipt_sent: sent,
  };
}
