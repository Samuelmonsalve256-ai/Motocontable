// ════════════════════════════════════════════════════════════════════════════
// PlacaLimpia PM · Platinium Motors
// Función de Supabase (Edge Function) que hace la consulta ciudadana del RUNT
// por placa + documento del propietario, con el captcha que escribe la persona.
//
//   accion "captcha"   → pide al RUNT una imagen de captcha nueva.
//   accion "consultar" → con placa, documento y el texto del captcha, hace la
//                        misma consulta que la página oficial y devuelve juntos
//                        vehículo, SOAT, tecnomecánica, limitaciones (embargos),
//                        prendas, garantías mobiliarias y solicitudes.
//
// Solo responde a un usuario con sesión iniciada en tu proyecto (tu cuenta de
// MotoContable). El RUNT no deja que una página de otro sitio lo consulte desde
// el navegador; por eso la consulta pasa por aquí.
// Instalación: supabase/LEEME.md → FASE 13.
// ════════════════════════════════════════════════════════════════════════════

const API = "https://runtproapi.runt.gov.co/CYRConsultaVehiculoMS";

const CORS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const TIPOS_DOC = ["C", "E", "N", "P", "D", "Y", "U", "T"];

function responder(datos: unknown, estado = 200): Response {
  return new Response(JSON.stringify(datos), {
    status: estado,
    headers: { ...CORS, "Content-Type": "application/json; charset=utf-8" },
  });
}

// Comprueba que quien llama tiene sesión iniciada (no basta la llave pública).
async function usuarioValido(req: Request): Promise<boolean> {
  const auth = req.headers.get("Authorization") || "";
  const url = Deno.env.get("SUPABASE_URL");
  const anon = Deno.env.get("SUPABASE_ANON_KEY");
  if (!auth.startsWith("Bearer ") || !url || !anon) return false;
  try {
    const r = await fetch(`${url}/auth/v1/user`, { headers: { Authorization: auth, apikey: anon } });
    if (!r.ok) return false;
    const u = await r.json();
    return !!(u && u.id);
  } catch {
    return false;
  }
}

async function leerJson(r: Response): Promise<unknown> {
  const texto = await r.text();
  try { return JSON.parse(texto); } catch { return { textoSinFormato: texto.slice(0, 2000) }; }
}

async function pedir(ruta: string, token: string): Promise<{ ok: boolean; estado: number; datos: unknown }> {
  try {
    const r = await fetch(API + ruta, {
      headers: { "Auth-Token": `Bearer ${token}`, Accept: "application/json" },
      signal: AbortSignal.timeout(25000),
    });
    return { ok: r.ok, estado: r.status, datos: await leerJson(r) };
  } catch (e) {
    return { ok: false, estado: 0, datos: { error: String(e) } };
  }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return responder({ ok: false, mensaje: "Método no permitido" }, 405);

  if (!(await usuarioValido(req))) {
    return responder({ ok: false, mensaje: "Inicia sesión con tu cuenta de MotoContable." }, 401);
  }

  let cuerpo: Record<string, unknown> = {};
  try { cuerpo = await req.json(); } catch { /* cuerpo vacío */ }
  const accion = String(cuerpo.accion || "");

  // ── 1. Captcha nuevo ──────────────────────────────────────────────────────
  if (accion === "captcha") {
    try {
      const r = await fetch(`${API}/captcha/libre-captcha/generar`, { signal: AbortSignal.timeout(20000) });
      const d = (await leerJson(r)) as Record<string, unknown>;
      if (!r.ok || !d.id || !d.imagen) {
        return responder({ ok: false, mensaje: "El RUNT no entregó el captcha. Intenta de nuevo." }, 502);
      }
      return responder({ ok: true, id: d.id, imagen: d.imagen });
    } catch {
      return responder({ ok: false, mensaje: "No se pudo conectar con el RUNT. Intenta de nuevo." }, 502);
    }
  }

  // ── 2. Consulta completa ─────────────────────────────────────────────────
  if (accion === "consultar") {
    const placa = String(cuerpo.placa || "").toUpperCase().replace(/[^A-Z0-9]/g, "");
    const documento = String(cuerpo.documento || "").replace(/[^0-9A-Za-z]/g, "");
    const tipoDocumento = String(cuerpo.tipoDocumento || "C");
    const captcha = String(cuerpo.captcha || "").trim();
    const idLibreCaptcha = String(cuerpo.idLibreCaptcha || "");

    if (!/^[A-Z0-9]{5,7}$/.test(placa)) return responder({ ok: false, mensaje: "Revisa la placa." }, 400);
    if (!documento || documento.length > 15) return responder({ ok: false, mensaje: "Revisa el número de documento." }, 400);
    if (!TIPOS_DOC.includes(tipoDocumento)) return responder({ ok: false, mensaje: "Tipo de documento no válido." }, 400);
    if (!captcha || captcha.length > 20 || !idLibreCaptcha) {
      return responder({ ok: false, mensaje: "Escribe el captcha." }, 400);
    }

    // Lo mismo que envía la página oficial en "Consulta ciudadana → Placa y propietario".
    const datosAuth = {
      procedencia: "NACIONAL",
      tipoConsulta: "1",
      placa,
      tipoDocumento,
      documento,
      vin: null,
      soat: null,
      aseguradora: "",
      rtm: null,
      reCaptcha: null,
      captcha,
      valueCaptchaEncripted: "",
      idLibreCaptcha,
      verBannerSoat: true,
      configuracion: { tiempoInactividad: "900", tiempoCuentaRegresiva: "10" },
    };

    let vehiculo: Record<string, unknown>;
    try {
      const r = await fetch(`${API}/auth`, {
        method: "POST",
        headers: { "Content-Type": "application/json", Accept: "application/json" },
        body: JSON.stringify(datosAuth),
        signal: AbortSignal.timeout(30000),
      });
      vehiculo = (await leerJson(r)) as Record<string, unknown>;
      const conError = vehiculo.error === true || vehiculo.error === "true" || vehiculo.error === "True";
      if (!r.ok || conError || !vehiculo.token) {
        const msg = String(vehiculo.descripcionRespuesta || vehiculo.mensaje || "El RUNT no devolvió información.");
        const esCaptcha = /captcha/i.test(msg);
        return responder({ ok: false, captchaMalo: esCaptcha, mensaje: msg }, 200);
      }
    } catch {
      return responder({ ok: false, mensaje: "No se pudo conectar con el RUNT. Intenta de nuevo." }, 502);
    }

    const token = String(vehiculo.token);
    const [soat, rtm, limitaciones, prendas, garantias, solicitudes, datosTecnicos] = await Promise.all([
      pedir("/soat", token),
      pedir("/rtms?tipo=N", token),
      pedir("/limitaciones-propiedad", token),
      pedir("/garantias/prendas", token),
      pedir("/garantias", token),
      pedir("/solicitudes", token),
      pedir("/datos-tecnicos", token),
    ]);

    // El token es de un solo uso para esta consulta: no se devuelve.
    delete vehiculo.token;

    return responder({
      ok: true,
      consultadoEn: new Date().toISOString(),
      placa,
      tipoDocumento,
      documento,
      vehiculo,
      soat,
      rtm,
      limitaciones,
      prendas,
      garantias,
      solicitudes,
      datosTecnicos,
    });
  }

  return responder({ ok: false, mensaje: "Acción desconocida." }, 400);
});
