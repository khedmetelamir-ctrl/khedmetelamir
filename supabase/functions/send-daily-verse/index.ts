// Supabase Edge Function: send-daily-verse
// Required secrets: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, VAPID_PUBLIC_KEY,
// VAPID_PRIVATE_KEY, VAPID_SUBJECT, DAILY_VERSE_JOB_SECRET.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.57.0";
import webpush from "npm:web-push@3.6.7";
const corsHeaders = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-job-secret" };
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return new Response("Method not allowed", { status: 405 });
  const expected = Deno.env.get("DAILY_VERSE_JOB_SECRET");
  const supplied = req.headers.get("x-job-secret");
  if (!expected || !supplied || supplied !== expected) return new Response("Unauthorized", { status: 401 });
  const url = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const publicKey = Deno.env.get("VAPID_PUBLIC_KEY");
  const privateKey = Deno.env.get("VAPID_PRIVATE_KEY");
  const subject = Deno.env.get("VAPID_SUBJECT");
  if (!url || !serviceKey || !publicKey || !privateKey || !subject) return new Response(JSON.stringify({ error: "Missing server secrets" }), { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } });
  try {
    webpush.setVapidDetails(subject, publicKey, privateKey);
    const supabase = createClient(url, serviceKey);
    const response = await fetch("https://raw.githubusercontent.com/khedmetelamir-ctrl/khedmetelamir/main/verses-data.js");
    if (!response.ok) throw new Error("Could not load existing verses dataset");
    const source = await response.text();
    const match = source.match(/window\.SERVICE_VERSES_READY\s*=\s*Promise\.resolve\((\[.*\])\);?\s*$/s);
    if (!match) throw new Error("Existing verse dataset format was not recognized");
    const verses = JSON.parse(match[1]);
    if (!Array.isArray(verses) || verses.length !== 300) throw new Error("Expected exactly 300 existing verses");
    const cairoDate = new Intl.DateTimeFormat("en-CA", { timeZone: "Africa/Cairo", year: "numeric", month: "2-digit", day: "2-digit" }).format(new Date());
    const dayNumber = Math.floor(Date.parse(cairoDate + "T00:00:00Z") / 86400000);
    const verse = verses[((dayNumber % verses.length) + verses.length) % verses.length];
    const { data: subscriptions, error } = await supabase.from("daily_verse_push_subscriptions").select("id, subscription");
    if (error) throw error;
    let sent = 0, failed = 0;
    for (const row of subscriptions ?? []) {
      try {
        await webpush.sendNotification(row.subscription, JSON.stringify({ title: "آية اليوم — خدمة الأمير", body: `${verse.t}\n${verse.r}`, url: "/" }));
        sent++;
      } catch (e) {
        failed++;
        if ([404, 410].includes(e?.statusCode)) await supabase.from("daily_verse_push_subscriptions").delete().eq("id", row.id);
      }
    }
    return new Response(JSON.stringify({ date: cairoDate, verse: verse.n, sent, failed }), { headers: { ...corsHeaders, "Content-Type": "application/json" } });
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e?.message ?? e) }), { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } });
  }
});
