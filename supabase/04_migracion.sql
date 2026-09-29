-- ════════════════════════════════════════════════════════════════════════════
-- MotoContable · 04_migracion.sql
-- Copia los datos de la tabla antigua mc_datos a la tabla nueva mc_registros.
--
--  • NO modifica ni borra mc_datos.
--  • Primero guarda una copia exacta de mc_datos en mc_datos_respaldo_pre_migracion.
--  • Se puede ejecutar más de una vez: lo que ya se copió no se duplica ni se pisa.
--
-- ANTES DE EJECUTAR: cambia PON_AQUI_TU_CORREO (más abajo, en la PARTE B) por el
-- correo con el que creaste tu usuario en Authentication → Users.
-- ════════════════════════════════════════════════════════════════════════════

-- ── PARTE A: respaldo exacto de la tabla antigua ──────────────────────────────
-- Si ya existe (porque ejecutaste este archivo antes) no se toca: conserva la
-- copia original.
create table if not exists public.mc_datos_respaldo_pre_migracion as
  select * from public.mc_datos;

-- El respaldo no debe quedar visible con la clave pública.
alter table public.mc_datos_respaldo_pre_migracion enable row level security;
revoke all on table public.mc_datos_respaldo_pre_migracion from public, anon, authenticated;

-- ── PARTE B: copiar a mc_registros ────────────────────────────────────────────
do $$
declare
  v_email  text := 'samuelmonsalve256@gmail.com';   -- ← CAMBIA ESTO
  v_uid    uuid;
  v_fila   jsonb;
  v_col    text;
  v_arr    jsonb;
  v_elem   jsonb;
  v_ord    bigint;
  v_len    bigint;
  v_id     text;
  v_filas  integer;
  v_nuevos integer;
  v_base   timestamptz := now();
begin
  if v_email = 'PON_AQUI_TU_CORREO' then
    raise exception 'Falta tu correo: cambia PON_AQUI_TU_CORREO en la PARTE B de este archivo.';
  end if;

  select u.id into v_uid from auth.users u where lower(u.email) = lower(trim(v_email));
  if v_uid is null then
    raise exception 'No existe un usuario con el correo "%". Créalo primero en Authentication → Users y revisa que esté bien escrito.', v_email;
  end if;

  select to_jsonb(d) into v_fila from public.mc_datos d where d.id::text = 'principal';
  if v_fila is null then
    raise notice 'mc_datos no tiene la fila "principal": no hay nada que copiar.';
    return;
  end if;

  foreach v_col in array array['motos','movimientos','ventas','carros','contactos','metas'] loop
    v_arr := v_fila -> v_col;
    -- Por si la columna guardó el arreglo como texto
    if v_arr is not null and jsonb_typeof(v_arr) = 'string' then
      v_arr := (v_arr #>> '{}')::jsonb;
    end if;
    if v_arr is null or jsonb_typeof(v_arr) <> 'array' then
      raise notice '%: 0 elementos', v_col;
      continue;
    end if;

    v_len    := jsonb_array_length(v_arr);
    v_nuevos := 0;

    for v_elem, v_ord in
      select e.value, e.ordinality from jsonb_array_elements(v_arr) with ordinality e
    loop
      if jsonb_typeof(v_elem) <> 'object' then continue; end if;

      v_id := nullif(v_elem ->> 'id', '');
      if v_id is null then
        -- Elemento antiguo sin id: se le asigna uno estable para poder sincronizarlo
        v_id   := 'mig_' || md5(v_col || v_elem::text);
        v_elem := v_elem || jsonb_build_object('id', v_id);
      end if;

      -- created_at conserva el orden en que la app mostraba la lista:
      -- motos, carros, contactos y metas tienen lo más nuevo primero;
      -- ventas y movimientos tienen lo más nuevo al final.
      insert into public.mc_registros (user_id, coleccion, id, data, device_id, created_at)
      values (v_uid, v_col, v_id, v_elem, 'migracion-sql',
              v_base - interval '1 millisecond' *
                case when v_col in ('ventas','movimientos') then v_len - v_ord else v_ord end)
      on conflict (user_id, coleccion, id) do nothing;

      get diagnostics v_filas = row_count;
      if v_filas > 0 then
        v_nuevos := v_nuevos + 1;
        insert into public.mc_historial (user_id, coleccion, id, data, version, motivo, device_id)
        values (v_uid, v_col, v_id, v_elem, 1, 'migracion', 'migracion-sql');
      end if;
    end loop;

    raise notice '%: % elementos en mc_datos, % copiados ahora', v_col, v_len, v_nuevos;
  end loop;
end
$$;

-- ── PARTE C: verificación ─────────────────────────────────────────────────────
-- Compara estos números con la consulta 5 de 00_diagnostico.sql.
select coleccion, count(*) as registros
from public.mc_registros
where deleted_at is null
group by coleccion
order by coleccion;
