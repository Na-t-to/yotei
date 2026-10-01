create extension if not exists pgcrypto with schema extensions;
create schema if not exists private;

create table if not exists public.aki_events (
  id uuid primary key default gen_random_uuid(),
  title text not null check (char_length(title) between 1 and 80),
  detail text,
  start_date date not null,
  end_date date not null,
  created_at timestamptz not null default now(),
  constraint aki_events_date_order check (end_date >= start_date),
  constraint aki_events_range_limit check (end_date - start_date <= 180)
);

create table if not exists public.aki_entries (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.aki_events(id) on delete cascade,
  date date not null,
  name text not null check (char_length(name) between 1 and 60),
  all_day boolean not null default true,
  start_time time,
  end_time time,
  note text,
  delete_token uuid not null,
  created_at timestamptz not null default now(),
  constraint aki_entries_note_limit check (note is null or char_length(note) <= 500),
  constraint aki_entries_time_shape check (
    (all_day and start_time is null and end_time is null)
    or
    (not all_day and (start_time is not null or end_time is not null))
  ),
  constraint aki_entries_time_order check (
    start_time is null or end_time is null or end_time > start_time
  )
);

create index if not exists aki_entries_event_date_idx on public.aki_entries(event_id, date);

alter table public.aki_events enable row level security;
alter table public.aki_entries enable row level security;

revoke all on table public.aki_events from anon, authenticated;
revoke all on table public.aki_entries from anon, authenticated;

create or replace function private.aki_create_event(
  p_title text,
  p_start_date date,
  p_end_date date
) returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_title text := btrim(coalesce(p_title, ''));
begin
  if char_length(v_title) < 1 or char_length(v_title) > 80 then
    raise exception 'タイトルを1〜80文字で入力してください';
  end if;
  if p_start_date is null or p_end_date is null or p_end_date < p_start_date then
    raise exception '日付を確認してください';
  end if;
  if p_end_date - p_start_date > 180 then
    raise exception '期間は180日以内にしてください';
  end if;

  insert into public.aki_events(title, start_date, end_date)
  values (v_title, p_start_date, p_end_date)
  returning id into v_id;
  return v_id;
end;
$$;

create or replace function private.aki_get_event(p_event_id uuid)
returns table(title text, start_date date, end_date date)
language sql
security definer
set search_path = ''
stable
as $$
  select e.title, e.start_date, e.end_date
  from public.aki_events e
  where e.id = p_event_id;
$$;

create or replace function private.aki_list_entries(p_event_id uuid)
returns table(
  id uuid,
  date date,
  name text,
  all_day boolean,
  start_time time,
  end_time time,
  note text,
  created_at timestamptz
)
language sql
security definer
set search_path = ''
stable
as $$
  select e.id, e.date, e.name, e.all_day, e.start_time, e.end_time, e.note, e.created_at
  from public.aki_entries e
  where e.event_id = p_event_id
  order by e.date, e.created_at;
$$;

create or replace function private.aki_add_entries(
  p_event_id uuid,
  p_dates date[],
  p_name text,
  p_all_day boolean,
  p_start_time time,
  p_end_time time,
  p_note text,
  p_delete_token uuid
) returns table(entry_id uuid)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_start date;
  v_end date;
  v_name text := btrim(coalesce(p_name, ''));
  v_note text := nullif(btrim(coalesce(p_note, '')), '');
  v_count integer := coalesce(array_length(p_dates, 1), 0);
begin
  if v_count < 1 or v_count > 60 then
    raise exception '日付を1〜60件で指定してください';
  end if;
  if char_length(v_name) < 1 or char_length(v_name) > 60 then
    raise exception '名前を1〜60文字で入力してください';
  end if;
  if v_note is not null and char_length(v_note) > 500 then
    raise exception '備考は500文字以内にしてください';
  end if;
  if p_delete_token is null then
    raise exception 'token is required';
  end if;
  if not p_all_day and p_start_time is null and p_end_time is null then
    raise exception '時間を指定してください';
  end if;
  if p_start_time is not null and p_end_time is not null and p_end_time <= p_start_time then
    raise exception '終了時刻は開始時刻より後にしてください';
  end if;

  select e.start_date, e.end_date into v_start, v_end
  from public.aki_events e
  where e.id = p_event_id;

  if not found then
    raise exception 'イベントが見つかりません';
  end if;

  if exists (
    select 1 from unnest(p_dates) as x(d)
    where d < v_start or d > v_end
  ) then
    raise exception '期間外の日付が含まれています';
  end if;

  return query
  insert into public.aki_entries(
    event_id, date, name, all_day, start_time, end_time, note, delete_token
  )
  select
    p_event_id,
    d,
    v_name,
    p_all_day,
    case when p_all_day then null else p_start_time end,
    case when p_all_day then null else p_end_time end,
    v_note,
    p_delete_token
  from (select distinct unnest(p_dates) as d) x
  returning public.aki_entries.id;
end;
$$;

create or replace function private.aki_delete_entry(
  p_event_id uuid,
  p_entry_id uuid,
  p_delete_token uuid
) returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  delete from public.aki_entries
  where id = p_entry_id
    and event_id = p_event_id
    and delete_token = p_delete_token;
  get diagnostics v_count = row_count;
  return v_count = 1;
end;
$$;

revoke all on function private.aki_create_event(text,date,date) from public;
revoke all on function private.aki_get_event(uuid) from public;
revoke all on function private.aki_list_entries(uuid) from public;
revoke all on function private.aki_add_entries(uuid,date[],text,boolean,time,time,text,uuid) from public;
revoke all on function private.aki_delete_entry(uuid,uuid,uuid) from public;

grant usage on schema private to anon, authenticated;
grant execute on function private.aki_create_event(text,date,date) to anon, authenticated;
grant execute on function private.aki_get_event(uuid) to anon, authenticated;
grant execute on function private.aki_list_entries(uuid) to anon, authenticated;
grant execute on function private.aki_add_entries(uuid,date[],text,boolean,time,time,text,uuid) to anon, authenticated;
grant execute on function private.aki_delete_entry(uuid,uuid,uuid) to anon, authenticated;

create or replace function public.aki_create_event(p_title text, p_start_date date, p_end_date date)
returns uuid
language sql
security invoker
set search_path = ''
as $$ select private.aki_create_event(p_title, p_start_date, p_end_date); $$;

create or replace function public.aki_get_event(p_event_id uuid)
returns table(title text, start_date date, end_date date)
language sql
security invoker
set search_path = ''
stable
as $$ select * from private.aki_get_event(p_event_id); $$;

create or replace function public.aki_list_entries(p_event_id uuid)
returns table(id uuid, date date, name text, all_day boolean, start_time time, end_time time, note text, created_at timestamptz)
language sql
security invoker
set search_path = ''
stable
as $$ select * from private.aki_list_entries(p_event_id); $$;

create or replace function public.aki_add_entries(
  p_event_id uuid,
  p_dates date[],
  p_name text,
  p_all_day boolean,
  p_start_time time,
  p_end_time time,
  p_note text,
  p_delete_token uuid
) returns table(entry_id uuid)
language sql
security invoker
set search_path = ''
as $$
  select * from private.aki_add_entries(
    p_event_id, p_dates, p_name, p_all_day, p_start_time, p_end_time, p_note, p_delete_token
  );
$$;

create or replace function public.aki_delete_entry(p_event_id uuid, p_entry_id uuid, p_delete_token uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select private.aki_delete_entry(p_event_id, p_entry_id, p_delete_token); $$;

revoke all on function public.aki_create_event(text,date,date) from public;
revoke all on function public.aki_get_event(uuid) from public;
revoke all on function public.aki_list_entries(uuid) from public;
revoke all on function public.aki_add_entries(uuid,date[],text,boolean,time,time,text,uuid) from public;
revoke all on function public.aki_delete_entry(uuid,uuid,uuid) from public;

grant execute on function public.aki_create_event(text,date,date) to anon, authenticated;
grant execute on function public.aki_get_event(uuid) to anon, authenticated;
grant execute on function public.aki_list_entries(uuid) to anon, authenticated;
grant execute on function public.aki_add_entries(uuid,date[],text,boolean,time,time,text,uuid) to anon, authenticated;
grant execute on function public.aki_delete_entry(uuid,uuid,uuid) to anon, authenticated;

-- Event details (v2)
alter table public.aki_events
  add column if not exists detail text;

create or replace function private.aki_create_event_v2(
  p_title text,
  p_detail text,
  p_start_date date,
  p_end_date date
) returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_title text := btrim(coalesce(p_title, ''));
  v_detail text := nullif(btrim(coalesce(p_detail, '')), '');
begin
  if char_length(v_title) < 1 or char_length(v_title) > 80 then
    raise exception 'タイトルを1〜80文字で入力してください';
  end if;
  if v_detail is not null and char_length(v_detail) > 1000 then
    raise exception '予定の詳細は1000文字以内にしてください';
  end if;
  if p_start_date is null or p_end_date is null or p_end_date < p_start_date then
    raise exception '日付を確認してください';
  end if;
  if p_end_date - p_start_date > 180 then
    raise exception '期間は180日以内にしてください';
  end if;

  insert into public.aki_events(title, detail, start_date, end_date)
  values (v_title, v_detail, p_start_date, p_end_date)
  returning id into v_id;
  return v_id;
end;
$$;

create or replace function private.aki_get_event_v2(p_event_id uuid)
returns table(title text, detail text, start_date date, end_date date)
language sql
security definer
set search_path = ''
stable
as $$
  select e.title, e.detail, e.start_date, e.end_date
  from public.aki_events e
  where e.id = p_event_id;
$$;

revoke all on function private.aki_create_event_v2(text,text,date,date) from public;
revoke all on function private.aki_get_event_v2(uuid) from public;

grant usage on schema private to anon, authenticated;
grant execute on function private.aki_create_event_v2(text,text,date,date) to anon, authenticated;
grant execute on function private.aki_get_event_v2(uuid) to anon, authenticated;

create or replace function public.aki_create_event_v2(
  p_title text,
  p_detail text,
  p_start_date date,
  p_end_date date
) returns uuid
language sql
security invoker
set search_path = ''
as $$
  select private.aki_create_event_v2(p_title, p_detail, p_start_date, p_end_date);
$$;

create or replace function public.aki_get_event_v2(p_event_id uuid)
returns table(title text, detail text, start_date date, end_date date)
language sql
security invoker
set search_path = ''
stable
as $$ select * from private.aki_get_event_v2(p_event_id); $$;

revoke all on function public.aki_create_event_v2(text,text,date,date) from public;
revoke all on function public.aki_get_event_v2(uuid) from public;

grant execute on function public.aki_create_event_v2(text,text,date,date) to anon, authenticated;
grant execute on function public.aki_get_event_v2(uuid) to anon, authenticated;
