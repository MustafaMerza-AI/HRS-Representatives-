-- PostgreSQL schema for the official organization model.
-- The schema separates organizational units from positions and assignments.

create table source_documents (
  id text primary key,
  title text not null,
  publisher text,
  issue_no text,
  issue_date date,
  file_name text,
  notes text,
  created_at timestamptz not null default now()
);

create table org_units (
  id text primary key,
  official_name_ar text not null,
  display_name_ar text not null,
  unit_type text not null,
  parent_id text references org_units(id),
  path_ar text not null,
  sort_order integer not null default 0,
  requires_primary_position boolean not null default true,
  expansion_status text not null default 'pending_source',
  source_ref text references source_documents(id),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index idx_org_units_parent_id on org_units(parent_id);
create index idx_org_units_type on org_units(unit_type);
create index idx_org_units_source_ref on org_units(source_ref);

create table positions (
  id text primary key,
  org_unit_id text not null references org_units(id) on delete cascade,
  title_ar text not null,
  position_type text not null default 'primary',
  rank_hint_ar text,
  is_primary_for_indicator boolean not null default false,
  source_ref text references source_documents(id),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index one_primary_indicator_position_per_unit
  on positions(org_unit_id)
  where is_primary_for_indicator = true and is_active = true;

create table persons (
  id uuid primary key default gen_random_uuid(),
  full_name_ar text not null,
  birth_date date,
  phone text,
  photo_url text,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table assignments (
  id uuid primary key default gen_random_uuid(),
  person_id uuid not null references persons(id) on delete restrict,
  position_id text not null references positions(id) on delete restrict,
  assignment_title_ar text,
  start_date date,
  end_date date,
  status text not null default 'active',
  source_ref text references source_documents(id),
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint valid_assignment_status check (status in ('draft', 'pending_approval', 'active', 'ended', 'rejected'))
);

create unique index one_active_assignment_per_position
  on assignments(position_id)
  where status = 'active' and end_date is null;

create table approval_requests (
  id uuid primary key default gen_random_uuid(),
  request_type text not null,
  target_org_unit_id text references org_units(id),
  target_position_id text references positions(id),
  proposed_person_id uuid references persons(id),
  submitted_by_user_id uuid,
  status text not null default 'pending',
  payload jsonb not null default '{}'::jsonb,
  decision_notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint valid_request_status check (status in ('pending', 'approved', 'rejected', 'needs_changes', 'cancelled'))
);

create table notifications (
  id uuid primary key default gen_random_uuid(),
  recipient_user_id uuid,
  title_ar text not null,
  body_ar text not null,
  notification_type text not null,
  priority text not null default 'normal',
  status text not null default 'unread',
  target_entity_type text,
  target_entity_id text,
  target_page text,
  payload jsonb not null default '{}'::jsonb,
  read_at timestamptz,
  created_at timestamptz not null default now(),
  constraint valid_notification_priority check (priority in ('low', 'normal', 'high', 'urgent')),
  constraint valid_notification_status check (status in ('unread', 'read', 'archived'))
);

create index idx_notifications_recipient_status
  on notifications(recipient_user_id, status, created_at desc);

create index idx_notifications_type
  on notifications(notification_type);

create table activity_log (
  id uuid primary key default gen_random_uuid(),
  actor_user_id uuid,
  action text not null,
  entity_type text not null,
  entity_id text not null,
  old_value jsonb,
  new_value jsonb,
  created_at timestamptz not null default now()
);

create view org_unit_occupancy as
select
  ou.id as org_unit_id,
  ou.official_name_ar,
  ou.display_name_ar,
  ou.unit_type,
  ou.parent_id,
  ou.path_ar,
  ou.requires_primary_position,
  p.id as primary_position_id,
  p.title_ar as primary_position_title_ar,
  a.id as active_assignment_id,
  per.id as person_id,
  per.full_name_ar as occupant_name_ar,
  case
    when ou.requires_primary_position = false then 'gray'
    when p.id is null then 'red'
    when a.id is null then 'red'
    else 'green'
  end as indicator_color
from org_units ou
left join positions p
  on p.org_unit_id = ou.id
  and p.is_primary_for_indicator = true
  and p.is_active = true
left join assignments a
  on a.position_id = p.id
  and a.status = 'active'
  and a.end_date is null
left join persons per
  on per.id = a.person_id;
