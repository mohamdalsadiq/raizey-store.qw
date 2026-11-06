-- Draft only. Publication requires documented provider suitability and a matching
-- Edge + client release. This migration does NOT attest any existing user's consent.
create schema if not exists private;
revoke all on schema private from public, anon;
grant usage on schema private to authenticated, service_role;

create table private.receipt_policy_versions (
  version text primary key,
  policy_path text not null check (policy_path = '/privacy.html'),
  published_at timestamptz,
  provider_review_reference text,
  check (published_at is null or nullif(btrim(provider_review_reference),'') is not null)
);
create unique index receipt_policy_one_published on private.receipt_policy_versions ((true)) where published_at is not null;
alter table private.receipt_policy_versions enable row level security;
revoke all on private.receipt_policy_versions from public,anon,authenticated;
insert into private.receipt_policy_versions(version,policy_path) values('2026-11-06','/privacy.html');

create table private.receipt_policy_acceptances (
  user_id uuid not null references auth.users(id) on delete cascade,
  policy_version text not null references private.receipt_policy_versions(version),
  accepted_at timestamptz not null default clock_timestamp(),
  acknowledgement_method text not null check(acknowledgement_method in ('account_prompt','signup_confirmed')),
  primary key(user_id,policy_version)
);
alter table private.receipt_policy_acceptances enable row level security;
revoke all on private.receipt_policy_acceptances from public,anon,authenticated;
grant select on private.receipt_policy_acceptances to authenticated;
create policy receipt_policy_read_own on private.receipt_policy_acceptances for select to authenticated using(user_id=(select auth.uid()));

create function private.receipt_policy_status() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v private.receipt_policy_versions; u uuid := auth.uid();
begin
  if u is null then raise exception 'auth_required' using errcode='42501'; end if;
  select * into v from private.receipt_policy_versions where published_at is not null and published_at<=clock_timestamp();
  if not found then return jsonb_build_object('configured',false,'accepted',false); end if;
  return jsonb_build_object('configured',true,'version',v.version,'policy_path',v.policy_path,'accepted',exists(select 1 from private.receipt_policy_acceptances a where a.user_id=u and a.policy_version=v.version));
end $$;
revoke all on function private.receipt_policy_status() from public,anon;
grant execute on function private.receipt_policy_status() to authenticated;

create function private.accept_receipt_policy(p_version text,p_method text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare u uuid := auth.uid(); v text;
begin
  if u is null then raise exception 'auth_required' using errcode='42501'; end if;
  if p_method is null or p_method not in ('account_prompt','signup_confirmed') then raise exception 'invalid_acknowledgement'; end if;
  -- Lock against a concurrent publication change. No browser-supplied identity/date.
  select version into v from private.receipt_policy_versions where version=p_version and published_at is not null and published_at<=clock_timestamp() for share;
  if not found then raise exception 'policy_not_current'; end if;
  insert into private.receipt_policy_acceptances(user_id,policy_version,acknowledgement_method)
    values(u,v,p_method) on conflict(user_id,policy_version) do nothing;
  return private.receipt_policy_status();
end $$;
revoke all on function private.accept_receipt_policy(text,text) from public,anon;
grant execute on function private.accept_receipt_policy(text,text) to authenticated;

create function public.get_receipt_policy_status() returns jsonb
language sql security invoker set search_path = '' as $$ select private.receipt_policy_status(); $$;
create function public.accept_receipt_policy(p_version text,p_method text) returns jsonb
language sql security invoker set search_path = '' as $$ select private.accept_receipt_policy(p_version,p_method); $$;
revoke all on function public.get_receipt_policy_status() from public,anon;
revoke all on function public.accept_receipt_policy(text,text) from public,anon;
grant execute on function public.get_receipt_policy_status(), public.accept_receipt_policy(text,text) to authenticated;

comment on table private.receipt_policy_versions is 'Draft until provider plan suitability is documented. No automatic publication or retroactive consent.';
