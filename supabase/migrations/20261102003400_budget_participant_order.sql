-- Permit either split ordering while requiring the exact current active pair.
-- The existing guard remains responsible for all other financial invariants.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

GRANT CREATE ON SCHEMA app_private TO twogethera_membership_owner;
SET LOCAL ROLE twogethera_membership_owner;

CREATE OR REPLACE FUNCTION app_private.guard_financial_row()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_actor uuid;
  v_budget public.couple_budgets%ROWTYPE;
  v_seat1 uuid;
  v_seat2 uuid;
BEGIN
  IF TG_OP = 'UPDATE' AND TG_TABLE_NAME = 'couple_expenses' THEN
    IF app_private.current_request_role() = 'service_role'
       AND current_setting('app_private.lifecycle_membership_purge', true) = 'on'
       AND OLD.recurring_rule_id IS NOT NULL
       AND NEW.recurring_rule_id IS NULL
       AND NEW.recurrence_key IS NULL THEN
      IF (to_jsonb(OLD) - ARRAY['recurring_rule_id','recurrence_key','revision','updated_at','updated_by'])
         IS DISTINCT FROM
         (to_jsonb(NEW) - ARRAY['recurring_rule_id','recurrence_key','revision','updated_at','updated_by']) THEN
        RAISE EXCEPTION 'invalid lifecycle relationship cleanup' USING ERRCODE = '42501';
      END IF;
      NEW.updated_at := statement_timestamp();
      NEW.revision := OLD.revision + 1;
      NEW.updated_by := OLD.updated_by;
      RETURN NEW;
    END IF;
  END IF;

  v_actor := app_private.current_identity_is_verified(false);
  IF TG_OP = 'INSERT' THEN
    NEW.created_by := v_actor;
    IF TG_TABLE_NAME = 'couple_expenses' THEN
      NEW.updated_by := v_actor;
    END IF;
    NEW.created_at := statement_timestamp();
    NEW.updated_at := NEW.created_at;
    NEW.revision := 1;
  ELSE
    IF OLD.id IS DISTINCT FROM NEW.id
       OR OLD.couple_id IS DISTINCT FROM NEW.couple_id
       OR OLD.created_by IS DISTINCT FROM NEW.created_by
       OR OLD.created_at IS DISTINCT FROM NEW.created_at
       OR OLD.revision IS DISTINCT FROM NEW.revision THEN
      RAISE EXCEPTION 'expense identity is server controlled' USING ERRCODE = '42501';
    END IF;
    IF TG_TABLE_NAME = 'couple_expenses' AND OLD.budget_id IS DISTINCT FROM NEW.budget_id THEN
      RAISE EXCEPTION 'expense budget is immutable' USING ERRCODE = '42501';
    END IF;
    IF TG_TABLE_NAME = 'couple_expenses' THEN
      NEW.updated_by := v_actor;
    END IF;
    NEW.updated_at := statement_timestamp();
    NEW.revision := OLD.revision + 1;
  END IF;

  IF TG_TABLE_NAME = 'couple_expenses' THEN
    SELECT * INTO v_budget
    FROM public.couple_budgets
    WHERE id = NEW.budget_id AND couple_id = NEW.couple_id;
    IF NOT FOUND
       OR (v_budget.currency_code, v_budget.currency_exponent)
          IS DISTINCT FROM (NEW.currency_code, NEW.currency_exponent)
       OR date_trunc('month', NEW.occurred_on)::date IS DISTINCT FROM v_budget.month_start THEN
      RAISE EXCEPTION 'expense must match its budget' USING ERRCODE = '23514';
    END IF;
    IF NEW.split_mode = 'equal'
       AND (NEW.split_a_minor <> NEW.amount_minor / 2
            OR NEW.split_b_minor <> NEW.amount_minor - NEW.split_a_minor) THEN
      RAISE EXCEPTION 'invalid equal split' USING ERRCODE = '23514';
    END IF;
  END IF;

  SELECT user_id INTO v_seat1
  FROM public.couple_memberships
  WHERE couple_id = NEW.couple_id AND seat = 1 AND state = 'active';
  SELECT user_id INTO v_seat2
  FROM public.couple_memberships
  WHERE couple_id = NEW.couple_id AND seat = 2 AND state = 'active';

  IF v_seat1 IS NULL
     OR v_seat2 IS NULL
     OR v_seat1 = v_seat2
     OR NEW.split_a_user_id IS NULL
     OR NEW.split_b_user_id IS NULL
     OR NEW.split_a_user_id = NEW.split_b_user_id
     OR NOT (
       (NEW.split_a_user_id = v_seat1 AND NEW.split_b_user_id = v_seat2)
       OR (NEW.split_a_user_id = v_seat2 AND NEW.split_b_user_id = v_seat1)
     )
     OR NEW.paid_by_user IS NULL
     OR NEW.paid_by_user NOT IN (v_seat1, v_seat2) THEN
    RAISE EXCEPTION 'expense participants must be current couple members'
      USING ERRCODE = '42501';
  END IF;

  IF NEW.split_a_minor + NEW.split_b_minor <> NEW.amount_minor THEN
    RAISE EXCEPTION 'split must equal expense amount' USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END
$function$;

REVOKE ALL ON FUNCTION app_private.guard_financial_row()
  FROM PUBLIC, anon, authenticated, service_role;

RESET ROLE;
REVOKE CREATE ON SCHEMA app_private FROM twogethera_membership_owner;

COMMIT;
NOTIFY pgrst, 'reload schema';
