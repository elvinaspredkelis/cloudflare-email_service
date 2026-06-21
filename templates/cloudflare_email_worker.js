// Cloudflare Email Worker for cloudflare-email_service inbound (Action Mailbox).
//
// - email(): forwards each received message to your Rails app's :cloudflare
//   ingress, signed with HMAC-SHA256 over "<timestamp>.<body>".
// - fetch(): a GET health check. Email Workers have no HTTP API, so visiting the
//   worker URL would otherwise error; this returns whether the vars are set.
//
// Set two Worker secrets/vars, then bind the Worker to an Email Routing rule and
// deploy (e.g. wrangler):
//   - CLOUDFLARE_EMAIL_INGRESS_URL    full URL of the ingress, e.g.
//       https://your-app.example.com/rails/action_mailbox/cloudflare/inbound_emails
//   - CLOUDFLARE_EMAIL_INGRESS_SECRET same value as the app's
//       config.ingress_secret (CLOUDFLARE_EMAIL_INGRESS_SECRET)

export default {
  async fetch(_request, env) {
    const configured = Boolean(
      env.CLOUDFLARE_EMAIL_INGRESS_URL && env.CLOUDFLARE_EMAIL_INGRESS_SECRET,
    );
    return Response.json({ ok: true, configured });
  },

  async email(message, env) {
    const { CLOUDFLARE_EMAIL_INGRESS_URL: url, CLOUDFLARE_EMAIL_INGRESS_SECRET: secret } = env;
    if (!url || !secret) {
      return message.setReject("CLOUDFLARE_EMAIL_INGRESS_URL / _SECRET not configured");
    }

    // arrayBuffer (not text) preserves the raw bytes of non-UTF-8 messages.
    const raw = new Uint8Array(await new Response(message.raw).arrayBuffer());
    const ts = Math.floor(Date.now() / 1000).toString();

    const key = await crypto.subtle.importKey(
      "raw", new TextEncoder().encode(secret),
      { name: "HMAC", hash: "SHA-256" }, false, ["sign"],
    );
    const signed = new Uint8Array([...new TextEncoder().encode(ts + "."), ...raw]);
    const digest = await crypto.subtle.sign("HMAC", key, signed);
    const sig = [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");

    const response = await fetch(url, {
      method: "POST",
      headers: {
        "Content-Type": "message/rfc822",
        "X-CF-Email-Timestamp": ts,
        "X-CF-Email-Signature": sig,
      },
      body: raw,
    });

    if (response.ok) return;

    // 4xx: the app refused this message and a retry won't change the outcome
    // (bad signature, wrong media type, unprocessable). Reject permanently so
    // the sender gets a bounce instead of the message being silently dropped.
    if (response.status >= 400 && response.status < 500) {
      return message.setReject(`ingress rejected message (${response.status})`);
    }

    // 5xx (or any other non-2xx): a transient app problem — a deploy, a 502/503,
    // a brief 500. Throw instead of setReject, exactly as a failed fetch() above
    // already would, so the message is NOT permanently bounced and the sending
    // server retries delivery once the app recovers.
    throw new Error(`ingress temporarily unavailable (${response.status})`);
  },
};
