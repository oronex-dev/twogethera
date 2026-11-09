-- Keep recurring-rule updates from evaluating expense-only record fields.
-- The shared trigger function guards both recurring rules and expenses.
BEGIN;

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
      RAISE EXCEPTION 'expense identity is server controlled'
        USING ERRCODE = '42501';
    END IF;
    IF TG_TABLE_NAME = 'couple_expenses' THEN
      IF OLD.budget_id IS DISTINCT FROM NEW.budget_id THEN
        RAISE EXCEPTION 'expense budget is immutable'
          USING ERRCODE = '42501';
      END IF;
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
          IS DISTINCT FROM (NEW.currency_code, NEW.currency_exponent) THEN
      RAISE EXCEPTION 'expense currency must match its budget'
        USING ERRCODE = '23514';
    END IF;
    IF date_trunc('month', NEW.occurred_on)::date
       IS DISTINCT FROM v_budget.month_start THEN
      RAISE EXCEPTION 'expense date must match the budget month'
        USING ERRCODE = '23514';
    END IF;
    IF NEW.split_mode = 'equal'
       AND (NEW.split_a_minor <> NEW.amount_minor / 2
            OR NEW.split_b_minor <> NEW.amount_minor - NEW.split_a_minor) THEN
      RAISE EXCEPTION 'equal split must differ by at most one minor unit'
        USING ERRCODE = '23514';
    END IF;
  END IF;

  SELECT user_id INTO v_seat1
  FROM public.couple_memberships
  WHERE couple_id = NEW.couple_id AND seat = 1 AND state = 'active';
  SELECT user_id INTO v_seat2
  FROM public.couple_memberships
  WHERE couple_id = NEW.couple_id AND seat = 2 AND state = 'active';
  IF v_seat1 IS NULL OR v_seat2 IS NULL
     OR NEW.split_a_user_id IS DISTINCT FROM v_seat1
     OR NEW.split_b_user_id IS DISTINCT FROM v_seat2
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
