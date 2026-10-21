-- ════════════════════════════════════════════════════════════════════════════
-- MotoContable · 09_aprobaciones.sql
-- Aprobación de las cuentas cobradas por la persona que paga en la financiera.
--
--  • Crea la tabla mc_aprobaciones: una fila por cada cuenta cobrada que se
--    envía con enlace de aprobación.
--  • Solo el dueño (con su sesión) ve y crea sus aprobaciones.
--  • Quien recibe el enlace NO necesita cuenta: abre la página aprobar.html y
--    solo puede hacer dos cosas, a través de dos funciones controladas:
--      - ver el resumen de ESA cuenta (nada más del negocio), y
--      - aprobarla o dejar una observación, escribiendo su cédula.
--    Si la cédula no coincide 5 veces, el enlace se bloquea.
--    Una vez respondida, la cuenta ya no se puede volver a cambiar desde el enlace.
--  • El enlace lleva un código aleatorio largo, imposible de adivinar.
--  • NO toca ninguna tabla ni dato existente (mc_registros, historial, fotos…).
--  • Se puede ejecutar más de una vez sin problema.
-- ════════════════════════════════════════════════════════════════════════════

begin;

create table if not exists public.mc_aprobaciones (
  token          text        primary key check (length(token) between 24 and 100),
  user_id        uuid        not null default auth.uid() references auth.users(id) on delete cascade,
  venta_id       text        not null check (length(venta_id) between 1 and 200),
  numero         integer,
  resumen        jsonb       not null default '{}'::jsonb check (jsonb_typeof(resumen) = 'object'),
  pagador_nombre text        not null default '',
  pagador_cc     text        not null default '',
  estado         text        not null default 'pendiente'
                 check (estado in ('pendiente','aprobada','observacion','anulada')),
  respuesta_cc   text,
  observacion    text        check (observacion is null or length(observacion) <= 1000),
  respondida_en  timestamptz,
  navegador      text,
  intentos       integer     not null default 0,
  creada_en      timestamptz not null default now()
);

create index if not exists mc_aprobaciones_user_idx on public.mc_aprobaciones (user_id, venta_id);

alter table public.mc_aprobaciones enable row level security;

-- El dueño ve las suyas. No hay políticas para escribir: todo pasa por las
-- funciones de abajo, que controlan qué se puede cambiar.
drop policy if exists mc_aprobaciones_ver on public.mc_aprobaciones;
create policy mc_aprobaciones_ver on public.mc_aprobaciones
  for select to authenticated using (user_id = auth.uid());

revoke all on public.mc_aprobaciones from anon;
revoke insert, update, delete on public.mc_aprobaciones from authenticated;
grant select on public.mc_aprobaciones to authenticated;

-- ── Dueño: crear la aprobación al enviar la cuenta ───────────────────────────
create or replace function public.mc_aprobacion_crear(
  p_token text, p_venta_id text, p_numero integer, p_resumen jsonb, p_nombre text, p_cc text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'Inicia sesión para crear aprobaciones'; end if;
  if p_token is null or length(p_token) < 24 then raise exception 'Código de aprobación inválido'; end if;
  if coalesce(regexp_replace(p_cc, '\D', '', 'g'), '') = '' then raise exception 'Falta la cédula de quien aprueba'; end if;
  -- Un envío nuevo de la misma cuenta deja sin efecto los enlaces anteriores sin responder
  update public.mc_aprobaciones set estado = 'anulada'
   where user_id = v_uid and venta_id = p_venta_id and estado = 'pendiente';
  insert into public.mc_aprobaciones (token, user_id, venta_id, numero, resumen, pagador_nombre, pagador_cc)
  values (p_token, v_uid, p_venta_id, p_numero, coalesce(p_resumen, '{}'::jsonb),
          left(coalesce(p_nombre, ''), 200), regexp_replace(p_cc, '\D', '', 'g'));
  return jsonb_build_object('ok', true, 'token', p_token);
end
$$;

-- ── Dueño: consultar cómo van sus aprobaciones ───────────────────────────────
create or replace function public.mc_aprobaciones_estado(p_tokens text[])
returns table (token text, venta_id text, numero integer, estado text, pagador_nombre text,
               respuesta_cc text, observacion text, respondida_en timestamptz, creada_en timestamptz)
language sql
stable
security definer
set search_path = ''
as $$
  select a.token, a.venta_id, a.numero, a.estado, a.pagador_nombre, a.respuesta_cc, a.observacion, a.respondida_en, a.creada_en
    from public.mc_aprobaciones a
   where a.user_id = auth.uid() and a.token = any(p_tokens);
$$;

-- ── Enlace: ver el resumen de la cuenta (sin sesión) ─────────────────────────
create or replace function public.mc_aprobacion_ver(p_token text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare a public.mc_aprobaciones%rowtype;
begin
  select * into a from public.mc_aprobaciones where token = p_token;
  if not found then return null; end if;
  return jsonb_build_object(
    'numero', a.numero, 'resumen', a.resumen, 'pagador', a.pagador_nombre,
    'estado', a.estado, 'respondida_en', a.respondida_en, 'observacion', a.observacion,
    'bloqueada', a.intentos >= 5);
end
$$;

-- ── Enlace: aprobar o dejar observación (sin sesión, con la cédula) ──────────
create or replace function public.mc_aprobacion_responder(
  p_token text, p_cc text, p_decision text, p_observacion text default null, p_navegador text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare a public.mc_aprobaciones%rowtype;
begin
  select * into a from public.mc_aprobaciones where token = p_token for update;
  if not found then return jsonb_build_object('ok', false, 'error', 'no_existe'); end if;
  if a.estado = 'anulada' then return jsonb_build_object('ok', false, 'error', 'anulada'); end if;
  if a.estado <> 'pendiente' then return jsonb_build_object('ok', false, 'error', 'respondida', 'estado', a.estado); end if;
  if a.intentos >= 5 then return jsonb_build_object('ok', false, 'error', 'bloqueada'); end if;
  if p_decision not in ('aprobada', 'observacion') then return jsonb_build_object('ok', false, 'error', 'decision'); end if;
  if regexp_replace(coalesce(p_cc, ''), '\D', '', 'g') <> a.pagador_cc then
    update public.mc_aprobaciones set intentos = intentos + 1 where token = p_token;
    return jsonb_build_object('ok', false, 'error', 'cedula', 'quedan', greatest(0, 4 - a.intentos));
  end if;
  if p_decision = 'observacion' and coalesce(trim(p_observacion), '') = '' then
    return jsonb_build_object('ok', false, 'error', 'falta_observacion');
  end if;
  update public.mc_aprobaciones
     set estado = p_decision,
         respuesta_cc = regexp_replace(p_cc, '\D', '', 'g'),
         observacion = case when p_decision = 'observacion' then left(trim(p_observacion), 1000) end,
         respondida_en = now(),
         navegador = left(coalesce(p_navegador, ''), 300)
   where token = p_token;
  return jsonb_build_object('ok', true, 'estado', p_decision, 'respondida_en', now());
end
$$;

revoke all on function public.mc_aprobacion_crear(text, text, integer, jsonb, text, text) from public, anon;
revoke all on function public.mc_aprobaciones_estado(text[]) from public, anon;
revoke all on function public.mc_aprobacion_ver(text) from public;
revoke all on function public.mc_aprobacion_responder(text, text, text, text, text) from public;
grant execute on function public.mc_aprobacion_crear(text, text, integer, jsonb, text, text) to authenticated;
grant execute on function public.mc_aprobaciones_estado(text[]) to authenticated;
grant execute on function public.mc_aprobacion_ver(text) to anon, authenticated;
grant execute on function public.mc_aprobacion_responder(text, text, text, text, text) to anon, authenticated;

commit;

-- Verificación: debe mostrar la tabla con RLS activado y las 4 funciones.
select relname, relrowsecurity from pg_class where relname = 'mc_aprobaciones';
select proname from pg_proc where proname like 'mc_aprobacion%' order by proname;
