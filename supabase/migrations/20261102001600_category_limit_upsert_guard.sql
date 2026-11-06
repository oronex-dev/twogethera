-- Support atomic category-limit upserts while keeping row identity immutable.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';
GRANT CREATE ON SCHEMA app_private TO twogethera_membership_owner;
SET LOCAL ROLE twogethera_membership_owner;

CREATE FUNCTION app_private.guard_budget_category_limit()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $function$
BEGIN
  IF TG_OP = 'INSERT' THEN
    NEW.created_at := statement_timestamp();
    NEW.updated_at := NEW.created_at;
    NEW.revision := 1;
  ELSE
    IF OLD.id IS DISTINCT FROM NEW.id
       OR OLD.couple_id IS DISTINCT FROM NEW.couple_id
       OR OLD.budget_id IS DISTINCT FROM NEW.budget_id
       OR OLD.category_key IS DISTINCT FROM NEW.category_key
       OR OLD.created_at IS DISTINCT FROM NEW.created_at
       OR OLD.revision IS DISTINCT FROM NEW.revision THEN
      RAISE EXCEPTION 'category limit identity is immutable' USING ERRCODE = '42501';
    END IF;
    NEW.updated_at := statement_timestamp();
    NEW.revision := OLD.revision + 1;
  END IF;
  RETURN NEW;
END
$function$;
ALTER FUNCTION app_private.guard_budget_category_limit() OWNER TO twogethera_membership_owner;
CREATE TRIGGER budget_category_limits_guard
BEFORE INSERT OR UPDATE ON public.budget_category_limits
FOR EACH ROW EXECUTE FUNCTION app_private.guard_budget_category_limit();

RESET ROLE;
REVOKE CREATE ON SCHEMA app_private FROM twogethera_membership_owner;
REVOKE ALL ON FUNCTION app_private.guard_budget_category_limit() FROM PUBLIC, anon, authenticated, service_role;
GRANT UPDATE (couple_id,budget_id,category_key,limit_minor)
ON public.budget_category_limits TO authenticated;
COMMIT;
