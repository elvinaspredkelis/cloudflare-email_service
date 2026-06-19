// Cloudflare Email Worker for cloudflare-email_service inbound (Action Mailbox).
//
// Forwards each received message to your Rails app's :cloudflare ingress, signed
// with HMAC-SHA256 over "<timestamp>.<body>" so the ingress can verify it and
// reject replays.
//
// Set two Worker secrets/vars, then bind the Worker to an Email Routing rule and
// deploy (e.g. wrangler):
//   - CLOUDFLARE_EMAIL_INGRESS_URL    full URL of the ingress, e.g.
//       https://your-app.example.com/rails/action_mailbox/cloudflare/inbound_emails
//   - CLOUDFLARE_EMAIL_INGRESS_SECRET same value as the app's
//       CLOUDFLARE_EMAIL_INGRESS_SECRET (or cloudflare.ingress_secret)

export default {
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

    // Reject on failure so Cloudflare bounces the message rather than silently
    // accepting (and dropping) it.
    if (!response.ok) message.setReject(`ingress error ${response.status}`);
  },
};
