-- ════════════════════════════════════════════════════════════════════════════
-- MotoContable · 01_esquema.sql
-- Crea las tablas nuevas. NO toca la tabla antigua mc_datos.
-- Se puede ejecutar más de una vez sin problema (no borra nada).
--
--   mc_registros : un registro por moto, venta, movimiento, carro, contacto,
--                  meta y la configuración. Es la fuente principal de datos.
--   mc_historial : copia de cada versión anterior, de cada eliminación y de
--                  cada cambio que perdió un conflicto. Nada se pierde.
-- ════════════════════════════════════════════════════════════════════════════

begin;

-- Orden global de cambios: cada escritura recibe un número mayor que el anterior.
-- Los dispositivos piden "todo lo que cambió después del número X".
create sequence if not exists public.mc_seq;

create table if not exists public.mc_registros (
  user_id    uuid        not null default auth.uid() references auth.users(id) on delete cascade,
  coleccion  text        not null check (coleccion in
               ('motos','movimientos','ventas','carros','contactos','metas','config')),
  id         text        not null check (length(id) between 1 and 200),
  data       jsonb       not null check (jsonb_typeof(data) = 'object'),
  version    bigint      not null,
  seq        bigint      not null,
  deleted_at timestamptz,
  device_id  text,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  primary key (user_id, coleccion, id)
);

create index if not exists mc_registros_user_seq_idx
  on public.mc_registros (user_id, seq);

create table if not exists public.mc_historial (
  hist_id     bigserial   primary key,
  user_id     uuid        not null references auth.users(id) on delete cascade,
  coleccion   text        not null,
  id          text        not null,
  data        jsonb,
  version     bigint,
  deleted_at  timestamptz,
  -- 'edicion'     : versión anterior a una edición
  -- 'eliminacion' : versión anterior a una eliminación
  -- 'conflicto'   : cambio de un dispositivo que llegó con una versión vieja
  -- 'migracion'   : dato local que difería de la nube al migrar, o copia de la migración SQL
  motivo      text        not null check (motivo in ('edicion','eliminacion','conflicto','migracion')),
  device_id   text,       -- dispositivo que originó esta entrada
  guardado_en timestamptz not null default now()
);

create index if not exists mc_historial_user_idx
  on public.mc_historial (user_id, coleccion, id, guardado_en desc);

-- ── Disparador al crear: versión 1, número de orden y fechas ──────────────────
create or replace function public.mc_registros_antes_insert()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  new.version    := 1;
  new.seq        := nextval('public.mc_seq');
  new.created_at := coalesce(new.created_at, clock_timestamp());
  new.updated_at := now();
  return new;
end
$$;

-- ── Disparador al modificar: guarda la versión anterior en el historial ───────
create or replace function public.mc_registros_antes_update()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.user_id <> old.user_id or new.coleccion <> old.coleccion or new.id <> old.id then
    raise exception 'No se puede cambiar el dueño, la colección ni el id de un registro';
  end if;

  insert into public.mc_historial (user_id, coleccion, id, data, version, deleted_at, motivo, device_id)
  values (old.user_id, old.coleccion, old.id, old.data, old.version, old.deleted_at,
          case when new.deleted_at is not null and old.deleted_at is null
               then 'eliminacion' else 'edicion' end,
          new.device_id);

  new.version    := old.version + 1;
  new.seq        := nextval('public.mc_seq');
  new.created_at := old.created_at;
  new.updated_at := now();
  return new;
end
$$;

drop trigger if exists mc_registros_antes_insert on public.mc_registros;
create trigger mc_registros_antes_insert
  before insert on public.mc_registros
  for each row execute function public.mc_registros_antes_insert();

drop trigger if exists mc_registros_antes_update on public.mc_registros;
create trigger mc_registros_antes_update
  before update on public.mc_registros
  for each row execute function public.mc_registros_antes_update();

-- Las funciones de disparador no se llaman directamente.
revoke all on function public.mc_registros_antes_insert() from public, anon, authenticated;
revoke all on function public.mc_registros_antes_update() from public, anon, authenticated;

commit;
