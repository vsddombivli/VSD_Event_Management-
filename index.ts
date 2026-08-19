// supabase/functions/send-notification/index.ts
//
// Generic notification sender for the VSD event app. Called from the client via:
//   sb.functions.invoke('send-notification', { body: { type: 'TEAM_ASSIGNMENT', area_assignment_id } })
//
// Designed to be reused across events with no code changes — it pulls whatever
// event/area/checklist data exists at call time. To add a new notification type
// later (e.g. DUE_TODAY, OVERDUE), add a case in the switch below; the email
// building + Resend send + notification_log write pattern stays the same.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const RESEND_API_KEY = Deno.env.get("RESEND_API_KEY") ?? "";
const SENDER_EMAIL = Deno.env.get("SENDER_EMAIL") ?? "noreply@example.com";
const SENDER_NAME = Deno.env.get("SENDER_NAME") ?? "VSD Events";
const APP_URL = Deno.env.get("APP_URL") ?? "";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

// service role client bypasses RLS — this function is trusted server-side code
const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
  db: { schema: "vsd" },
});

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS });
  }

  try {
    const { type, area_assignment_id } = await req.json();

    if (!type || !area_assignment_id) {
      return jsonResponse({ error: "type and area_assignment_id are required" }, 400);
    }

    switch (type) {
      case "TEAM_ASSIGNMENT":
        return await sendTeamAssignmentEmail(area_assignment_id);

      // Future types can slot in here without touching the client code that
      // calls this function or the notification_log table:
      // case "DUE_TODAY": return await sendDueTodayEmail(area_assignment_id);
      // case "OVERDUE": return await sendOverdueEmail(area_assignment_id);

      default:
        return jsonResponse({ error: `Unknown notification type: ${type}` }, 400);
    }
  } catch (err) {
    return jsonResponse({ error: String(err) }, 500);
  }
});

async function sendTeamAssignmentEmail(areaAssignmentId: string) {
  const { data: assignment, error } = await supabase
    .from("area_assignment")
    .select(`
      id, incharge_name, incharge_email, helper_names,
      area:area_id (
        id, area_name, temple_list, event_id,
        event:event_id ( name, event_date )
      )
    `)
    .eq("id", areaAssignmentId)
    .single();

  if (error || !assignment) {
    return jsonResponse({ error: "Assignment not found" }, 404);
  }

  const eventId = assignment.area.event_id;

  const { data: checklist } = await supabase
    .from("checklist_item")
    .select("label")
    .eq("event_id", eventId)
    .order("sort_order");

  const checklistHtml = (checklist || [])
    .map((c: { label: string }) => `<li>${escapeHtml(c.label)}</li>`)
    .join("");

  const eventName = assignment.area.event.name;
  const eventDate = assignment.area.event.event_date;
  const areaName = assignment.area.area_name;
  const temples = assignment.area.temple_list || "-";
  const helpers = assignment.helper_names || "-";

  const subject = `You're the incharge for ${areaName} — ${eventName}`;
  const html = `
    <div style="font-family:sans-serif;max-width:520px;margin:auto;color:#2C1B10;">
      <h2 style="color:#7A1E2B;margin-bottom:4px;">${escapeHtml(eventName)}</h2>
      <p>Hi ${escapeHtml(assignment.incharge_name)},</p>
      <p>You've been assigned as <b>incharge</b> for <b>${escapeHtml(areaName)}</b>.</p>
      <table style="border-collapse:collapse;margin:12px 0;">
        <tr><td style="padding:4px 8px;color:#666;">Event date</td><td style="padding:4px 8px;"><b>${escapeHtml(String(eventDate))}</b></td></tr>
        <tr><td style="padding:4px 8px;color:#666;">Temples</td><td style="padding:4px 8px;">${escapeHtml(temples)}</td></tr>
        <tr><td style="padding:4px 8px;color:#666;">Helpers</td><td style="padding:4px 8px;">${escapeHtml(helpers)}</td></tr>
      </table>
      <p><b>Checklist for your area:</b></p>
      <ul>${checklistHtml}</ul>
      ${
        APP_URL
          ? `<p><a href="${APP_URL}" style="background:#E29317;color:#fff;padding:10px 16px;border-radius:8px;text-decoration:none;display:inline-block;">Open the app</a></p>
             <p style="font-size:13px;color:#666;">Sign in with this email address (${escapeHtml(assignment.incharge_email)}) — you'll get a one-time sign-in link.</p>`
          : ""
      }
    </div>
  `;

  const resendResp = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${RESEND_API_KEY}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      from: `${SENDER_NAME} <${SENDER_EMAIL}>`,
      to: [assignment.incharge_email],
      subject,
      html,
    }),
  });

  const resendData = await resendResp.json().catch(() => ({}));

  // Audit log — also gives every future notification type a consistent trail.
  await supabase.from("notification_log").insert({
    event_id: eventId,
    area_id: assignment.area.id,
    notification_type: "TEAM_ASSIGNMENT",
    recipient: assignment.incharge_email,
    provider_message_id: resendData?.id ?? null,
    status: resendResp.ok ? "sent" : "failed",
    error_message: resendResp.ok ? null : JSON.stringify(resendData),
  });

  if (!resendResp.ok) {
    return jsonResponse({ error: "Failed to send email", details: resendData }, 500);
  }

  return jsonResponse({ success: true, id: resendData?.id ?? null });
}

function escapeHtml(str: string) {
  return String(str)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;");
}

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
  });
}
