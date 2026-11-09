-- CP-011 Phase 4: shared expenses. Money is exact integer minor units.
-- No Savings/contribution ledger or automatic currency conversion is included.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';

GRANT CREATE ON SCHEMA public TO twogethera_membership_owner;
SET LOCAL ROLE twogethera_membership_owner;
ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;

CREATE FUNCTION app_private.currency_exponent(p_code text)
RETURNS smallint LANGUAGE sql IMMUTABLE SET search_path = '' AS $function$
  SELECT CASE p_code
    WHEN 'JPY' THEN 0 WHEN 'KRW' THEN 0
    WHEN 'KWD' THEN 3
    WHEN 'USD' THEN 2 WHEN 'EUR' THEN 2 WHEN 'GBP' THEN 2
    WHEN 'CAD' THEN 2 WHEN 'AUD' THEN 2 WHEN 'NZD' THEN 2
    WHEN 'CHF' THEN 2 WHEN 'SGD' THEN 2 WHEN 'HKD' THEN 2
    WHEN 'CNY' THEN 2 WHEN 'INR' THEN 2 WHEN 'PHP' THEN 2
    ELSE NULL END::smallint
$function$;
REVOKE ALL ON FUNCTION app_private.currency_exponent(text) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION app_private.currency_exponent(text) TO authenticated;

CREATE TABLE public.couple_budgets (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  couple_id uuid NOT NULL REFERENCES public.couple_spaces(id) ON DELETE RESTRICT,
  month_start date NOT NULL CHECK (extract(day FROM month_start) = 1),
  currency_code text NOT NULL CHECK (app_private.currency_exponent(currency_code) IS NOT NULL),
  currency_exponent smallint NOT NULL CHECK (currency_exponent = app_private.currency_exponent(currency_code)),
  limit_minor bigint NOT NULL CHECK (limit_minor BETWEEN 0 AND 9000000000000),
  created_by uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT statement_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT statement_timestamp(),
  revision bigint NOT NULL DEFAULT 1 CHECK (revision > 0),
  UNIQUE (couple_id, month_start),
  UNIQUE (couple_id, id)
);
CREATE INDEX couple_budgets_scope_month ON public.couple_budgets(couple_id, month_start DESC);

CREATE TABLE public.budget_category_limits (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  couple_id uuid NOT NULL,
  budget_id uuid NOT NULL,
  category_key text NOT NULL CHECK (category_key IN ('housing','food','transport','utilities','health','travel','shopping','entertainment','other')),
  limit_minor bigint NOT NULL CHECK (limit_minor BETWEEN 0 AND 9000000000000),
  created_at timestamptz NOT NULL DEFAULT statement_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT statement_timestamp(),
  revision bigint NOT NULL DEFAULT 1 CHECK (revision > 0),
  UNIQUE (budget_id, category_key),
  FOREIGN KEY (couple_id, budget_id) REFERENCES public.couple_budgets(couple_id, id) ON DELETE CASCADE
);

CREATE TABLE public.recurring_expense_rules (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  couple_id uuid NOT NULL REFERENCES public.couple_spaces(id) ON DELETE RESTRICT,
  title text NOT NULL CHECK (title = btrim(title) AND char_length(title) BETWEEN 1 AND 160),
  description text NOT NULL DEFAULT '' CHECK (char_length(description) <= 2000),
  amount_minor bigint NOT NULL CHECK (amount_minor BETWEEN 1 AND 9000000000000),
  currency_code text NOT NULL CHECK (app_private.currency_exponent(currency_code) IS NOT NULL),
  currency_exponent smallint NOT NULL CHECK (currency_exponent = app_private.currency_exponent(currency_code)),
  category_key text NOT NULL CHECK (category_key IN ('housing','food','transport','utilities','health','travel','shopping','entertainment','other')),
  paid_by_user uuid NOT NULL,
  split_a_user_id uuid NOT NULL,
  split_a_minor bigint NOT NULL CHECK (split_a_minor >= 0),
  split_b_user_id uuid NOT NULL,
  split_b_minor bigint NOT NULL CHECK (split_b_minor >= 0),
  frequency text NOT NULL CHECK (frequency IN ('weekly','monthly','yearly')),
  starts_on date NOT NULL,
  ends_on date CHECK (ends_on IS NULL OR ends_on >= starts_on),
  active boolean NOT NULL DEFAULT true,
  created_by uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT statement_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT statement_timestamp(),
  revision bigint NOT NULL DEFAULT 1 CHECK (revision > 0),
  UNIQUE (couple_id, id),
  CHECK (split_a_user_id <> split_b_user_id),
  CHECK (split_a_minor + split_b_minor = amount_minor)
);

CREATE TABLE public.couple_expenses (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  couple_id uuid NOT NULL REFERENCES public.couple_spaces(id) ON DELETE RESTRICT,
  budget_id uuid NOT NULL,
  title text NOT NULL CHECK (title = btrim(title) AND char_length(title) BETWEEN 1 AND 160),
  description text NOT NULL DEFAULT '' CHECK (char_length(description) <= 2000),
  amount_minor bigint NOT NULL CHECK (amount_minor BETWEEN 1 AND 9000000000000),
  currency_code text NOT NULL CHECK (app_private.currency_exponent(currency_code) IS NOT NULL),
  currency_exponent smallint NOT NULL CHECK (currency_exponent = app_private.currency_exponent(currency_code)),
  occurred_on date NOT NULL,
  category_key text NOT NULL CHECK (category_key IN ('housing','food','transport','utilities','health','travel','shopping','entertainment','other')),
  paid_by_user uuid NOT NULL,
  split_mode text NOT NULL CHECK (split_mode IN ('equal','custom')),
  split_a_user_id uuid NOT NULL,
  split_a_minor bigint NOT NULL CHECK (split_a_minor >= 0),
  split_b_user_id uuid NOT NULL,
  split_b_minor bigint NOT NULL CHECK (split_b_minor >= 0),
  recurring_rule_id uuid,
  recurrence_key date,
  receipt_count smallint NOT NULL DEFAULT 0 CHECK (receipt_count BETWEEN 0 AND 5),
  created_by uuid NOT NULL,
  updated_by uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT statement_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT statement_timestamp(),
  revision bigint NOT NULL DEFAULT 1 CHECK (revision > 0),
  UNIQUE (couple_id, id),
  FOREIGN KEY (couple_id, budget_id) REFERENCES public.couple_budgets(couple_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (couple_id, recurring_rule_id) REFERENCES public.recurring_expense_rules(couple_id, id) ON DELETE RESTRICT,
  CHECK (split_a_user_id <> split_b_user_id),
  CHECK (split_a_minor + split_b_minor = amount_minor),
  CHECK ((recurring_rule_id IS NULL) = (recurrence_key IS NULL)),
  UNIQUE (recurring_rule_id, recurrence_key)
);
CREATE INDEX couple_expenses_scope_date ON public.couple_expenses(couple_id, occurred_on DESC, id);
CREATE INDEX couple_expenses_budget_category ON public.couple_expenses(budget_id, category_key, occurred_on DESC);

CREATE TABLE public.expense_receipts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  couple_id uuid NOT NULL,
  expense_id uuid NOT NULL,
  object_path text NOT NULL UNIQUE,
  content_type text NOT NULL CHECK (content_type IN ('image/jpeg','image/png','image/webp')),
  byte_size bigint NOT NULL CHECK (byte_size BETWEEN 1 AND 10485760),
  created_by uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT statement_timestamp(),
  FOREIGN KEY (couple_id, expense_id) REFERENCES public.couple_expenses(couple_id, id) ON DELETE RESTRICT
);
CREATE INDEX expense_receipts_parent ON public.expense_receipts(couple_id, expense_id, created_at, id);

CREATE FUNCTION app_private.guard_expense_receipt()
RETURNS trigger LANGUAGE plpgsql SET search_path = '' AS $function$
BEGIN
  IF TG_OP = 'INSERT' THEN
    NEW.created_by := app_private.current_identity_is_verified(false);
    NEW.created_at := statement_timestamp();
    NEW.object_path := NEW.couple_id::text || '/' || NEW.expense_id::text || '/' || NEW.id::text || '.blob';
    IF (SELECT count(*) FROM public.expense_receipts r WHERE r.expense_id = NEW.expense_id) >= 5 THEN
      RAISE EXCEPTION 'receipt limit reached' USING ERRCODE = '23514';
    END IF;
  ELSE
    IF OLD.id IS DISTINCT FROM NEW.id OR OLD.couple_id IS DISTINCT FROM NEW.couple_id
       OR OLD.expense_id IS DISTINCT FROM NEW.expense_id OR OLD.object_path IS DISTINCT FROM NEW.object_path
       OR OLD.content_type IS DISTINCT FROM NEW.content_type OR OLD.byte_size IS DISTINCT FROM NEW.byte_size
       OR OLD.created_by IS DISTINCT FROM NEW.created_by OR OLD.created_at IS DISTINCT FROM NEW.created_at THEN
      RAISE EXCEPTION 'receipt identity is immutable' USING ERRCODE = '42501';
    END IF;
  END IF;
  RETURN NEW;
END
$function$;
CREATE TRIGGER expense_receipts_guard BEFORE INSERT OR UPDATE ON public.expense_receipts
  FOR EACH ROW EXECUTE FUNCTION app_private.guard_expense_receipt();

CREATE FUNCTION app_private.guard_budget_row()
RETURNS trigger LANGUAGE plpgsql SET search_path = '' AS $function$
BEGIN
  IF TG_OP = 'INSERT' THEN
    NEW.created_by := app_private.current_identity_is_verified(false);
    NEW.created_at := statement_timestamp(); NEW.updated_at := NEW.created_at; NEW.revision := 1;
  ELSE
    IF OLD.id IS DISTINCT FROM NEW.id OR OLD.couple_id IS DISTINCT FROM NEW.couple_id
       OR OLD.month_start IS DISTINCT FROM NEW.month_start OR OLD.created_by IS DISTINCT FROM NEW.created_by
       OR OLD.created_at IS DISTINCT FROM NEW.created_at OR OLD.revision IS DISTINCT FROM NEW.revision THEN
      RAISE EXCEPTION 'budget identity is server controlled' USING ERRCODE = '42501';
    END IF;
    IF (OLD.currency_code, OLD.currency_exponent) IS DISTINCT FROM (NEW.currency_code, NEW.currency_exponent)
       AND EXISTS (SELECT 1 FROM public.couple_expenses e WHERE e.budget_id = OLD.id) THEN
      RAISE EXCEPTION 'currency cannot change after expenses exist' USING ERRCODE = '23514';
    END IF;
    NEW.updated_at := statement_timestamp(); NEW.revision := OLD.revision + 1;
  END IF;
  RETURN NEW;
END
$function$;
CREATE TRIGGER couple_budgets_guard BEFORE INSERT OR UPDATE ON public.couple_budgets
  FOR EACH ROW EXECUTE FUNCTION app_private.guard_budget_row();

CREATE FUNCTION app_private.guard_financial_row()
RETURNS trigger LANGUAGE plpgsql SET search_path = '' AS $function$
DECLARE v_actor uuid; v_budget public.couple_budgets%ROWTYPE; v_seat1 uuid; v_seat2 uuid;
BEGIN
  v_actor := app_private.current_identity_is_verified(false);
  IF TG_OP = 'INSERT' THEN
    NEW.created_by := v_actor;
    IF TG_TABLE_NAME = 'couple_expenses' THEN NEW.updated_by := v_actor; END IF;
    NEW.created_at := statement_timestamp(); NEW.updated_at := NEW.created_at; NEW.revision := 1;
  ELSE
    IF OLD.id IS DISTINCT FROM NEW.id OR OLD.couple_id IS DISTINCT FROM NEW.couple_id
       OR OLD.created_by IS DISTINCT FROM NEW.created_by
       OR OLD.created_at IS DISTINCT FROM NEW.created_at OR OLD.revision IS DISTINCT FROM NEW.revision THEN
      RAISE EXCEPTION 'expense identity is server controlled' USING ERRCODE = '42501';
    END IF;
    IF TG_TABLE_NAME = 'couple_expenses' THEN
      IF OLD.budget_id IS DISTINCT FROM NEW.budget_id THEN
        RAISE EXCEPTION 'expense budget is immutable' USING ERRCODE = '42501';
      END IF;
    END IF;
    IF TG_TABLE_NAME = 'couple_expenses' THEN NEW.updated_by := v_actor; END IF;
    NEW.updated_at := statement_timestamp(); NEW.revision := OLD.revision + 1;
  END IF;
  IF TG_TABLE_NAME = 'couple_expenses' THEN
    SELECT * INTO v_budget FROM public.couple_budgets WHERE id = NEW.budget_id AND couple_id = NEW.couple_id;
    IF NOT FOUND OR (v_budget.currency_code, v_budget.currency_exponent) IS DISTINCT FROM (NEW.currency_code, NEW.currency_exponent) THEN
      RAISE EXCEPTION 'expense currency must match its budget' USING ERRCODE = '23514';
    END IF;
    IF date_trunc('month', NEW.occurred_on)::date IS DISTINCT FROM v_budget.month_start THEN
      RAISE EXCEPTION 'expense date must match the budget month' USING ERRCODE = '23514';
    END IF;
    IF NEW.split_mode = 'equal'
       AND (NEW.split_a_minor <> NEW.amount_minor / 2 OR NEW.split_b_minor <> NEW.amount_minor - NEW.split_a_minor) THEN
      RAISE EXCEPTION 'equal split must differ by at most one minor unit' USING ERRCODE = '23514';
    END IF;
  END IF;
  SELECT user_id INTO v_seat1 FROM public.couple_memberships WHERE couple_id = NEW.couple_id AND seat = 1 AND state = 'active';
  SELECT user_id INTO v_seat2 FROM public.couple_memberships WHERE couple_id = NEW.couple_id AND seat = 2 AND state = 'active';
  IF v_seat1 IS NULL OR v_seat2 IS NULL
     OR NEW.split_a_user_id IS DISTINCT FROM v_seat1 OR NEW.split_b_user_id IS DISTINCT FROM v_seat2
     OR NEW.paid_by_user NOT IN (v_seat1, v_seat2) THEN
    RAISE EXCEPTION 'expense participants must be current couple members' USING ERRCODE = '42501';
  END IF;
  IF NEW.split_a_minor + NEW.split_b_minor <> NEW.amount_minor THEN
    RAISE EXCEPTION 'split must equal expense amount' USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END
$function$;
CREATE TRIGGER recurring_expense_rules_guard BEFORE INSERT OR UPDATE ON public.recurring_expense_rules
  FOR EACH ROW EXECUTE FUNCTION app_private.guard_financial_row();
CREATE TRIGGER couple_expenses_guard BEFORE INSERT OR UPDATE ON public.couple_expenses
  FOR EACH ROW EXECUTE FUNCTION app_private.guard_financial_row();

CREATE FUNCTION app_private.guard_budget_spend()
RETURNS trigger LANGUAGE plpgsql SET search_path = '' AS $function$
DECLARE v_budget_id uuid; v_total numeric;
BEGIN
  v_budget_id := coalesce(NEW.budget_id, OLD.budget_id);
  SELECT coalesce(sum(amount_minor::numeric), 0) INTO v_total
  FROM public.couple_expenses WHERE budget_id = v_budget_id;
  IF v_total > 9000000000000 THEN
    RAISE EXCEPTION 'monthly spending exceeds the supported exact-money range' USING ERRCODE = '23514';
  END IF;
  RETURN NULL;
END
$function$;
CREATE CONSTRAINT TRIGGER couple_expenses_total_guard
AFTER INSERT OR UPDATE OR DELETE ON public.couple_expenses
DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION app_private.guard_budget_spend();

CREATE FUNCTION public.delete_couple_expense(p_couple_id uuid, p_expense_id uuid, p_expected_revision bigint)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $function$
DECLARE v_actor uuid; v_revision bigint;
BEGIN
  v_actor := app_private.current_identity_is_verified(true);
  IF v_actor IS NULL OR NOT app_private.can_read_shared_records(p_couple_id) THEN RETURN false; END IF;
  SELECT revision INTO v_revision FROM public.couple_expenses
  WHERE couple_id = p_couple_id AND id = p_expense_id FOR UPDATE;
  IF NOT FOUND OR v_revision IS DISTINCT FROM p_expected_revision THEN RETURN false; END IF;
  IF EXISTS (SELECT 1 FROM public.expense_receipts WHERE couple_id = p_couple_id AND expense_id = p_expense_id) THEN
    RAISE EXCEPTION 'remove private receipts before deleting this expense' USING ERRCODE = '23514';
  END IF;
  DELETE FROM public.couple_expenses WHERE couple_id = p_couple_id AND id = p_expense_id;
  RETURN FOUND;
END
$function$;
ALTER FUNCTION public.delete_couple_expense(uuid,uuid,bigint) OWNER TO twogethera_membership_owner;

ALTER TABLE public.couple_budgets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.couple_budgets FORCE ROW LEVEL SECURITY;
ALTER TABLE public.budget_category_limits ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.budget_category_limits FORCE ROW LEVEL SECURITY;
ALTER TABLE public.recurring_expense_rules ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.recurring_expense_rules FORCE ROW LEVEL SECURITY;
ALTER TABLE public.couple_expenses ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.couple_expenses FORCE ROW LEVEL SECURITY;
ALTER TABLE public.expense_receipts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.expense_receipts FORCE ROW LEVEL SECURITY;

CREATE POLICY budgets_pair_access ON public.couple_budgets FOR ALL TO authenticated
  USING (app_private.can_read_shared_records(couple_id))
  WITH CHECK (app_private.can_read_shared_records(couple_id));
CREATE POLICY budget_categories_pair_access ON public.budget_category_limits FOR ALL TO authenticated
  USING (app_private.can_read_shared_records(couple_id))
  WITH CHECK (app_private.can_read_shared_records(couple_id));
CREATE POLICY recurring_expenses_pair_access ON public.recurring_expense_rules FOR ALL TO authenticated
  USING (app_private.can_read_shared_records(couple_id))
  WITH CHECK (app_private.can_read_shared_records(couple_id));
CREATE POLICY expenses_pair_access ON public.couple_expenses FOR ALL TO authenticated
  USING (app_private.can_read_shared_records(couple_id))
  WITH CHECK (app_private.can_read_shared_records(couple_id));
CREATE POLICY expense_receipts_pair_access ON public.expense_receipts FOR ALL TO authenticated
  USING (app_private.can_read_shared_records(couple_id))
  WITH CHECK (app_private.can_read_shared_records(couple_id));

CREATE POLICY budgets_owner_access ON public.couple_budgets FOR ALL TO twogethera_membership_owner USING (true) WITH CHECK (true);
CREATE POLICY budget_categories_owner_access ON public.budget_category_limits FOR ALL TO twogethera_membership_owner USING (true) WITH CHECK (true);
CREATE POLICY recurring_expenses_owner_access ON public.recurring_expense_rules FOR ALL TO twogethera_membership_owner USING (true) WITH CHECK (true);
CREATE POLICY expenses_owner_access ON public.couple_expenses FOR ALL TO twogethera_membership_owner USING (true) WITH CHECK (true);
CREATE POLICY expense_receipts_owner_access ON public.expense_receipts FOR ALL TO twogethera_membership_owner USING (true) WITH CHECK (true);

RESET ROLE;
REVOKE CREATE ON SCHEMA public FROM twogethera_membership_owner;
REVOKE ALL ON public.couple_budgets, public.budget_category_limits, public.recurring_expense_rules, public.couple_expenses, public.expense_receipts FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT ON public.couple_budgets, public.budget_category_limits, public.recurring_expense_rules, public.couple_expenses TO authenticated;
GRANT INSERT (couple_id,month_start,currency_code,currency_exponent,limit_minor) ON public.couple_budgets TO authenticated;
GRANT UPDATE (couple_id,month_start,limit_minor,currency_code,currency_exponent) ON public.couple_budgets TO authenticated;
GRANT INSERT (couple_id,budget_id,category_key,limit_minor) ON public.budget_category_limits TO authenticated;
GRANT UPDATE (budget_id,category_key,limit_minor) ON public.budget_category_limits TO authenticated;
GRANT INSERT (couple_id,title,description,amount_minor,currency_code,currency_exponent,category_key,paid_by_user,split_a_user_id,split_a_minor,split_b_user_id,split_b_minor,frequency,starts_on,ends_on,active) ON public.recurring_expense_rules TO authenticated;
GRANT UPDATE (title,description,amount_minor,currency_code,currency_exponent,category_key,paid_by_user,split_a_user_id,split_a_minor,split_b_user_id,split_b_minor,frequency,starts_on,ends_on,active) ON public.recurring_expense_rules TO authenticated;
GRANT INSERT (couple_id,budget_id,title,description,amount_minor,currency_code,currency_exponent,occurred_on,category_key,paid_by_user,split_mode,split_a_user_id,split_a_minor,split_b_user_id,split_b_minor,recurring_rule_id,recurrence_key) ON public.couple_expenses TO authenticated;
GRANT UPDATE (title,description,amount_minor,occurred_on,category_key,paid_by_user,split_mode,split_a_user_id,split_a_minor,split_b_user_id,split_b_minor) ON public.couple_expenses TO authenticated;
REVOKE ALL ON FUNCTION public.delete_couple_expense(uuid,uuid,bigint) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.delete_couple_expense(uuid,uuid,bigint) TO authenticated;

-- Receipt metadata schema and integrity triggers remain for lifecycle
-- compatibility, but client grants are intentionally absent in Private Beta V1.

COMMIT;
NOTIFY pgrst, 'reload schema';
