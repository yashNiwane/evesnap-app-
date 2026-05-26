-- Eve host + guest schema
create extension if not exists pgcrypto;

create table if not exists public.events (
  id uuid primary key default gen_random_uuid(),
  host_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  details text not null default '',
  cover_path text,
  theme text not null default 'minimal' check (theme in ('party', 'wedding', 'vacation', 'graduation', 'minimal')),
  reveal_time timestamptz not null,
  photo_limit integer not null check (photo_limit > 0),
  is_revealed boolean not null default false,
  created_at timestamptz not null default now()
);

alter table public.events add column if not exists theme text not null default 'minimal';
alter table public.events add column if not exists is_revealed boolean not null default false;
alter table public.events add column if not exists cover_path text;
do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'events_theme_check'
      and conrelid = 'public.events'::regclass
  ) then
    alter table public.events
      add constraint events_theme_check
      check (theme in ('party', 'wedding', 'vacation', 'graduation', 'minimal'));
  end if;
end $$;

create table if not exists public.guests (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.events(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  nickname text not null,
  joined_at timestamptz not null default now(),
  unique (event_id, user_id)
);

create table if not exists public.photos (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.events(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  storage_path text not null,
  caption text not null default '',
  nickname_denormalized text not null default '',
  file_size_bytes integer,
  captured_ip inet,
  source_type text not null default 'gallery',
  created_at timestamptz not null default now()
);

alter table public.photos add column if not exists nickname_denormalized text not null default '';
alter table public.photos add column if not exists file_size_bytes integer;
alter table public.photos add column if not exists captured_ip inet;

create table if not exists public.reactions (
  id uuid primary key default gen_random_uuid(),
  photo_id uuid not null references public.photos(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  reaction text not null,
  created_at timestamptz not null default now(),
  unique (photo_id, user_id, reaction)
);

create index if not exists idx_events_host on public.events(host_id);
create index if not exists idx_guests_event on public.guests(event_id);
create index if not exists idx_photos_event on public.photos(event_id);
create index if not exists idx_photos_user on public.photos(user_id);
create index if not exists idx_photos_event_user on public.photos(event_id, user_id);
create index if not exists idx_photos_captured_ip on public.photos(captured_ip);
create index if not exists idx_reactions_photo on public.reactions(photo_id);

create or replace function public.event_is_host(target_event_id uuid)
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.events e
    where e.id = target_event_id
      and e.host_id = auth.uid()
  );
$$;

create or replace function public.event_is_guest(target_event_id uuid)
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.guests g
    where g.event_id = target_event_id
      and g.user_id = auth.uid()
  );
$$;

create or replace function public.event_is_joined_by(target_event_id uuid, target_user_id uuid)
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.guests g
    where g.event_id = target_event_id
      and g.user_id = target_user_id
  );
$$;

create or replace function public.event_is_revealed(target_event_id uuid)
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.events e
    where e.id = target_event_id
      and (e.is_revealed or now() >= e.reveal_time)
  );
$$;

create or replace function public.event_accepts_upload(
  target_event_id uuid,
  target_user_id uuid
)
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.events e
    where e.id = target_event_id
      and not (e.is_revealed or now() >= e.reveal_time)
      and (
        select count(*)
        from public.photos p
        where p.event_id = target_event_id
          and p.user_id = target_user_id
      ) < e.photo_limit
  );
$$;

create or replace function public.first_path_uuid(path text)
returns uuid
language plpgsql
immutable
as $$
begin
  return split_part(path, '/', 1)::uuid;
exception
  when others then
    return null;
end;
$$;

alter table public.events enable row level security;
alter table public.guests enable row level security;
alter table public.photos enable row level security;
alter table public.reactions enable row level security;

drop policy if exists events_select on public.events;
create policy events_select on public.events for select to authenticated using (true);

drop policy if exists events_insert on public.events;
create policy events_insert on public.events for insert to authenticated with check (auth.uid() = host_id);

drop policy if exists events_update on public.events;
create policy events_update on public.events for update to authenticated using (auth.uid() = host_id) with check (auth.uid() = host_id);

drop policy if exists events_delete on public.events;
create policy events_delete on public.events for delete to authenticated using (auth.uid() = host_id);

drop policy if exists guests_select on public.guests;
create policy guests_select on public.guests for select to authenticated using (
  public.event_is_host(event_id)
  or user_id = auth.uid()
);

drop policy if exists guests_insert on public.guests;
create policy guests_insert on public.guests for insert to authenticated with check (auth.uid() = user_id);

drop policy if exists guests_update on public.guests;
create policy guests_update on public.guests for update to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists photos_select on public.photos;
create policy photos_select on public.photos for select to authenticated using (
  public.event_is_host(event_id)
  or (
    user_id = auth.uid()
    and not public.event_is_revealed(event_id)
  )
  or (
    public.event_is_revealed(event_id)
    and public.event_is_guest(event_id)
  )
);

drop policy if exists photos_insert on public.photos;
create policy photos_insert on public.photos for insert to authenticated with check (
  auth.uid() = user_id
  and (
    public.event_is_host(event_id)
    or (
      public.event_is_joined_by(event_id, user_id)
      and public.event_accepts_upload(event_id, user_id)
    )
  )
);

drop policy if exists photos_update on public.photos;
create policy photos_update on public.photos for update to authenticated using (
  auth.uid() = user_id
  and not public.event_is_revealed(event_id)
) with check (
  auth.uid() = user_id
  and not public.event_is_revealed(event_id)
);

drop policy if exists photos_delete on public.photos;
create policy photos_delete on public.photos for delete to authenticated using (
  (
    public.event_is_host(event_id)
    or auth.uid() = user_id
  )
  and not public.event_is_revealed(event_id)
);

drop policy if exists reactions_select on public.reactions;
create policy reactions_select on public.reactions for select to authenticated using (
  photo_id in (
    select p.id from public.photos p
    where public.event_is_host(p.event_id)
      or (public.event_is_revealed(p.event_id) and public.event_is_guest(p.event_id))
  )
);

drop policy if exists reactions_insert on public.reactions;
create policy reactions_insert on public.reactions for insert to authenticated with check (
  auth.uid() = user_id
  and exists (
    select 1
    from public.photos p
    where p.id = photo_id
      and public.event_is_revealed(p.event_id)
      and public.event_is_guest(p.event_id)
  )
);

drop policy if exists reactions_update on public.reactions;
create policy reactions_update on public.reactions for update to authenticated using (
  auth.uid() = user_id
) with check (
  auth.uid() = user_id
);

insert into storage.buckets (id, name, public)
values ('Event Photos and Videos', 'Event Photos and Videos', false)
on conflict (id) do nothing;

insert into storage.buckets (id, name, public)
values ('Event Covers', 'Event Covers', false)
on conflict (id) do nothing;

drop policy if exists event_photo_objects_select on storage.objects;
create policy event_photo_objects_select on storage.objects for select to authenticated using (
  bucket_id = 'Event Photos and Videos'
  and (
    public.event_is_host(public.first_path_uuid(name))
    or owner = auth.uid()
    or (
      public.event_is_revealed(public.first_path_uuid(name))
      and public.event_is_guest(public.first_path_uuid(name))
    )
  )
);

drop policy if exists event_photo_objects_insert on storage.objects;
create policy event_photo_objects_insert on storage.objects for insert to authenticated with check (
  bucket_id = 'Event Photos and Videos'
  and owner = auth.uid()
  and (
    public.event_is_host(public.first_path_uuid(name))
    or (
      public.event_is_guest(public.first_path_uuid(name))
      and public.event_accepts_upload(public.first_path_uuid(name), auth.uid())
    )
  )
);

drop policy if exists event_photo_objects_delete on storage.objects;
create policy event_photo_objects_delete on storage.objects for delete to authenticated using (
  bucket_id = 'Event Photos and Videos'
  and not public.event_is_revealed(public.first_path_uuid(name))
  and (
    public.event_is_host(public.first_path_uuid(name))
    or owner = auth.uid()
  )
);

drop policy if exists event_cover_objects_select on storage.objects;
create policy event_cover_objects_select on storage.objects for select to authenticated using (
  bucket_id = 'Event Covers'
  and owner = auth.uid()
);

drop policy if exists event_cover_objects_insert on storage.objects;
create policy event_cover_objects_insert on storage.objects for insert to authenticated with check (
  bucket_id = 'Event Covers'
  and owner = auth.uid()
  and public.first_path_uuid(name) = auth.uid()
);

drop policy if exists event_cover_objects_delete on storage.objects;
create policy event_cover_objects_delete on storage.objects for delete to authenticated using (
  bucket_id = 'Event Covers'
  and owner = auth.uid()
  and public.first_path_uuid(name) = auth.uid()
);
