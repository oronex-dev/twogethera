-- Allow only the non-login membership owner used by cleanup RPCs to check
-- whether protected media still exists; no authenticated client gets this
-- policy or direct table access.
BEGIN;
CREATE POLICY private_attachment_presence_check ON storage.objects
FOR SELECT TO twogethera_membership_owner
USING (bucket_id IN ('couple-memories', 'couple-receipts'));
COMMIT;
