-- ════════════════════════════════════════════════════════════════════════════
-- MotoContable · 03_funciones.sql
-- Funciones que usa la app para sincronizar. Se puede ejecutar más de una vez.
--
--   mc_push(cambios, dispositivo) : envía cambios. Todo el lote se aplica en una
--                                   sola transacción (todo o nada) y con control
--                                   de versiones para no pisar datos más nuevos.
--   mc_pull(desde, limite)        : trae lo que cambió después de un número de orden.
--   mc_indice()                   : lista liviana (sin datos) para verificar que
--                                   un dispositivo no se haya saltado ningún cambio.
-- ════════════════════════════════════════════════════════════════════════════

begin;

-- ── mc_push ───────────────────────────────────────────────────────────────────
-- Cada elemento de p_cambios:
--   { "coleccion": "motos", "id": "id123", "data": {...},
--     "base_version": 3 | null, "eliminar": false, "modo": "normal" | "migracion" }
--
-- Reglas:
--   • No existe en la nube            → se crea (versión 1).
--   • La nube ya está igual           → no se hace nada (reintentos seguros).
--   • base_version = versión de nube  → se aplica (versión + 1; la anterior va al historial).
--   • Cualquier otro caso             → CONFLICTO: la nube se conserva como principal y el
--                                       cambio del dispositivo se guarda en mc_historial.
--   • modo 'migracion'                → nunca sobrescribe: si difiere, va al historial.
create or replace function public.mc_push(p_cambios jsonb, p_device text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid        uuid := auth.uid();
  c            jsonb;
  v_col        text;
  v_id         text;
  v_base       bigint;
  v_borrar     boolean;
  v_data       jsonb;
  v_modo       text;
  r            public.mc_registros%rowtype;
  v_aplicados  jsonb := '[]'::jsonb;
  v_conflictos jsonb := '[]'::jsonb;
begin
  if v_uid is null then
    raise exception 'Debes iniciar sesión' using errcode = '42501';
  end if;
  if p_cambios is null or jsonb_typeof(p_cambios) <> 'array' then
    raise exception 'p_cambios debe ser un arreglo';
  end if;
  if jsonb_array_length(p_cambios) > 500 then
    raise exception 'Máximo 500 cambios por envío';
  end if;

  for c in select value from jsonb_array_elements(p_cambios) loop
    v_col    := c->>'coleccion';
    v_id     := c->>'id';
    v_base   := nullif(c->>'base_version', '')::bigint;
    v_borrar := coalesce((c->>'eliminar')::boolean, false);
    v_data   := c->'data';
    v_modo   := coalesce(c->>'modo', 'normal');

    if v_col is null or v_id is null or v_id = '' then
      raise exception 'Cambio sin colección o sin id';
    end if;
    if v_modo not in ('normal', 'migracion') then
      raise exception 'Modo desconocido: %', v_modo;
    end if;
    if not v_borrar and (v_data is null or jsonb_typeof(v_data) <> 'object') then
      raise exception 'Cambio sin datos: %/%', v_col, v_id;
    end if;

    select * into r
    from public.mc_registros
    where user_id = v_uid and coleccion = v_col and id = v_id
    for update;

    -- 1) No existe en la nube
    if not found then
      if v_borrar then
        v_aplicados := v_aplicados || jsonb_build_object(
          'coleccion', v_col, 'id', v_id, 'version', null, 'seq', null,
          'eliminado', true, 'resultado', 'inexistente');
        continue;
      end if;
      insert into public.mc_registros (user_id, coleccion, id, data, device_id)
      values (v_uid, v_col, v_id, v_data, p_device)
      returning * into r;
      v_aplicados := v_aplicados || jsonb_build_object(
        'coleccion', r.coleccion, 'id', r.id, 'version', r.version, 'seq', r.seq,
        'eliminado', false, 'resultado', 'creado');
      continue;
    end if;

    -- 2) La nube ya está como el dispositivo quiere (reintento o mismo dato)
    if (v_borrar and r.deleted_at is not null)
       or (not v_borrar and r.deleted_at is null and r.data = v_data) then
      v_aplicados := v_aplicados || jsonb_build_object(
        'coleccion', r.coleccion, 'id', r.id, 'version', r.version, 'seq', r.seq,
        'eliminado', r.deleted_at is not null, 'resultado', 'sin_cambios');
      continue;
    end if;

    -- 3) El dispositivo conocía la última versión → se aplica
    if v_modo = 'normal' and v_base is not null and v_base = r.version then
      update public.mc_registros
         set data       = case when v_borrar then data else v_data end,
             deleted_at = case when v_borrar then now() else null end,
             device_id  = p_device
       where user_id = v_uid and coleccion = v_col and id = v_id
      returning * into r;
      v_aplicados := v_aplicados || jsonb_build_object(
        'coleccion', r.coleccion, 'id', r.id, 'version', r.version, 'seq', r.seq,
        'eliminado', r.deleted_at is not null,
        'resultado', case when v_borrar then 'eliminado' else 'actualizado' end);
      continue;
    end if;

    -- 4) Conflicto: la nube gana; el cambio del dispositivo queda en el historial
    insert into public.mc_historial (user_id, coleccion, id, data, version, deleted_at, motivo, device_id)
    values (v_uid, v_col, v_id, v_data, v_base,
            case when v_borrar then now() end,
            case when v_modo = 'migracion' then 'migracion' else 'conflicto' end,
            p_device);

    v_conflictos := v_conflictos || jsonb_build_object(
      'coleccion', r.coleccion, 'id', r.id,
      'data', case when r.deleted_at is null then r.data end,
      'version', r.version, 'seq', r.seq, 'created_at', r.created_at,
      'eliminado', r.deleted_at is not null,
      'motivo', case when v_modo = 'migracion' then 'migracion' else 'conflicto' end);
  end loop;

  return jsonb_build_object('aplicados', v_aplicados, 'conflictos', v_conflictos);
end
$$;

-- ── mc_pull ───────────────────────────────────────────────────────────────────
create or replace function public.mc_pull(p_desde bigint default 0, p_limite integer default 200)
returns table (
  coleccion  text,
  id         text,
  data       jsonb,
  version    bigint,
  seq        bigint,
  created_at timestamptz,
  eliminado  boolean
)
language sql
stable
security invoker
set search_path = ''
as $$
  select r.coleccion, r.id,
         case when r.deleted_at is null then r.data end,
         r.version, r.seq, r.created_at, r.deleted_at is not null
  from public.mc_registros r
  where r.user_id = auth.uid()
    and r.seq > coalesce(p_desde, 0)
  order by r.seq
  limit least(greatest(coalesce(p_limite, 200), 1), 1000);
$$;

-- ── mc_indice ─────────────────────────────────────────────────────────────────
create or replace function public.mc_indice()
returns table (
  coleccion text,
  id        text,
  version   bigint,
  seq       bigint,
  eliminado boolean
)
language sql
stable
security invoker
set search_path = ''
as $$
  select r.coleccion, r.id, r.version, r.seq, r.deleted_at is not null
  from public.mc_registros r
  where r.user_id = auth.uid();
$$;

-- Solo usuarios con sesión pueden llamar estas funciones.
revoke all on function public.mc_push(jsonb, text)     from public, anon;
revoke all on function public.mc_pull(bigint, integer) from public, anon;
revoke all on function public.mc_indice()              from public, anon;
grant execute on function public.mc_push(jsonb, text)     to authenticated;
grant execute on function public.mc_pull(bigint, integer) to authenticated;
grant execute on function public.mc_indice()              to authenticated;

-- ── Tiempo real: avisar a los otros dispositivos cuando algo cambia ───────────
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (select 1 from pg_publication_tables
                     where pubname = 'supabase_realtime'
                       and schemaname = 'public' and tablename = 'mc_registros') then
    alter publication supabase_realtime add table public.mc_registros;
  end if;
end
$$;

commit;
