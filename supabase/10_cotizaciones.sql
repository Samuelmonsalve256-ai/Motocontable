-- ════════════════════════════════════════════════════════════════════════════
-- MotoContable · 10_cotizaciones.sql
-- Permite guardar las Cotizaciones de crédito en la nube, en la misma tabla
-- mc_registros, con la misma seguridad (RLS), el mismo historial y las mismas
-- funciones de sincronización.
--
--  • Solo amplía la lista de colecciones permitidas con:
--      'cotizaciones' → las cotizaciones guardadas
--      'cot_motos'    → el catálogo de motos con su precio
--      'cot_config'   → los ajustes (empresa, planes, plazos) y los requisitos
--  • La lista nueva incluye también cualquier colección que ya exista en la
--    tabla, para que ningún registro actual quede por fuera de la regla.
--  • NO borra ni modifica ningún dato. Se puede ejecutar más de una vez.
-- ════════════════════════════════════════════════════════════════════════════

do $$
declare
  lista text;
begin
  select string_agg(quote_literal(c), ', ' order by c) into lista
  from (
    select unnest(array[
      'motos','movimientos','ventas','carros','contactos','metas','config',
      'traspasos','traspasos_borradores',
      'cotizaciones','cot_motos','cot_config']) as c
    union
    select distinct coleccion from public.mc_registros
  ) t;

  alter table public.mc_registros drop constraint if exists mc_registros_coleccion_check;
  execute 'alter table public.mc_registros add constraint mc_registros_coleccion_check '
       || 'check (coleccion in (' || lista || '))';
end $$;

-- Verificación: la regla nueva (debe incluir cotizaciones, cot_motos y cot_config)
select pg_get_constraintdef(oid) as regla
from pg_constraint
where conname = 'mc_registros_coleccion_check';

-- Cuántos registros hay por colección (solo para revisar)
select coleccion, count(*) as registros
from public.mc_registros
group by coleccion
order by coleccion;
