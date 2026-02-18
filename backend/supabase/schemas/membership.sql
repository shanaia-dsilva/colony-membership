-- supabase/schemas/membership.sql
-- Membership schema: members, roles, members_roles, enums, indexes, view, and RLS policies.
-- Save under supabase/schemas/ so the Supabase CLI can diff and generate migrations.

-- Extensions
create extension if not exists "pgcrypto"; -- for gen_random_uuid()
-- create extension if not exists postgis;   -- uncomment if you want PostGIS geometry columns

-- -----------------------------------------------------------------------------
-- Enums (guarded creation so re-running doesn't error)
-- -----------------------------------------------------------------------------
do $$
begin
  if not exists (select 1 from pg_type where typname = 'membership_term_t') then
    create type membership_term_t as enum ('monthly', 'quarterly', 'annual', 'lifetime');
  end if;

  if not exists (select 1 from pg_type where typname = 'membership_status_t') then
    create type membership_status_t as enum ('active', 'expired', 'suspended', 'pending', 'cancelled');
  end if;
end$$;

-- -----------------------------------------------------------------------------
-- Roles table
-- -----------------------------------------------------------------------------
create table if not exists "roles" (
  "id" uuid primary key default gen_random_uuid(),
  "name" text not null unique, -- e.g. 'admin', 'board', 'volunteer'
  "description" text,
  "created_at" timestamptz not null default now()
);

-- Seed a default admin role (safe to re-run)
insert into "roles" ("name", "description")
values ('admin', 'Full access admin')
on conflict ("name") do nothing;

-- -----------------------------------------------------------------------------
-- Members table
-- -----------------------------------------------------------------------------
create table if not exists "members" (
  "id" uuid primary key default gen_random_uuid(),

  -- Tie a member record to a Supabase Auth user (for login + self access)
  "auth_user_id" uuid references auth.users(id) on delete set null,

  "first_name" text not null,
  "last_name" text not null,
  "full_name" text generated always as (
    concat(coalesce("first_name",''), ' ', coalesce("last_name",''))
  ) stored,

  "phone" text,
  "email" text not null,

  -- Colony-friendly label (Block/Flat), plus optional full address fields
  "location_label" text,
  "street" text,
  "city" text,
  "region" text, -- state/province
  "postal_code" text,
  "country" text,

  -- Geolocation
  "latitude" double precision,
  "longitude" double precision,
  -- Optional PostGIS:
  -- "location" geometry(Point, 4326),

  -- Membership term / status
  "membership_term" membership_term_t not null default 'annual',
  "membership_status" membership_status_t not null default 'pending',
  "membership_started_at" timestamptz not null default now(),
  "membership_expires_at" timestamptz, -- nullable for lifetime/pending

  -- Administrative fields
  "registered_at" timestamptz not null default now(),
  "notes" text,

  -- Soft-delete flag
  "is_deleted" boolean not null default false
);

-- Constraints
alter table "members"
  add constraint if not exists members_email_unique unique ("email");

-- One auth user -> one member row (optional but recommended if users log in)
alter table "members"
  add constraint if not exists members_auth_user_unique unique ("auth_user_id");

-- Indexes
create index if not exists idx_members_phone on "members" ("phone");
create index if not exists idx_members_registered_at on "members" ("registered_at");
create index if not exists idx_members_membership_status on "members" ("membership_status");
create index if not exists idx_members_membership_expires_at on "members" ("membership_expires_at");
create index if not exists idx_members_lat_lon on "members" ("latitude", "longitude");
create index if not exists idx_members_auth_user_id on "members" ("auth_user_id");

-- Optional unique phone (partial unique so nulls allowed)
create unique index if not exists members_phone_unique
on "members" ("phone")
where "phone" is not null;

-- -----------------------------------------------------------------------------
-- Members <-> Roles join table (many-to-many)
-- -----------------------------------------------------------------------------
create table if not exists "members_roles" (
  "id" uuid primary key default gen_random_uuid(),
  "member_id" uuid not null references "members"("id") on delete cascade,
  "role_id" uuid not null references "roles"("id") on delete cascade,
  "granted_by" uuid, -- could reference auth.users(id) if you want
  "granted_at" timestamptz not null default now(),
  constraint members_roles_unique unique ("member_id", "role_id")
);

create index if not exists idx_members_roles_member_id on "members_roles" ("member_id");
create index if not exists idx_members_roles_role_id on "members_roles" ("role_id");

-- -----------------------------------------------------------------------------
-- Convenience view: member + roles
-- -----------------------------------------------------------------------------
create or replace view "member_with_roles" as
select
  m.*,
  coalesce(
    jsonb_agg(
      jsonb_build_object('id', r.id, 'name', r.name, 'description', r.description)
    ) filter (where r.id is not null),
    '[]'::jsonb
  ) as roles
from "members" m
left join "members_roles" mr on mr.member_id = m.id
left join "roles" r on r.id = mr.role_id
where not m.is_deleted
group by m.id;

-- -----------------------------------------------------------------------------
-- Row Level Security (RLS)
-- -----------------------------------------------------------------------------
alter table "members" enable row level security;
alter table "roles" enable row level security;
alter table "members_roles" enable row level security;

-- Clean up old policies if re-running (optional safety)
drop policy if exists "members_self_select" on "members";
drop policy if exists "members_admin_select_all" on "members";
drop policy if exists "members_admin_update_all" on "members";

-- Members can read their own row
create policy "members_self_select" on "members"
for select to authenticated
using (auth.uid() = auth_user_id);

-- Admins can read all members if their member row has role 'admin'
create policy "members_admin_select_all" on "members"
for select to authenticated
using (
  exists (
    select 1
    from members m2
    join members_roles mr on mr.member_id = m2.id
    join roles r on r.id = mr.role_id
    where m2.auth_user_id = auth.uid()
      and r.name = 'admin'
  )
);

-- Admins can update all members
create policy "members_admin_update_all" on "members"
for update to authenticated
using (
  exists (
    select 1
    from members m2
    join members_roles mr on mr.member_id = m2.id
    join roles r on r.id = mr.role_id
    where m2.auth_user_id = auth.uid()
      and r.name = 'admin'
  )
);

-- NOTE:
-- We intentionally do NOT allow public inserts/updates directly to members here.
-- Your app should insert/update via server-side routes (or add an insert policy if you need client inserts).