-- ════════════════════════════════════════════════════════════════════════════
-- MotoContable · 00_diagnostico.sql
-- SOLO LECTURA. No crea, no cambia y no borra nada.
--
-- Muestra cómo está hoy tu proyecto de Supabase: qué tablas existen, si la
-- tabla antigua mc_datos tiene seguridad (RLS) y cuántos registros guarda.
-- Guarda (copia/pega o captura de pantalla) el resultado de cada consulta
-- antes de seguir con los demás archivos.
-- ════════════════════════════════════════════════════════════════════════════

-- 1) Tablas que existen en el esquema public
select table_name
from information_schema.tables
where table_schema = 'public'
order by table_name;

-- 2) Columnas de la tabla antigua mc_datos
select column_name, data_type
from information_schema.columns
where table_schema = 'public' and table_name = 'mc_datos'
order by ordinal_position;

-- 3) ¿Tiene RLS activado cada tabla mc_*?
select c.relname as tabla, c.relrowsecurity as rls_activado
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public' and c.relkind = 'r' and c.relname like 'mc\_%'
order by c.relname;

-- 4) Políticas actuales de mc_datos (GUARDA ESTE RESULTADO)
select policyname, roles, cmd, qual, with_check
from pg_policies
where schemaname = 'public' and tablename = 'mc_datos';

-- 5) Cuántos elementos hay en cada lista de la fila 'principal'
select
  d.id,
  to_jsonb(d) ->> 'updated_at' as ultima_actualizacion,
  (select count(*) from jsonb_array_elements(
     case jsonb_typeof(to_jsonb(d)->'motos')       when 'array' then to_jsonb(d)->'motos'       else '[]'::jsonb end)) as motos,
  (select count(*) from jsonb_array_elements(
     case jsonb_typeof(to_jsonb(d)->'movimientos') when 'array' then to_jsonb(d)->'movimientos' else '[]'::jsonb end)) as movimientos,
  (select count(*) from jsonb_array_elements(
     case jsonb_typeof(to_jsonb(d)->'ventas')      when 'array' then to_jsonb(d)->'ventas'      else '[]'::jsonb end)) as ventas,
  (select count(*) from jsonb_array_elements(
     case jsonb_typeof(to_jsonb(d)->'carros')      when 'array' then to_jsonb(d)->'carros'      else '[]'::jsonb end)) as carros,
  (select count(*) from jsonb_array_elements(
     case jsonb_typeof(to_jsonb(d)->'contactos')   when 'array' then to_jsonb(d)->'contactos'   else '[]'::jsonb end)) as contactos,
  (select count(*) from jsonb_array_elements(
     case jsonb_typeof(to_jsonb(d)->'metas')       when 'array' then to_jsonb(d)->'metas'       else '[]'::jsonb end)) as metas
from public.mc_datos d;
