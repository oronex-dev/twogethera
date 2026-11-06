-- CP-009A: keep profile-photo deletion on the same verified owner path as
-- upload/update. The authenticated role must not call private identity helpers
-- directly from Storage policy expressions.
BEGIN;

DROP POLICY profile_photos_owner_delete ON storage.objects;
CREATE POLICY profile_photos_owner_delete
  ON storage.objects FOR DELETE TO authenticated
  USING (
    bucket_id = 'profile-photos'
    AND app_private.can_write_profile_photo(name)
  );

COMMIT;
