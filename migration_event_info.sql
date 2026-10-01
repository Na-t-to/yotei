-- Structured event details migration.
-- Safe to run more than once. Existing events and availability entries are preserved.

alter table public.aki_events add column if not exists detail text;
alter table public.aki_events add column if not exists place text;
alter table public.aki_events add column if not exists event_time text;
alter table public.aki_events add column if not exists activity text;
alter table public.aki_events add column if not exists reference_url text;
alter table public.aki_events add column if not exists other text;

create or replace function private.aki_create_event_v3(
  p_title text,
  p_place text,
  p_event_time text,
  p_activity text,
  p_reference_url text,
  p_other text,
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
  v_place text := nullif(btrim(coalesce(p_place, '')), '');
  v_event_time text := nullif(btrim(coalesce(p_event_time, '')), '');
  v_activity text := nullif(btrim(coalesce(p_activity, '')), '');
  v_reference_url text := nullif(btrim(coalesce(p_reference_url, '')), '');
  v_other text := nullif(btrim(coalesce(p_other, '')), '');
begin
  if char_length(v_title) < 1 or char_length(v_title) > 30 then
    raise exception 'タイトルを1〜30文字で入力してください';
  end if;
  if v_place is not null and char_length(v_place) > 100 then
    raise exception '場所は100文字以内にしてください';
  end if;
  if v_event_time is not null and char_length(v_event_time) > 80 then
    raise exception '時間は80文字以内にしてください';
  end if;
  if v_activity is not null and char_length(v_activity) > 200 then
    raise exception '何をするは200文字以内にしてください';
  end if;
  if v_reference_url is not null and char_length(v_reference_url) > 500 then
    raise exception '参考URLは500文字以内にしてください';
  end if;
  if v_reference_url is not null and v_reference_url !~* '^https?://' then
    raise exception '参考URLはhttp://またはhttps://で入力してください';
  end if;
  if v_other is not null and char_length(v_other) > 500 then
    raise exception 'その他は500文字以内にしてください';
  end if;
  if p_start_date is null or p_end_date is null or p_end_date < p_start_date then
    raise exception '日付を確認してください';
  end if;
  if p_end_date - p_start_date > 180 then
    raise exception '期間は180日以内にしてください';
  end if;

  insert into public.aki_events(
    title, place, event_time, activity, reference_url, other, start_date, end_date
  )
  values (
    v_title, v_place, v_event_time, v_activity, v_reference_url, v_other, p_start_date, p_end_date
  )
  returning id into v_id;

  return v_id;
end;
$$;

create or replace function private.aki_get_event_v3(p_event_id uuid)
returns table(
  title text,
  place text,
  event_time text,
  activity text,
  reference_url text,
  other text,
  detail text,
  start_date date,
  end_date date
)
language sql
security definer
set search_path = ''
stable
as $$
  select
    e.title,
    e.place,
    e.event_time,
    e.activity,
    e.reference_url,
    e.other,
    e.detail,
    e.start_date,
    e.end_date
  from public.aki_events e
  where e.id = p_event_id;
$$;

revoke all on function private.aki_create_event_v3(text,text,text,text,text,text,date,date) from public;
revoke all on function private.aki_get_event_v3(uuid) from public;

grant usage on schema private to anon, authenticated;
grant execute on function private.aki_create_event_v3(text,text,text,text,text,text,date,date) to anon, authenticated;
grant execute on function private.aki_get_event_v3(uuid) to anon, authenticated;

create or replace function public.aki_create_event_v3(
  p_title text,
  p_place text,
  p_event_time text,
  p_activity text,
  p_reference_url text,
  p_other text,
  p_start_date date,
  p_end_date date
) returns uuid
language sql
security invoker
set search_path = ''
as $$
  select private.aki_create_event_v3(
    p_title, p_place, p_event_time, p_activity, p_reference_url, p_other, p_start_date, p_end_date
  );
$$;

create or replace function public.aki_get_event_v3(p_event_id uuid)
returns table(
  title text,
  place text,
  event_time text,
  activity text,
  reference_url text,
  other text,
  detail text,
  start_date date,
  end_date date
)
language sql
security invoker
set search_path = ''
stable
as $$ select * from private.aki_get_event_v3(p_event_id); $$;

revoke all on function public.aki_create_event_v3(text,text,text,text,text,text,date,date) from public;
revoke all on function public.aki_get_event_v3(uuid) from public;

grant execute on function public.aki_create_event_v3(text,text,text,text,text,text,date,date) to anon, authenticated;
grant execute on function public.aki_get_event_v3(uuid) to anon, authenticated;
