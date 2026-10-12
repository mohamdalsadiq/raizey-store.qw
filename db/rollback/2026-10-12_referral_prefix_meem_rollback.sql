-- Rollback: restore the RZY prefix.
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
    v_code := 'RZY';
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
commit;
