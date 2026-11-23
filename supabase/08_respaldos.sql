-- ════════════════════════════════════════════════════════════════════════════
-- MotoContable · 08_respaldos.sql
-- Respaldo semanal automático en la nube, aparte de la sincronización.
-- Si algo se borra por error, desde Ajustes se recupera lo que faltaba.
--
--  • Crea el "bucket" (carpeta de archivos) llamado 'respaldos', PRIVADO:
--    nadie puede verlo sin iniciar sesión.
--  • Cada usuario solo puede ver, guardar y borrar los respaldos de SU carpeta
--    (la carpeta lleva el id del usuario). Nadie más los ve.
--  • Solo archivos .json de hasta 50 MB (la app guarda los datos, no las fotos:
--    las fotos ya están en el bucket 'fotos').
--  • NO toca ninguna tabla ni dato existente (mc_registros, historial, fotos…).
--  • Se puede ejecutar más de una vez sin problema.
-- ════════════════════════════════════════════════════════════════════════════

begin;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('respaldos', 'respaldos', false, 52428800, array['application/json'])
on conflict (id) do update
  set public = false,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists mc_respaldos_ver     on storage.objects;
drop policy if exists mc_respaldos_subir   on storage.objects;
drop policy if exists mc_respaldos_cambiar on storage.objects;
drop policy if exists mc_respaldos_borrar  on storage.objects;

create policy mc_respaldos_ver on storage.objects
  for select to authenticated
  using (bucket_id = 'respaldos' and (storage.foldername(name))[1] = auth.uid()::text);

create policy mc_respaldos_subir on storage.objects
  for insert to authenticated
  with check (bucket_id = 'respaldos' and (storage.foldername(name))[1] = auth.uid()::text);

create policy mc_respaldos_cambiar on storage.objects
  for update to authenticated
  using (bucket_id = 'respaldos' and (storage.foldername(name))[1] = auth.uid()::text)
  with check (bucket_id = 'respaldos' and (storage.foldername(name))[1] = auth.uid()::text);

create policy mc_respaldos_borrar on storage.objects
  for delete to authenticated
  using (bucket_id = 'respaldos' and (storage.foldername(name))[1] = auth.uid()::text);

commit;

-- Verificación: debe mostrar el bucket 'respaldos' (public = false) y 4 políticas.
select id, public, file_size_limit from storage.buckets where id = 'respaldos';
select policyname, cmd from pg_policies
where schemaname = 'storage' and tablename = 'objects' and policyname like 'mc_respaldos_%'
order by policyname;
