// ═══════════════════════════════════════════════════════════════════════
//  OpenClaw Factory — Token verification Worker
//
//  Назначение:
//    - Принимает POST /verify с токеном
//    - Проверяет в KV namespace OPENCLAW_TOKENS
//    - Отдаёт 200 + имя ученика, если токен валидный
//    - Трекает активацию (чтобы видеть, кто и когда устанавливал)
//
//  Деплой:
//    wrangler deploy
// ═══════════════════════════════════════════════════════════════════════

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);

    // CORS для локальных тестов
    const corsHeaders = {
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Methods": "POST, GET, OPTIONS",
      "Access-Control-Allow-Headers": "Content-Type",
    };

    if (request.method === "OPTIONS") {
      return new Response(null, { headers: corsHeaders });
    }

    // ─── Проверка токена ──────────────────────────────────────────────
    if (url.pathname === "/verify" && request.method === "POST") {
      const body = await request.json().catch(() => ({}));
      const token = (body.token || "").trim();

      if (!token) {
        return json({ ok: false, error: "empty_token" }, 400, corsHeaders);
      }

      // Токены в KV: key = токен, value = JSON { user, email, activations, maxActivations, expiresAt, revoked }
      const raw = await env.OPENCLAW_TOKENS.get(token);

      if (!raw) {
        return json({ ok: false, error: "invalid_token" }, 403, corsHeaders);
      }

      const record = JSON.parse(raw);

      // Отозван ли?
      if (record.revoked) {
        return json({ ok: false, error: "revoked" }, 403, corsHeaders);
      }

      // Истёк ли?
      if (record.expiresAt && new Date(record.expiresAt) < new Date()) {
        return json({ ok: false, error: "expired" }, 403, corsHeaders);
      }

      // Лимит активаций?
      const activations = record.activations || 0;
      const max = record.maxActivations || 3; // по умолчанию 3 активации (основной комп + запасной + переустановка)

      if (activations >= max) {
        return json(
          { ok: false, error: "limit_reached", activations, max },
          403,
          corsHeaders
        );
      }

      // Обновляем счётчик активаций
      record.activations = activations + 1;
      record.lastActivatedAt = new Date().toISOString();
      record.lastActivationIP = request.headers.get("cf-connecting-ip") || "unknown";

      await env.OPENCLAW_TOKENS.put(token, JSON.stringify(record));

      return json(
        {
          ok: true,
          user: record.user || "студент",
          activations: record.activations,
          max,
          message: `Добро пожаловать, ${record.user || "студент"}! Активация ${record.activations}/${max}.`,
        },
        200,
        corsHeaders
      );
    }

    // ─── Админка: выпустить токен (защищено секретом) ────────────────
    if (url.pathname === "/admin/issue" && request.method === "POST") {
      const adminKey = request.headers.get("X-Admin-Key");
      if (adminKey !== env.ADMIN_SECRET) {
        return json({ ok: false, error: "forbidden" }, 403, corsHeaders);
      }

      const body = await request.json().catch(() => ({}));
      const token = body.token || generateToken();
      const record = {
        user: body.user || "student",
        email: body.email || null,
        activations: 0,
        maxActivations: body.maxActivations || 3,
        expiresAt: body.expiresAt || null,
        revoked: false,
        issuedAt: new Date().toISOString(),
      };

      await env.OPENCLAW_TOKENS.put(token, JSON.stringify(record));

      return json({ ok: true, token, record }, 200, corsHeaders);
    }

    // ─── Админка: отозвать токен ─────────────────────────────────────
    if (url.pathname === "/admin/revoke" && request.method === "POST") {
      const adminKey = request.headers.get("X-Admin-Key");
      if (adminKey !== env.ADMIN_SECRET) {
        return json({ ok: false, error: "forbidden" }, 403, corsHeaders);
      }

      const body = await request.json().catch(() => ({}));
      const raw = await env.OPENCLAW_TOKENS.get(body.token);
      if (!raw) return json({ ok: false, error: "not_found" }, 404, corsHeaders);

      const record = JSON.parse(raw);
      record.revoked = true;
      record.revokedAt = new Date().toISOString();
      await env.OPENCLAW_TOKENS.put(body.token, JSON.stringify(record));

      return json({ ok: true }, 200, corsHeaders);
    }

    // ─── Корень: health check ────────────────────────────────────────
    if (url.pathname === "/" || url.pathname === "/health") {
      return json({ ok: true, service: "openclaw-factory-auth" }, 200, corsHeaders);
    }

    return json({ ok: false, error: "not_found" }, 404, corsHeaders);
  },
};

function json(data, status, headers = {}) {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      "Content-Type": "application/json",
      ...headers,
    },
  });
}

function generateToken() {
  // Формат: OC-XXXX-XXXX-XXXX (12 символов, легко диктовать)
  const chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"; // убрали I, O, 0, 1 (путаются)
  const groups = [];
  for (let g = 0; g < 3; g++) {
    let s = "";
    for (let i = 0; i < 4; i++) {
      s += chars[Math.floor(Math.random() * chars.length)];
    }
    groups.push(s);
  }
  return "OC-" + groups.join("-");
}
