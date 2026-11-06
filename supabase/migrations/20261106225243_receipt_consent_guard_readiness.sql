-- Still unpublished: only release readiness, never provider authorization.
alter table private.receipt_policy_versions
  add column content_sha256 text check (content_sha256 ~ '^[a-f0-9]{64}$'),
  add column retired_at timestamptz,
  add constraint receipt_policy_published_content check (published_at is null or content_sha256 is not null);
drop index private.receipt_policy_one_published;
create unique index receipt_policy_one_published on private.receipt_policy_versions ((true))
  where published_at is not null and retired_at is null;

create function private.protect_receipt_policy_content() returns trigger
language plpgsql set search_path='' as $$
begin
  if (old.published_at is not null or exists(select 1 from private.receipt_policy_acceptances where policy_version=old.version))
    and (new.version is distinct from old.version or new.policy_path is distinct from old.policy_path or new.content_sha256 is distinct from old.content_sha256 or new.published_at is distinct from old.published_at) then
    raise exception 'published_policy_immutable';
  end if;
  return new;
end $$;
revoke all on function private.protect_receipt_policy_content() from public,anon,authenticated;
create trigger protect_receipt_policy_content before update on private.receipt_policy_versions
  for each row execute function private.protect_receipt_policy_content();

create or replace function private.receipt_policy_status() returns jsonb
language plpgsql security definer set search_path='' as $$
declare v private.receipt_policy_versions; u uuid:=auth.uid();
begin
  if u is null then raise exception 'auth_required' using errcode='42501'; end if;
  select * into v from private.receipt_policy_versions
    where published_at is not null and published_at<=clock_timestamp() and retired_at is null;
  if not found then return jsonb_build_object('configured',false,'accepted',false); end if;
  return jsonb_build_object('configured',true,'version',v.version,'policy_path',v.policy_path,'content_sha256',v.content_sha256,
    'accepted',exists(select 1 from private.receipt_policy_acceptances a where a.user_id=u and a.policy_version=v.version));
end $$;

create or replace function private.accept_receipt_policy(p_version text,p_method text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare u uuid:=auth.uid(); v text;
begin
  if u is null then raise exception 'auth_required' using errcode='42501'; end if;
  if p_method is null or p_method not in ('account_prompt','signup_confirmed') then raise exception 'invalid_acknowledgement'; end if;
  select version into v from private.receipt_policy_versions where version=p_version
    and published_at is not null and published_at<=clock_timestamp() and retired_at is null for share;
  if not found then raise exception 'policy_not_current'; end if;
  insert into private.receipt_policy_acceptances(user_id,policy_version,acknowledgement_method)
    values(u,v,p_method) on conflict(user_id,policy_version) do nothing;
  return private.receipt_policy_status();
end $$;
revoke all on function private.receipt_policy_status(),private.accept_receipt_policy(text,text) from public,anon;
grant execute on function private.receipt_policy_status(),private.accept_receipt_policy(text,text) to authenticated;
