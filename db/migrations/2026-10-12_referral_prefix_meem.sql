-- MEEM STORE — rebrand the referral short-code prefix (RZY → MEEM).
-- Forward-only data-free change: only the generator's prefix changes, so codes
-- already issued keep working (matching is case-insensitive on the value).
-- Format stays inside the existing CHECK: ^[A-Z0-9]{5,12}$  ('MEEM'+8 = 12).
begin;

create or replace function public.generate_referral_short_code()
returns text
language plpgsql
security definer
set search_path to 'public'
as $fn$
declare
  v_alphabet constant text := '23456789ABCDEFGHJKLMNPQRSTUVWXYZ';
  v_code     text;
  v_attempt  integer := 0;
begin
  loop
    v_attempt := v_attempt + 1;
    v_code := 'MEEM';
    for i in 1..8 loop
      v_code := v_code || substr(v_alphabet, 1 + floor(random() * length(v_alphabet))::int, 1);
    end loop;
    exit when not exists (select 1 from public.profiles where referral_short_code = v_code);
    if v_attempt > 25 then
      raise exception 'referral_code_generation_failed';
    end if;
  end loop;
  return v_code;
end
$fn$;

revoke all on function public.generate_referral_short_code() from public, anon, authenticated;
grant execute on function public.generate_referral_short_code() to service_role;

select proname, pg_get_functiondef(oid) like '%MEEM%' as uses_meem
from pg_proc where proname = 'generate_referral_short_code';

commit;
