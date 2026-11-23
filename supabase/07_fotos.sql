-- ════════════════════════════════════════════════════════════════════════════
-- MotoContable · 07_fotos.sql
-- Guarda las fotos de motos y carros en Supabase Storage (archivos), en vez de
-- dentro de los datos. Así el sistema no se llena y todas las fotos quedan en
-- la nube.
--
--  • Crea el "bucket" (carpeta de archivos) llamado 'fotos', PRIVADO:
--    nadie puede ver las fotos sin iniciar sesión.
--  • Cada usuario solo puede ver, subir y cambiar las fotos de SU carpeta
--    (la carpeta lleva el id del usuario). Nadie más las ve.
--  • Límite de 5 MB por foto y solo imágenes (la app las comprime antes).
--  • NO toca ninguna tabla ni dato existente (mc_registros, historial, etc.).
--  • Se puede ejecutar más de una vez sin problema.
-- ════════════════════════════════════════════════════════════════════════════

begin;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('fotos', 'fotos', false, 5242880, array['image/jpeg','image/png','image/webp'])
on conflict (id) do update
  set public = false,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists mc_fotos_ver     on storage.objects;
drop policy if exists mc_fotos_subir   on storage.objects;
drop policy if exists mc_fotos_cambiar on storage.objects;
drop policy if exists mc_fotos_borrar  on storage.objects;

create policy mc_fotos_ver on storage.objects
  for select to authenticated
  using (bucket_id = 'fotos' and (storage.foldername(name))[1] = auth.uid()::text);

create policy mc_fotos_subir on storage.objects
  for insert to authenticated
  with check (bucket_id = 'fotos' and (storage.foldername(name))[1] = auth.uid()::text);

create policy mc_fotos_cambiar on storage.objects
  for update to authenticated
  using (bucket_id = 'fotos' and (storage.foldername(name))[1] = auth.uid()::text)
  with check (bucket_id = 'fotos' and (storage.foldername(name))[1] = auth.uid()::text);

create policy mc_fotos_borrar on storage.objects
  for delete to authenticated
  using (bucket_id = 'fotos' and (storage.foldername(name))[1] = auth.uid()::text);

commit;

-- Verificación: debe mostrar el bucket 'fotos' (public = false) y 4 políticas.
select id, public, file_size_limit from storage.buckets where id = 'fotos';
select policyname, cmd from pg_policies
where schemaname = 'storage' and tablename = 'objects' and policyname like 'mc_fotos_%'
order by policyname;
