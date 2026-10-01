-- Add optional event details without changing existing event URLs or entries.

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
