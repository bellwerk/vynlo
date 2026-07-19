-- VYN-CRM-001, VYN-TEN-001, VYN-SEC-001, VYN-AUD-001, VYN-JOB-001
-- M3-CRM-AC-001 / T-CRM-001 / T-TEN-001 / T-RBAC-001 / T-AUTH-002 / T-AUD-001
-- Tenant-neutral party profiles, consented contacts, structured addresses,
-- restricted identifiers, relationships, preferences, and command controls.

-- The M1 API used a workspace-global raw idempotency key on parties. Preserve
-- the raw key and function signature while making ownership actor-scoped.
alter table public.parties
  add column idempotency_actor_user_id uuid;

update public.parties
set idempotency_actor_user_id = created_by
where idempotency_actor_user_id is null;

alter table public.parties
  alter column idempotency_actor_user_id set not null,
  add constraint parties_idempotency_actor_fk
    foreign key (idempotency_actor_user_id)
    references auth.users (id) on delete restrict;

alter table public.parties
  drop constraint parties_workspace_id_idempotency_key_key;
alter table public.parties
  add constraint parties_workspace_actor_idempotency_key
    unique (workspace_id, idempotency_actor_user_id, idempotency_key);

create function app.set_party_idempotency_actor()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.idempotency_actor_user_id := coalesce(
    new.idempotency_actor_user_id,
    new.created_by
  );
  if new.idempotency_actor_user_id is null then
    raise exception using
      errcode = '23502',
      message = 'party idempotency actor is required';
  end if;
  return new;
end;
$$;

create function app.m3_replace_party_identifier(
  p_workspace_id uuid,
  p_idempotency_key text,
  p_party_id uuid,
  p_identifier_type text,
  p_jurisdiction text,
  p_plaintext_value text,
  p_effective_from date,
  p_effective_to date,
  p_reason text,
  p_request_id text,
  p_correlation_id uuid
)
returns table (
  identifier_id uuid,
  party_id uuid,
  aggregate_version bigint,
  audit_event_id uuid,
  outbox_event_id uuid,
  replayed boolean
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_user_id uuid;
  normalized_key text;
  normalized_type text;
  normalized_jurisdiction text;
  normalized_plaintext text;
  normalized_reason text;
  identifier_fingerprint text;
  identifier_ciphertext bytea;
  identifier_mask text;
  request_fingerprint text;
  existing_receipt record;
  party_row record;
  current_identifier record;
  next_identifier_version bigint;
  next_aggregate_version bigint;
  new_identifier_id uuid;
  new_audit_event_id uuid;
  new_outbox_event_id uuid;
  result_payload jsonb;
begin
  actor_user_id := app.require_m3_crm_permission(
    p_workspace_id,
    'identifiers.manage',
    true
  );
  -- Resolve the runtime key before even considering a replay. Sensitive
  -- commands must fail closed when encryption is not configured.
  perform app.m3_crm_identifier_runtime_key();

  normalized_key := pg_catalog.btrim(p_idempotency_key);
  normalized_type := pg_catalog.btrim(p_identifier_type);
  normalized_jurisdiction := pg_catalog.btrim(p_jurisdiction);
  normalized_plaintext := pg_catalog.btrim(p_plaintext_value);
  normalized_reason := pg_catalog.btrim(p_reason);
  if p_party_id is null
    or pg_catalog.char_length(normalized_key) not between 8 and 200
    or normalized_type !~ '^[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)*$'
    or pg_catalog.char_length(normalized_jurisdiction) not between 2 and 100
    or pg_catalog.char_length(normalized_plaintext) not between 2 and 500
    or pg_catalog.char_length(normalized_reason) not between 1 and 2000
    or (p_effective_to is not null and p_effective_from is not null
      and p_effective_to < p_effective_from)
    or p_correlation_id is null
    or (p_request_id is not null and pg_catalog.char_length(p_request_id) > 200) then
    raise exception using errcode = '22023', message = 'invalid party identifier command';
  end if;

  identifier_fingerprint := app.m3_crm_identifier_fingerprint(normalized_plaintext);
  identifier_ciphertext := app.m3_crm_encrypt_identifier(normalized_plaintext);
  identifier_mask := pg_catalog.right(
    normalized_plaintext,
    least(4, pg_catalog.char_length(normalized_plaintext))
  );
  request_fingerprint := app.vertical_slice_fingerprint(
    pg_catalog.jsonb_build_object(
      'partyId', p_party_id,
      'identifierType', normalized_type,
      'jurisdiction', normalized_jurisdiction,
      'valueFingerprint', identifier_fingerprint,
      'effectiveFrom', p_effective_from,
      'effectiveTo', p_effective_to,
      'reason', normalized_reason
    )
  );

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      p_workspace_id::text || E'\x1fm3_replace_party_identifier\x1f'
        || actor_user_id::text || E'\x1f' || normalized_key,
      0
    )
  );
  select receipt.* into existing_receipt
  from public.party_command_receipts receipt
  where receipt.workspace_id = p_workspace_id
    and receipt.actor_user_id = app.current_user_id()
    and receipt.command_type = 'm3_replace_party_identifier'
    and receipt.idempotency_key = normalized_key;
  if found then
    if existing_receipt.command_fingerprint <> request_fingerprint then
      raise exception using
        errcode = '23505',
        message = 'party idempotency key was used for different identifier input';
    end if;
    return query select
      (existing_receipt.result ->> 'identifier_id')::uuid,
      (existing_receipt.result ->> 'party_id')::uuid,
      (existing_receipt.result ->> 'aggregate_version')::bigint,
      (existing_receipt.result ->> 'audit_event_id')::uuid,
      (existing_receipt.result ->> 'outbox_event_id')::uuid,
      true;
    return;
  end if;

  select party.* into party_row
  from public.parties party
  where party.workspace_id = p_workspace_id and party.id = p_party_id
  for update;
  if not found or party_row.status <> 'active' then
    raise exception using errcode = '23514', message = 'active workspace party is required';
  end if;

  select stored_identifier.* into current_identifier
  from public.party_identifiers stored_identifier
  where stored_identifier.workspace_id = p_workspace_id
    and stored_identifier.party_id = p_party_id
    and stored_identifier.identifier_type = normalized_type
    and stored_identifier.jurisdiction = normalized_jurisdiction
    and stored_identifier.status = 'active'
  for update;

  next_identifier_version := coalesce(current_identifier.version, 0) + 1;
  if current_identifier.id is not null then
    update public.party_identifiers
    set status = 'replaced', replaced_at = pg_catalog.statement_timestamp()
    where workspace_id = p_workspace_id and id = current_identifier.id;
  end if;

  new_identifier_id := pg_catalog.gen_random_uuid();
  insert into public.party_identifiers (
    id, workspace_id, party_id, identifier_type, jurisdiction, version,
    encrypted_value, value_fingerprint, masked_suffix,
    effective_from, effective_to, replaces_identifier_id, reason, created_by
  ) values (
    new_identifier_id, p_workspace_id, p_party_id, normalized_type,
    normalized_jurisdiction, next_identifier_version,
    identifier_ciphertext, identifier_fingerprint, identifier_mask,
    p_effective_from, p_effective_to, current_identifier.id,
    normalized_reason, actor_user_id
  );

  next_aggregate_version := party_row.version + 1;
  update public.parties set version = next_aggregate_version
  where workspace_id = p_workspace_id and id = p_party_id;

  new_audit_event_id := app.write_audit_event(
    p_workspace_id => p_workspace_id,
    p_action => 'party.identifier_replaced',
    p_entity_type => 'party',
    p_entity_id => p_party_id,
    p_actor_user_id => actor_user_id,
    p_actor_type => 'user',
    p_before_data => pg_catalog.jsonb_build_object(
      'version', party_row.version,
      'prior_identifier_id', current_identifier.id
    ),
    p_after_data => pg_catalog.jsonb_build_object(
      'version', next_aggregate_version,
      'identifier_id', new_identifier_id,
      'identifier_type', normalized_type,
      'jurisdiction', normalized_jurisdiction,
      'masked_value', '********' || identifier_mask,
      'identifier_version', next_identifier_version
    ),
    p_request_id => p_request_id,
    p_correlation_id => p_correlation_id,
    p_auth_assurance => coalesce(auth.jwt() ->> 'aal', 'unknown'),
    p_metadata => pg_catalog.jsonb_build_object(
      'idempotency_key', normalized_key,
      'reason', normalized_reason
    )
  );
  new_outbox_event_id := app.append_m3_crm_outbox_event(
    p_workspace_id,
    'party.identifier_replaced',
    p_party_id,
    next_aggregate_version,
    pg_catalog.jsonb_build_object(
      'partyId', p_party_id,
      'identifierId', new_identifier_id,
      'identifierType', normalized_type,
      'jurisdiction', normalized_jurisdiction,
      'maskedValue', '********' || identifier_mask,
      'identifierVersion', next_identifier_version,
      'aggregateVersion', next_aggregate_version
    ),
    actor_user_id,
    p_correlation_id
  );
  result_payload := pg_catalog.jsonb_build_object(
    'identifier_id', new_identifier_id,
    'party_id', p_party_id,
    'aggregate_version', next_aggregate_version,
    'audit_event_id', new_audit_event_id,
    'outbox_event_id', new_outbox_event_id
  );
  insert into public.party_command_receipts (
    workspace_id, actor_user_id, command_type, idempotency_key,
    command_fingerprint, party_id, result, audit_event_id, outbox_event_id
  ) values (
    p_workspace_id, actor_user_id, 'm3_replace_party_identifier', normalized_key,
    request_fingerprint, p_party_id, result_payload,
    new_audit_event_id, new_outbox_event_id
  );

  return query select
    new_identifier_id,
    p_party_id,
    next_aggregate_version,
    new_audit_event_id,
    new_outbox_event_id,
    false;
end;
$$;

create function app.m3_reveal_party_identifier(
  p_workspace_id uuid,
  p_identifier_id uuid,
  p_reason text,
  p_request_id text,
  p_correlation_id uuid
)
returns table (
  identifier_id uuid,
  party_id uuid,
  plaintext_value text,
  audit_event_id uuid
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_user_id uuid;
  normalized_reason text;
  stored_identifier record;
  revealed_value text;
  new_audit_event_id uuid;
begin
  actor_user_id := app.require_m3_crm_permission(
    p_workspace_id,
    'identifiers.read_restricted',
    true
  );
  perform app.m3_crm_identifier_runtime_key();
  normalized_reason := pg_catalog.btrim(p_reason);
  if p_identifier_id is null
    or pg_catalog.char_length(normalized_reason) not between 1 and 2000
    or p_correlation_id is null
    or (p_request_id is not null and pg_catalog.char_length(p_request_id) > 200) then
    raise exception using errcode = '22023', message = 'invalid identifier reveal request';
  end if;

  select identifier.* into stored_identifier
  from public.party_identifiers identifier
  where identifier.workspace_id = p_workspace_id and identifier.id = p_identifier_id;
  if not found then
    raise exception using errcode = '23503', message = 'party identifier does not exist';
  end if;
  revealed_value := app.m3_crm_decrypt_identifier(stored_identifier.encrypted_value);

  new_audit_event_id := app.write_audit_event(
    p_workspace_id => p_workspace_id,
    p_action => 'party.identifier_revealed',
    p_entity_type => 'party',
    p_entity_id => stored_identifier.party_id,
    p_actor_user_id => actor_user_id,
    p_actor_type => 'user',
    p_before_data => null,
    p_after_data => pg_catalog.jsonb_build_object(
      'identifier_id', stored_identifier.id,
      'identifier_type', stored_identifier.identifier_type,
      'jurisdiction', stored_identifier.jurisdiction,
      'masked_value', '********' || stored_identifier.masked_suffix
    ),
    p_request_id => p_request_id,
    p_correlation_id => p_correlation_id,
    p_auth_assurance => coalesce(auth.jwt() ->> 'aal', 'unknown'),
    p_metadata => pg_catalog.jsonb_build_object('reason', normalized_reason)
  );

  return query select
    stored_identifier.id,
    stored_identifier.party_id,
    revealed_value,
    new_audit_event_id;
end;
$$;

create trigger parties_a_set_idempotency_actor
before insert on public.parties
for each row execute function app.set_party_idempotency_actor();

drop trigger parties_immutable on public.parties;
create trigger parties_immutable
before update on public.parties
for each row execute function app.enforce_immutable_columns(
  'id', 'workspace_id', 'party_type', 'idempotency_key',
  'idempotency_actor_user_id', 'command_fingerprint', 'created_by', 'created_at'
);

-- Shared tenant-neutral prerequisite for deal ownership and document headers.
-- Legal identifiers, tax behavior, and document policy are deliberately absent.
create table public.legal_entities (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  workspace_id uuid not null references public.workspaces (id) on delete restrict,
  key text not null
    check (key ~ '^[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)*$'),
  legal_names jsonb not null check (
    pg_catalog.jsonb_typeof(legal_names) = 'object'
    and pg_catalog.jsonb_typeof(legal_names -> 'en') = 'string'
    and pg_catalog.btrim(legal_names ->> 'en') <> ''
    and pg_catalog.jsonb_typeof(legal_names -> 'fr') = 'string'
    and pg_catalog.btrim(legal_names ->> 'fr') <> ''
  ),
  display_names jsonb not null check (
    pg_catalog.jsonb_typeof(display_names) = 'object'
    and pg_catalog.jsonb_typeof(display_names -> 'en') = 'string'
    and pg_catalog.btrim(display_names ->> 'en') <> ''
    and pg_catalog.jsonb_typeof(display_names -> 'fr') = 'string'
    and pg_catalog.btrim(display_names ->> 'fr') <> ''
  ),
  organization_party_id uuid,
  status text not null default 'active' check (status in ('active', 'retired')),
  version bigint not null default 1 check (version > 0),
  created_by uuid references auth.users (id) on delete restrict,
  created_at timestamptz not null default pg_catalog.statement_timestamp(),
  retired_at timestamptz,
  unique (workspace_id, id),
  unique (workspace_id, key),
  foreign key (workspace_id, organization_party_id)
    references public.parties (workspace_id, id) on delete restrict,
  check (
    (status = 'active' and retired_at is null)
    or (status = 'retired' and retired_at is not null)
  )
);

create table public.party_person_profiles (
  party_id uuid primary key,
  workspace_id uuid not null references public.workspaces (id) on delete restrict,
  given_name text not null check (
    pg_catalog.btrim(given_name) <> '' and pg_catalog.char_length(given_name) <= 100
  ),
  family_name text not null check (
    pg_catalog.btrim(family_name) <> '' and pg_catalog.char_length(family_name) <= 100
  ),
  preferred_name text check (
    preferred_name is null or (
      pg_catalog.btrim(preferred_name) <> ''
      and pg_catalog.char_length(preferred_name) <= 100
    )
  ),
  birth_date date,
  preferred_locale text not null check (preferred_locale in ('en', 'fr')),
  version bigint not null check (version > 0),
  created_at timestamptz not null default pg_catalog.statement_timestamp(),
  updated_at timestamptz not null default pg_catalog.statement_timestamp(),
  unique (workspace_id, party_id),
  foreign key (workspace_id, party_id)
    references public.parties (workspace_id, id) on delete restrict
);

create table public.party_organization_profiles (
  party_id uuid primary key,
  workspace_id uuid not null references public.workspaces (id) on delete restrict,
  legal_name text not null check (
    pg_catalog.btrim(legal_name) <> '' and pg_catalog.char_length(legal_name) <= 200
  ),
  registration_name text check (
    registration_name is null or (
      pg_catalog.btrim(registration_name) <> ''
      and pg_catalog.char_length(registration_name) <= 200
    )
  ),
  preferred_locale text not null check (preferred_locale in ('en', 'fr')),
  version bigint not null check (version > 0),
  created_at timestamptz not null default pg_catalog.statement_timestamp(),
  updated_at timestamptz not null default pg_catalog.statement_timestamp(),
  unique (workspace_id, party_id),
  foreign key (workspace_id, party_id)
    references public.parties (workspace_id, id) on delete restrict
);

-- M3-CRM-AC-001 compatibility: parties created before typed profiles existed
-- must remain readable through the M3 detail contract. The source display name
-- remains authoritative; these deterministic projections only satisfy the
-- required subtype shape until an explicit M3 update supplies richer data.
insert into public.party_person_profiles (
  party_id, workspace_id, given_name, family_name, preferred_name,
  birth_date, preferred_locale, version
)
select
  party.id,
  party.workspace_id,
  pg_catalog.left(pg_catalog.split_part(party.display_name, ' ', 1), 100),
  coalesce(
    nullif(
      pg_catalog.left(
        pg_catalog.btrim(
          pg_catalog.regexp_replace(party.display_name, '^[^ ]+[ ]*', '')
        ),
        100
      ),
      ''
    ),
    pg_catalog.left(pg_catalog.split_part(party.display_name, ' ', 1), 100)
  ),
  null,
  null,
  case when workspace.default_locale like 'fr%' then 'fr' else 'en' end,
  party.version
from public.parties party
join public.workspaces workspace on workspace.id = party.workspace_id
where party.party_type = 'person';

insert into public.party_organization_profiles (
  party_id, workspace_id, legal_name, registration_name,
  preferred_locale, version
)
select
  party.id,
  party.workspace_id,
  party.display_name,
  null,
  case when workspace.default_locale like 'fr%' then 'fr' else 'en' end,
  party.version
from public.parties party
join public.workspaces workspace on workspace.id = party.workspace_id
where party.party_type = 'organization';

create table public.party_contacts (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  workspace_id uuid not null references public.workspaces (id) on delete restrict,
  party_id uuid not null,
  logical_contact_id uuid not null,
  version bigint not null check (version > 0),
  contact_type text not null check (contact_type in ('email', 'phone')),
  value text not null check (
    pg_catalog.btrim(value) <> '' and pg_catalog.char_length(value) <= 320
  ),
  normalized_value text not null check (
    pg_catalog.btrim(normalized_value) <> ''
    and pg_catalog.char_length(normalized_value) <= 320
  ),
  is_primary boolean not null default false,
  is_preferred boolean not null default false,
  do_not_contact boolean not null default false,
  consent_status text not null default 'unknown'
    check (consent_status in ('unknown', 'granted', 'denied', 'withdrawn')),
  consent_source text check (
    consent_source is null or (
      pg_catalog.btrim(consent_source) <> ''
      and pg_catalog.char_length(consent_source) <= 500
    )
  ),
  consent_recorded_at timestamptz not null default pg_catalog.statement_timestamp(),
  consent_recorded_by uuid not null references auth.users (id) on delete restrict,
  status text not null default 'active'
    check (status in ('active', 'replaced', 'archived')),
  replaces_contact_id uuid,
  effective_from timestamptz not null default pg_catalog.statement_timestamp(),
  effective_to timestamptz,
  archived_at timestamptz,
  created_by uuid not null references auth.users (id) on delete restrict,
  created_at timestamptz not null default pg_catalog.statement_timestamp(),
  unique (workspace_id, id),
  unique (workspace_id, logical_contact_id, version),
  foreign key (workspace_id, party_id)
    references public.parties (workspace_id, id) on delete restrict,
  foreign key (workspace_id, replaces_contact_id)
    references public.party_contacts (workspace_id, id) on delete restrict,
  check (consent_status <> 'granted' or consent_source is not null),
  check (effective_to is null or effective_to > effective_from),
  check (
    (status = 'active' and effective_to is null and archived_at is null)
    or (status in ('replaced', 'archived') and effective_to is not null)
  )
);

create unique index party_contacts_active_value_uidx
  on public.party_contacts (
    workspace_id, party_id, contact_type, normalized_value
  ) where status = 'active';
create unique index party_contacts_primary_uidx
  on public.party_contacts (workspace_id, party_id, contact_type)
  where status = 'active' and is_primary;
create unique index party_contacts_preferred_uidx
  on public.party_contacts (workspace_id, party_id, contact_type)
  where status = 'active' and is_preferred;

create table public.party_addresses (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  workspace_id uuid not null references public.workspaces (id) on delete restrict,
  party_id uuid not null,
  logical_address_id uuid not null,
  version bigint not null check (version > 0),
  address_type text not null
    check (address_type ~ '^[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)*$'),
  line_1 text not null check (
    pg_catalog.btrim(line_1) <> '' and pg_catalog.char_length(line_1) <= 200
  ),
  line_2 text check (line_2 is null or pg_catalog.char_length(line_2) <= 200),
  locality text not null check (
    pg_catalog.btrim(locality) <> '' and pg_catalog.char_length(locality) <= 100
  ),
  region text not null check (
    pg_catalog.btrim(region) <> '' and pg_catalog.char_length(region) <= 100
  ),
  postal_code text not null check (
    pg_catalog.btrim(postal_code) <> '' and pg_catalog.char_length(postal_code) <= 32
  ),
  country_code char(2) not null check (country_code ~ '^[A-Z]{2}$'),
  is_primary boolean not null default false,
  status text not null default 'active'
    check (status in ('active', 'replaced', 'archived')),
  replaces_address_id uuid,
  effective_from timestamptz not null default pg_catalog.statement_timestamp(),
  effective_to timestamptz,
  archived_at timestamptz,
  created_by uuid not null references auth.users (id) on delete restrict,
  created_at timestamptz not null default pg_catalog.statement_timestamp(),
  unique (workspace_id, id),
  unique (workspace_id, logical_address_id, version),
  foreign key (workspace_id, party_id)
    references public.parties (workspace_id, id) on delete restrict,
  foreign key (workspace_id, replaces_address_id)
    references public.party_addresses (workspace_id, id) on delete restrict,
  check (effective_to is null or effective_to > effective_from),
  check (
    (status = 'active' and effective_to is null and archived_at is null)
    or (status in ('replaced', 'archived') and effective_to is not null)
  )
);

create unique index party_addresses_primary_uidx
  on public.party_addresses (workspace_id, party_id, address_type)
  where status = 'active' and is_primary;

create table public.party_identifiers (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  workspace_id uuid not null references public.workspaces (id) on delete restrict,
  party_id uuid not null,
  identifier_type text not null
    check (identifier_type ~ '^[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)*$'),
  jurisdiction text not null check (
    pg_catalog.btrim(jurisdiction) <> ''
    and pg_catalog.char_length(jurisdiction) between 2 and 100
  ),
  version bigint not null check (version > 0),
  status text not null default 'active'
    check (status in ('active', 'replaced', 'revoked')),
  encrypted_value bytea not null check (pg_catalog.octet_length(encrypted_value) > 16),
  value_fingerprint text not null check (value_fingerprint ~ '^[0-9a-f]{64}$'),
  masked_suffix text not null check (
    pg_catalog.btrim(masked_suffix) <> ''
    and pg_catalog.char_length(masked_suffix) between 2 and 8
  ),
  encryption_key_version text not null default 'v1'
    check (encryption_key_version ~ '^v[1-9][0-9]*$'),
  effective_from date,
  effective_to date,
  replaces_identifier_id uuid,
  replaced_at timestamptz,
  reason text not null check (
    pg_catalog.btrim(reason) <> '' and pg_catalog.char_length(reason) <= 2000
  ),
  created_by uuid not null references auth.users (id) on delete restrict,
  created_at timestamptz not null default pg_catalog.statement_timestamp(),
  unique (workspace_id, id),
  unique (workspace_id, party_id, identifier_type, jurisdiction, version),
  foreign key (workspace_id, party_id)
    references public.parties (workspace_id, id) on delete restrict,
  foreign key (workspace_id, replaces_identifier_id)
    references public.party_identifiers (workspace_id, id) on delete restrict,
  check (effective_to is null or effective_from is null or effective_to >= effective_from),
  check (
    (status = 'active' and replaced_at is null)
    or (status in ('replaced', 'revoked') and replaced_at is not null)
  )
);

create unique index party_identifiers_active_type_uidx
  on public.party_identifiers (
    workspace_id, party_id, identifier_type, jurisdiction
  ) where status = 'active';

create table public.party_relationships (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  workspace_id uuid not null references public.workspaces (id) on delete restrict,
  party_id uuid not null,
  related_party_id uuid not null,
  relationship_type text not null
    check (relationship_type ~ '^[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)*$'),
  version bigint not null default 1 check (version > 0),
  status text not null default 'active' check (status in ('active', 'ended')),
  effective_from date,
  effective_to date,
  ended_at timestamptz,
  created_by uuid not null references auth.users (id) on delete restrict,
  created_at timestamptz not null default pg_catalog.statement_timestamp(),
  unique (workspace_id, id),
  foreign key (workspace_id, party_id)
    references public.parties (workspace_id, id) on delete restrict,
  foreign key (workspace_id, related_party_id)
    references public.parties (workspace_id, id) on delete restrict,
  check (party_id <> related_party_id),
  check (effective_to is null or effective_from is null or effective_to >= effective_from),
  check (
    (status = 'active' and ended_at is null)
    or (status = 'ended' and ended_at is not null and effective_to is not null)
  )
);

create unique index party_relationships_active_uidx
  on public.party_relationships (
    workspace_id, party_id, related_party_id, relationship_type
  ) where status = 'active';

create table public.party_communication_preferences (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  workspace_id uuid not null references public.workspaces (id) on delete restrict,
  party_id uuid not null,
  channel_key text not null
    check (channel_key ~ '^[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)*$'),
  version bigint not null check (version > 0),
  allowed boolean not null,
  do_not_contact boolean not null default false,
  consent_status text not null default 'unknown'
    check (consent_status in ('unknown', 'granted', 'denied', 'withdrawn')),
  consent_source text check (
    consent_source is null or (
      pg_catalog.btrim(consent_source) <> ''
      and pg_catalog.char_length(consent_source) <= 500
    )
  ),
  status text not null default 'active' check (status in ('active', 'replaced')),
  replaces_preference_id uuid,
  replaced_at timestamptz,
  created_by uuid not null references auth.users (id) on delete restrict,
  created_at timestamptz not null default pg_catalog.statement_timestamp(),
  unique (workspace_id, id),
  unique (workspace_id, party_id, channel_key, version),
  foreign key (workspace_id, party_id)
    references public.parties (workspace_id, id) on delete restrict,
  foreign key (workspace_id, replaces_preference_id)
    references public.party_communication_preferences (workspace_id, id)
    on delete restrict,
  check (consent_status <> 'granted' or consent_source is not null),
  check (not do_not_contact or not allowed),
  check (
    (status = 'active' and replaced_at is null)
    or (status = 'replaced' and replaced_at is not null)
  )
);

create unique index party_communication_preferences_active_uidx
  on public.party_communication_preferences (workspace_id, party_id, channel_key)
  where status = 'active';

create table public.party_command_receipts (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  workspace_id uuid not null references public.workspaces (id) on delete restrict,
  actor_user_id uuid not null references auth.users (id) on delete restrict,
  command_type text not null check (
    command_type in (
      'm3_create_party', 'm3_add_party_contact', 'm3_add_party_address',
      'm3_replace_party_identifier', 'm3_add_party_relationship',
      'm3_update_party', 'm3_archive_party',
      'm3_set_party_communication_preference'
    )
  ),
  idempotency_key text not null check (
    pg_catalog.char_length(pg_catalog.btrim(idempotency_key)) between 8 and 200
  ),
  command_fingerprint text not null check (command_fingerprint ~ '^[0-9a-f]{64}$'),
  party_id uuid not null,
  result jsonb not null check (
    pg_catalog.jsonb_typeof(result) = 'object'
    and not app.job_payload_contains_forbidden_key(result)
  ),
  audit_event_id uuid not null,
  outbox_event_id uuid not null,
  created_at timestamptz not null default pg_catalog.statement_timestamp(),
  unique (workspace_id, id),
  unique (workspace_id, actor_user_id, command_type, idempotency_key),
  foreign key (workspace_id, party_id)
    references public.parties (workspace_id, id) on delete restrict,
  foreign key (workspace_id, audit_event_id)
    references public.audit_events (workspace_id, id) on delete restrict,
  foreign key (workspace_id, outbox_event_id)
    references public.outbox_events (workspace_id, id) on delete restrict
);

create index party_command_receipts_party_idx
  on public.party_command_receipts (workspace_id, party_id, created_at desc);

create function app.require_m3_crm_permission(
  p_workspace_id uuid,
  p_permission_key text,
  p_require_recent_aal2 boolean default false
)
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  actor_user_id uuid;
begin
  actor_user_id := app.require_vertical_slice_permission(
    p_workspace_id,
    p_permission_key,
    p_require_recent_aal2
  );
  if not app.workspace_entitlement_is_enabled(
    p_workspace_id,
    'crm',
    pg_catalog.statement_timestamp()
  ) then
    raise exception using
      errcode = '42501',
      message = 'CRM entitlement is not active';
  end if;
  return actor_user_id;
end;
$$;

create function app.can_read_m3_crm(
  p_workspace_id uuid,
  p_permission_key text default 'crm.read'
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select app.workspace_entitlement_is_enabled(
      p_workspace_id,
      'crm',
      pg_catalog.statement_timestamp()
    )
    and app.has_permission(p_workspace_id, p_permission_key);
$$;

create function app.m3_crm_identifier_runtime_key()
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  runtime_key text;
begin
  runtime_key := pg_catalog.current_setting(
    'app.crm_identifier_encryption_key',
    true
  );
  if runtime_key is null or pg_catalog.char_length(runtime_key) < 32 then
    raise exception using
      errcode = '55000',
      message = 'CRM identifier encryption key is unavailable';
  end if;
  return runtime_key;
end;
$$;

create function app.m3_crm_identifier_fingerprint(p_plaintext_value text)
returns text
language sql
stable
security definer
strict
set search_path = ''
as $$
  select pg_catalog.encode(
    extensions.hmac(
      pg_catalog.convert_to(p_plaintext_value, 'UTF8'),
      pg_catalog.convert_to(app.m3_crm_identifier_runtime_key(), 'UTF8'),
      'sha256'
    ),
    'hex'
  );
$$;

create function app.m3_crm_encrypt_identifier(p_plaintext_value text)
returns bytea
language sql
stable
security definer
strict
set search_path = ''
as $$
  select extensions.pgp_sym_encrypt(
    p_plaintext_value,
    app.m3_crm_identifier_runtime_key(),
    'cipher-algo=aes256, compress-algo=0'
  );
$$;

create function app.m3_crm_decrypt_identifier(p_encrypted_value bytea)
returns text
language sql
stable
security definer
strict
set search_path = ''
as $$
  select extensions.pgp_sym_decrypt(
    p_encrypted_value,
    app.m3_crm_identifier_runtime_key()
  );
$$;

create function app.append_m3_crm_outbox_event(
  p_workspace_id uuid,
  p_event_name text,
  p_party_id uuid,
  p_aggregate_version bigint,
  p_payload jsonb,
  p_actor_user_id uuid,
  p_correlation_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  event_id uuid;
begin
  if p_event_name !~ '^party\.[a-z][a-z0-9_]*$'
    or p_aggregate_version < 1
    or p_correlation_id is null
    or pg_catalog.jsonb_typeof(p_payload) <> 'object'
    or app.job_payload_contains_forbidden_key(p_payload) then
    raise exception using errcode = '23514', message = 'invalid CRM outbox event';
  end if;
  insert into public.outbox_events (
    workspace_id,
    event_name,
    aggregate_type,
    aggregate_id,
    aggregate_version,
    payload_schema_version,
    payload,
    actor_user_id,
    correlation_id
  ) values (
    p_workspace_id,
    p_event_name,
    'party',
    p_party_id,
    p_aggregate_version,
    1,
    p_payload,
    p_actor_user_id,
    p_correlation_id
  ) returning id into event_id;
  return event_id;
end;
$$;

create function app.assert_party_profile_type()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  expected_party_type text;
begin
  expected_party_type := case tg_table_name
    when 'party_person_profiles' then 'person'
    when 'party_organization_profiles' then 'organization'
    else null
  end;
  if expected_party_type is null or not exists (
    select 1
    from public.parties party
    where party.workspace_id = new.workspace_id
      and party.id = new.party_id
      and party.party_type = expected_party_type
  ) then
    raise exception using
      errcode = '23514',
      message = 'party profile type must match its workspace party';
  end if;
  return new;
end;
$$;

create function app.guard_party_version_history()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    raise exception using errcode = '55000', message = 'party history is append-only';
  end if;

  if tg_table_name in ('party_contacts', 'party_addresses')
    and old.status = 'active'
    and new.status in ('replaced', 'archived')
    and new.effective_to is not null
    and (pg_catalog.to_jsonb(new) - array[
      'status', 'effective_to', 'archived_at'
    ]::text[]) is not distinct from (pg_catalog.to_jsonb(old) - array[
      'status', 'effective_to', 'archived_at'
    ]::text[]) then
    return new;
  elsif tg_table_name = 'party_identifiers'
    and old.status = 'active'
    and new.status in ('replaced', 'revoked')
    and new.replaced_at is not null
    and (pg_catalog.to_jsonb(new) - array['status', 'replaced_at']::text[])
      is not distinct from
      (pg_catalog.to_jsonb(old) - array['status', 'replaced_at']::text[]) then
    return new;
  elsif tg_table_name = 'party_relationships'
    and old.status = 'active'
    and new.status = 'ended'
    and new.ended_at is not null
    and new.effective_to is not null
    and (pg_catalog.to_jsonb(new) - array[
      'status', 'effective_to', 'ended_at'
    ]::text[]) is not distinct from (pg_catalog.to_jsonb(old) - array[
      'status', 'effective_to', 'ended_at'
    ]::text[]) then
    return new;
  elsif tg_table_name = 'party_communication_preferences'
    and old.status = 'active'
    and new.status = 'replaced'
    and new.replaced_at is not null
    and (pg_catalog.to_jsonb(new) - array['status', 'replaced_at']::text[])
      is not distinct from
      (pg_catalog.to_jsonb(old) - array['status', 'replaced_at']::text[]) then
    return new;
  end if;

  raise exception using errcode = '55000', message = 'party history is append-only';
end;
$$;

create function app.prevent_party_command_receipt_mutation()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception using errcode = '55000', message = 'party command receipts are append-only';
end;
$$;

create function app.guard_legal_entity_lifecycle()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    raise exception using
      errcode = '55000',
      message = 'legal entities cannot be hard deleted';
  end if;

  if old.status = 'active'
    and new.status = 'retired'
    and new.version = old.version + 1
    and new.retired_at is not null
    and (pg_catalog.to_jsonb(new) - array[
      'status', 'version', 'retired_at'
    ]::text[]) is not distinct from (pg_catalog.to_jsonb(old) - array[
      'status', 'version', 'retired_at'
    ]::text[]) then
    return new;
  end if;

  raise exception using
    errcode = '55000',
    message = 'legal entity versions are immutable except for retirement';
end;
$$;

create function app.assert_legal_entity_organization_party()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.organization_party_id is not null and not exists (
    select 1
    from public.parties party
    where party.workspace_id = new.workspace_id
      and party.id = new.organization_party_id
      and party.party_type = 'organization'
      and party.status = 'active'
  ) then
    raise exception using
      errcode = '23514',
      message = 'legal entity organization party must be active and workspace-scoped';
  end if;
  return new;
end;
$$;

create trigger legal_entities_organization_party
before insert or update on public.legal_entities
for each row execute function app.assert_legal_entity_organization_party();

create trigger legal_entities_lifecycle
before update or delete on public.legal_entities
for each row execute function app.guard_legal_entity_lifecycle();

create trigger party_person_profiles_type
before insert or update on public.party_person_profiles
for each row execute function app.assert_party_profile_type();
create trigger party_organization_profiles_type
before insert or update on public.party_organization_profiles
for each row execute function app.assert_party_profile_type();

create trigger party_person_profiles_updated_at
before update on public.party_person_profiles
for each row execute function app.set_updated_at();
create trigger party_organization_profiles_updated_at
before update on public.party_organization_profiles
for each row execute function app.set_updated_at();

create trigger party_person_profiles_immutable_ownership
before update on public.party_person_profiles
for each row execute function app.enforce_immutable_columns(
  'party_id', 'workspace_id', 'created_at'
);
create trigger party_organization_profiles_immutable_ownership
before update on public.party_organization_profiles
for each row execute function app.enforce_immutable_columns(
  'party_id', 'workspace_id', 'created_at'
);

drop trigger parties_prevent_hard_delete on public.parties;
create trigger parties_prevent_hard_delete
before delete on public.parties
for each row execute function app.prevent_hard_delete();
create trigger party_person_profiles_prevent_hard_delete
before delete on public.party_person_profiles
for each row execute function app.prevent_hard_delete();
create trigger party_organization_profiles_prevent_hard_delete
before delete on public.party_organization_profiles
for each row execute function app.prevent_hard_delete();

create trigger party_contacts_history
before update or delete on public.party_contacts
for each row execute function app.guard_party_version_history();
create trigger party_addresses_history
before update or delete on public.party_addresses
for each row execute function app.guard_party_version_history();
create trigger party_identifiers_history
before update or delete on public.party_identifiers
for each row execute function app.guard_party_version_history();
create trigger party_relationships_history
before update or delete on public.party_relationships
for each row execute function app.guard_party_version_history();
create trigger party_communication_preferences_history
before update or delete on public.party_communication_preferences
for each row execute function app.guard_party_version_history();
create trigger party_command_receipts_append_only
before update or delete on public.party_command_receipts
for each row execute function app.prevent_party_command_receipt_mutation();

alter table public.legal_entities enable row level security;
alter table public.legal_entities force row level security;
alter table public.party_person_profiles enable row level security;
alter table public.party_person_profiles force row level security;
alter table public.party_organization_profiles enable row level security;
alter table public.party_organization_profiles force row level security;
alter table public.party_contacts enable row level security;
alter table public.party_contacts force row level security;
alter table public.party_addresses enable row level security;
alter table public.party_addresses force row level security;
alter table public.party_identifiers enable row level security;
alter table public.party_identifiers force row level security;
alter table public.party_relationships enable row level security;
alter table public.party_relationships force row level security;
alter table public.party_communication_preferences enable row level security;
alter table public.party_communication_preferences force row level security;
alter table public.party_command_receipts enable row level security;
alter table public.party_command_receipts force row level security;

drop policy parties_select on public.parties;
create policy parties_select
on public.parties
for select to authenticated
using (app.can_read_m3_crm(workspace_id, 'crm.read'));

create policy legal_entities_select
on public.legal_entities
for select to authenticated
using (
  app.has_permission(workspace_id, 'workspace.read')
  or app.has_permission(workspace_id, 'configuration.read')
);

create policy party_person_profiles_select
on public.party_person_profiles for select to authenticated
using (app.can_read_m3_crm(workspace_id, 'crm.read'));
create policy party_organization_profiles_select
on public.party_organization_profiles for select to authenticated
using (app.can_read_m3_crm(workspace_id, 'crm.read'));
create policy party_contacts_select
on public.party_contacts for select to authenticated
using (app.can_read_m3_crm(workspace_id, 'crm.read'));
create policy party_addresses_select
on public.party_addresses for select to authenticated
using (app.can_read_m3_crm(workspace_id, 'crm.read'));
create policy party_relationships_select
on public.party_relationships for select to authenticated
using (app.can_read_m3_crm(workspace_id, 'crm.read'));
create policy party_communication_preferences_select
on public.party_communication_preferences for select to authenticated
using (app.can_read_m3_crm(workspace_id, 'crm.read'));

revoke all on table
  public.legal_entities,
  public.party_person_profiles,
  public.party_organization_profiles,
  public.party_contacts,
  public.party_addresses,
  public.party_identifiers,
  public.party_relationships,
  public.party_communication_preferences,
  public.party_command_receipts
from public, anon, authenticated, service_role;

grant select on table public.legal_entities to authenticated;

grant select on table
  public.party_person_profiles,
  public.party_organization_profiles,
  public.party_contacts,
  public.party_addresses,
  public.party_relationships,
  public.party_communication_preferences
to authenticated;

grant select on table
  public.legal_entities,
  public.party_person_profiles,
  public.party_organization_profiles,
  public.party_contacts,
  public.party_addresses,
  public.party_identifiers,
  public.party_relationships,
  public.party_communication_preferences,
  public.party_command_receipts
to service_role;

create function app.m3_list_parties(p_workspace_id uuid)
returns table (
  party_id uuid,
  party_type text,
  display_name text,
  preferred_locale text,
  status text,
  version bigint
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform app.require_m3_crm_permission(p_workspace_id, 'crm.read', false);
  return query
  select
    party.id,
    party.party_type,
    party.display_name,
    coalesce(
      person.preferred_locale,
      organization.preferred_locale,
      case when workspace.default_locale like 'fr%' then 'fr' else 'en' end
    ),
    party.status,
    party.version
  from public.parties party
  join public.workspaces workspace on workspace.id = party.workspace_id
  left join public.party_person_profiles person
    on person.workspace_id = party.workspace_id and person.party_id = party.id
  left join public.party_organization_profiles organization
    on organization.workspace_id = party.workspace_id
   and organization.party_id = party.id
  where party.workspace_id = p_workspace_id
  order by pg_catalog.lower(party.display_name), party.id
  limit 500;
end;
$$;

create function app.m3_get_party(
  p_workspace_id uuid,
  p_party_id uuid
)
returns table (
  party_id uuid,
  party_type text,
  display_name text,
  preferred_locale text,
  status text,
  version bigint,
  contacts jsonb,
  addresses jsonb,
  identifiers jsonb,
  relationships jsonb,
  preferences jsonb,
  profile jsonb
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform app.require_m3_crm_permission(p_workspace_id, 'crm.read', false);
  if not exists (
    select 1 from public.parties party
    where party.workspace_id = p_workspace_id and party.id = p_party_id
  ) then
    raise exception using errcode = '23503', message = 'party does not exist';
  end if;

  return query
  select
    party.id,
    party.party_type,
    party.display_name,
    coalesce(
      person.preferred_locale,
      organization.preferred_locale,
      case when workspace.default_locale like 'fr%' then 'fr' else 'en' end
    ),
    party.status,
    party.version,
    coalesce((
      select pg_catalog.jsonb_agg(
        pg_catalog.jsonb_build_object(
          'contactId', contact.id,
          'contactType', contact.contact_type,
          'value', contact.value,
          'isPrimary', contact.is_primary,
          'isPreferred', contact.is_preferred,
          'consentStatus', contact.consent_status,
          'doNotContact', contact.do_not_contact
        ) order by contact.is_primary desc, contact.created_at, contact.id
      )
      from (
        select candidate.*
        from public.party_contacts candidate
        where candidate.workspace_id = party.workspace_id
          and candidate.party_id = party.id
          and candidate.status = 'active'
        order by candidate.is_primary desc, candidate.created_at, candidate.id
        limit 100
      ) contact
    ), '[]'::jsonb),
    coalesce((
      select pg_catalog.jsonb_agg(
        pg_catalog.jsonb_build_object(
          'addressId', address.id,
          'addressType', address.address_type,
          'line1', address.line_1,
          'line2', address.line_2,
          'locality', address.locality,
          'region', address.region,
          'postalCode', address.postal_code,
          'countryCode', address.country_code::text,
          'isPrimary', address.is_primary
        ) order by address.is_primary desc, address.created_at, address.id
      )
      from (
        select candidate.*
        from public.party_addresses candidate
        where candidate.workspace_id = party.workspace_id
          and candidate.party_id = party.id
          and candidate.status = 'active'
        order by candidate.is_primary desc, candidate.created_at, candidate.id
        limit 100
      ) address
    ), '[]'::jsonb),
    coalesce((
      select pg_catalog.jsonb_agg(
        pg_catalog.jsonb_build_object(
          'identifierId', identifier.id,
          'identifierType', identifier.identifier_type,
          'jurisdiction', identifier.jurisdiction,
          'maskedValue', '********' || identifier.masked_suffix
        ) order by identifier.identifier_type, identifier.jurisdiction
      )
      from (
        select candidate.*
        from public.party_identifiers candidate
        where candidate.workspace_id = party.workspace_id
          and candidate.party_id = party.id
          and candidate.status = 'active'
        order by candidate.identifier_type, candidate.jurisdiction, candidate.id
        limit 100
      ) identifier
    ), '[]'::jsonb),
    coalesce((
      select pg_catalog.jsonb_agg(
        pg_catalog.jsonb_build_object(
          'relationshipId', relationship.id,
          'relatedPartyId', relationship.related_party_id,
          'relationshipType', relationship.relationship_type,
          'effectiveFrom', case when relationship.effective_from is null
            then null else relationship.effective_from::text end,
          'effectiveTo', case when relationship.effective_to is null
            then null else relationship.effective_to::text end,
          'version', relationship.version
        ) order by relationship.relationship_type, relationship.created_at,
          relationship.id
      )
      from (
        select candidate.*
        from public.party_relationships candidate
        where candidate.workspace_id = party.workspace_id
          and candidate.party_id = party.id
          and candidate.status = 'active'
        order by candidate.relationship_type, candidate.created_at, candidate.id
        limit 100
      ) relationship
    ), '[]'::jsonb),
    coalesce((
      select pg_catalog.jsonb_agg(
        pg_catalog.jsonb_build_object(
          'preferenceId', preference.id,
          'channelKey', preference.channel_key,
          'allowed', preference.allowed,
          'doNotContact', preference.do_not_contact,
          'consentStatus', preference.consent_status,
          'consentSource', preference.consent_source,
          'version', preference.version
        ) order by preference.channel_key, preference.version
      )
      from (
        select candidate.*
        from public.party_communication_preferences candidate
        where candidate.workspace_id = party.workspace_id
          and candidate.party_id = party.id
          and candidate.status = 'active'
        order by candidate.channel_key, candidate.version, candidate.id
        limit 100
      ) preference
    ), '[]'::jsonb),
    case party.party_type
      when 'person' then pg_catalog.jsonb_build_object(
        'givenName', person.given_name,
        'familyName', person.family_name,
        'preferredName', person.preferred_name,
        'birthDate', case when person.birth_date is null
          then null else person.birth_date::text end
      )
      when 'organization' then pg_catalog.jsonb_build_object(
        'legalName', organization.legal_name,
        'registrationName', organization.registration_name
      )
      else '{}'::jsonb
    end
  from public.parties party
  join public.workspaces workspace on workspace.id = party.workspace_id
  left join public.party_person_profiles person
    on person.workspace_id = party.workspace_id and person.party_id = party.id
  left join public.party_organization_profiles organization
    on organization.workspace_id = party.workspace_id
   and organization.party_id = party.id
  where party.workspace_id = p_workspace_id and party.id = p_party_id;
end;
$$;

create function app.m3_create_party(
  p_workspace_id uuid,
  p_idempotency_key text,
  p_party_type text,
  p_display_name text,
  p_preferred_locale text,
  p_given_name text,
  p_family_name text,
  p_preferred_name text,
  p_birth_date date,
  p_legal_name text,
  p_registration_name text,
  p_request_id text,
  p_correlation_id uuid
)
returns table (
  party_id uuid,
  aggregate_version bigint,
  audit_event_id uuid,
  outbox_event_id uuid,
  replayed boolean
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_user_id uuid;
  normalized_idempotency_key text;
  normalized_display_name text;
  normalized_given_name text;
  normalized_family_name text;
  normalized_preferred_name text;
  normalized_legal_name text;
  normalized_registration_name text;
  request_fingerprint text;
  existing_receipt public.party_command_receipts%rowtype;
  new_party_id uuid;
  new_audit_event_id uuid;
  new_outbox_event_id uuid;
  result_payload jsonb;
begin
  actor_user_id := app.require_m3_crm_permission(
    p_workspace_id, 'crm.create', false
  );
  normalized_idempotency_key := pg_catalog.btrim(coalesce(p_idempotency_key, ''));
  normalized_display_name := pg_catalog.regexp_replace(
    pg_catalog.btrim(coalesce(p_display_name, '')), '\s+', ' ', 'g'
  );
  normalized_given_name := nullif(pg_catalog.btrim(p_given_name), '');
  normalized_family_name := nullif(pg_catalog.btrim(p_family_name), '');
  normalized_preferred_name := nullif(pg_catalog.btrim(p_preferred_name), '');
  normalized_legal_name := nullif(pg_catalog.btrim(p_legal_name), '');
  normalized_registration_name := nullif(
    pg_catalog.btrim(p_registration_name), ''
  );

  if pg_catalog.char_length(normalized_idempotency_key) not between 8 and 200
    or normalized_display_name = ''
    or pg_catalog.char_length(normalized_display_name) > 200
    or p_party_type not in ('person', 'organization')
    or p_preferred_locale not in ('en', 'fr')
    or p_correlation_id is null
    or (p_request_id is not null and pg_catalog.char_length(p_request_id) > 200)
    or (
      p_party_type = 'person' and (
        normalized_given_name is null
        or pg_catalog.char_length(normalized_given_name) > 100
        or normalized_family_name is null
        or pg_catalog.char_length(normalized_family_name) > 100
        or (
          normalized_preferred_name is not null
          and pg_catalog.char_length(normalized_preferred_name) > 100
        )
        or normalized_legal_name is not null
        or normalized_registration_name is not null
      )
    )
    or (
      p_party_type = 'organization' and (
        normalized_legal_name is null
        or pg_catalog.char_length(normalized_legal_name) > 200
        or (
          normalized_registration_name is not null
          and pg_catalog.char_length(normalized_registration_name) > 200
        )
        or normalized_given_name is not null
        or normalized_family_name is not null
        or normalized_preferred_name is not null
        or p_birth_date is not null
      )
    ) then
    raise exception using errcode = '22023', message = 'invalid party command';
  end if;

  request_fingerprint := app.vertical_slice_fingerprint(
    pg_catalog.jsonb_build_object(
      'partyType', p_party_type,
      'displayName', normalized_display_name,
      'preferredLocale', p_preferred_locale,
      'givenName', normalized_given_name,
      'familyName', normalized_family_name,
      'preferredName', normalized_preferred_name,
      'birthDate', p_birth_date,
      'legalName', normalized_legal_name,
      'registrationName', normalized_registration_name
    )
  );
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      p_workspace_id::text || E'\x1fm3_create_party\x1f'
        || actor_user_id::text || E'\x1f' || normalized_idempotency_key,
      0
    )
  );
  select receipt.* into existing_receipt
  from public.party_command_receipts receipt
  where receipt.workspace_id = p_workspace_id
    and receipt.actor_user_id = app.current_user_id()
    and receipt.command_type = 'm3_create_party'
    and receipt.idempotency_key = normalized_idempotency_key;
  if found then
    if existing_receipt.command_fingerprint <> request_fingerprint then
      raise exception using errcode = '23505',
        message = 'party idempotency key was used for different create input';
    end if;
    return query select
      (existing_receipt.result ->> 'party_id')::uuid,
      (existing_receipt.result ->> 'aggregate_version')::bigint,
      (existing_receipt.result ->> 'audit_event_id')::uuid,
      (existing_receipt.result ->> 'outbox_event_id')::uuid,
      true;
    return;
  end if;
  if exists (
    select 1 from public.parties party
    where party.workspace_id = p_workspace_id
      and party.idempotency_actor_user_id = actor_user_id
      and party.idempotency_key = normalized_idempotency_key
  ) then
    raise exception using
      errcode = '23505',
      message = 'party idempotency key belongs to an incompatible create command';
  end if;

  new_party_id := pg_catalog.gen_random_uuid();
  insert into public.parties (
    id, workspace_id, party_type, display_name, status, version,
    idempotency_key, idempotency_actor_user_id, command_fingerprint, created_by
  ) values (
    new_party_id, p_workspace_id, p_party_type, normalized_display_name,
    'active', 1, normalized_idempotency_key, actor_user_id,
    request_fingerprint, actor_user_id
  );
  if p_party_type = 'person' then
    insert into public.party_person_profiles (
      party_id, workspace_id, given_name, family_name, preferred_name,
      birth_date, preferred_locale, version
    ) values (
      new_party_id, p_workspace_id, normalized_given_name,
      normalized_family_name, normalized_preferred_name, p_birth_date,
      p_preferred_locale, 1
    );
  else
    insert into public.party_organization_profiles (
      party_id, workspace_id, legal_name, registration_name,
      preferred_locale, version
    ) values (
      new_party_id, p_workspace_id, normalized_legal_name,
      normalized_registration_name, p_preferred_locale, 1
    );
  end if;

  new_audit_event_id := app.write_audit_event(
    p_workspace_id => p_workspace_id,
    p_action => 'party.created',
    p_entity_type => 'party',
    p_entity_id => new_party_id,
    p_actor_user_id => actor_user_id,
    p_actor_type => 'user',
    p_after_data => pg_catalog.jsonb_build_object(
      'party_type', p_party_type,
      'display_name', normalized_display_name,
      'preferred_locale', p_preferred_locale,
      'status', 'active',
      'version', 1
    ),
    p_request_id => p_request_id,
    p_correlation_id => p_correlation_id,
    p_auth_assurance => coalesce(auth.jwt() ->> 'aal', 'unknown'),
    p_metadata => pg_catalog.jsonb_build_object(
      'idempotency_key', normalized_idempotency_key
    )
  );
  new_outbox_event_id := app.append_m3_crm_outbox_event(
    p_workspace_id,
    'party.created',
    new_party_id,
    1,
    pg_catalog.jsonb_build_object(
      'partyId', new_party_id,
      'partyType', p_party_type,
      'aggregateVersion', 1
    ),
    actor_user_id,
    p_correlation_id
  );
  result_payload := pg_catalog.jsonb_build_object(
    'party_id', new_party_id,
    'aggregate_version', 1,
    'audit_event_id', new_audit_event_id,
    'outbox_event_id', new_outbox_event_id
  );
  insert into public.party_command_receipts (
    workspace_id, actor_user_id, command_type, idempotency_key,
    command_fingerprint, party_id, result, audit_event_id, outbox_event_id
  ) values (
    p_workspace_id, actor_user_id, 'm3_create_party', normalized_idempotency_key,
    request_fingerprint, new_party_id, result_payload,
    new_audit_event_id, new_outbox_event_id
  );
  return query select
    new_party_id, 1::bigint, new_audit_event_id, new_outbox_event_id, false;
end;
$$;

create function app.m3_add_party_contact(
  p_workspace_id uuid,
  p_idempotency_key text,
  p_party_id uuid,
  p_contact_type text,
  p_value text,
  p_is_primary boolean,
  p_is_preferred boolean,
  p_consent_status text,
  p_consent_source text,
  p_do_not_contact boolean,
  p_request_id text,
  p_correlation_id uuid
)
returns table (
  contact_id uuid,
  party_id uuid,
  aggregate_version bigint,
  audit_event_id uuid,
  outbox_event_id uuid,
  replayed boolean
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_user_id uuid;
  normalized_key text;
  normalized_value text;
  normalized_consent_source text;
  request_fingerprint text;
  existing_receipt public.party_command_receipts%rowtype;
  party_row public.parties%rowtype;
  next_version bigint;
  new_contact_id uuid;
  new_audit_event_id uuid;
  new_outbox_event_id uuid;
  result_payload jsonb;
begin
  actor_user_id := app.require_m3_crm_permission(
    p_workspace_id, 'crm.update', false
  );
  normalized_key := pg_catalog.btrim(coalesce(p_idempotency_key, ''));
  normalized_consent_source := nullif(
    pg_catalog.btrim(p_consent_source), ''
  );
  normalized_value := case p_contact_type
    when 'email' then pg_catalog.lower(pg_catalog.btrim(coalesce(p_value, '')))
    when 'phone' then pg_catalog.regexp_replace(
      pg_catalog.btrim(coalesce(p_value, '')), '[\s().-]', '', 'g'
    )
    else ''
  end;
  if pg_catalog.char_length(normalized_key) not between 8 and 200
    or p_contact_type not in ('email', 'phone')
    or p_is_primary is null or p_is_preferred is null
    or p_do_not_contact is null
    or p_consent_status not in ('unknown', 'granted', 'denied', 'withdrawn')
    or (p_consent_status = 'granted' and normalized_consent_source is null)
    or (
      normalized_consent_source is not null
      and pg_catalog.char_length(normalized_consent_source) > 500
    )
    or (
      p_contact_type = 'email'
      and (
        pg_catalog.char_length(normalized_value) > 320
        or normalized_value !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
      )
    )
    or (
      p_contact_type = 'phone'
      and normalized_value !~ '^\+[1-9][0-9]{7,14}$'
    )
    or p_correlation_id is null
    or (p_request_id is not null and pg_catalog.char_length(p_request_id) > 200) then
    raise exception using errcode = '22023', message = 'invalid party contact command';
  end if;
  request_fingerprint := app.vertical_slice_fingerprint(
    pg_catalog.jsonb_build_object(
      'partyId', p_party_id,
      'contactType', p_contact_type,
      'normalizedValue', normalized_value,
      'isPrimary', p_is_primary,
      'isPreferred', p_is_preferred,
      'consentStatus', p_consent_status,
      'consentSource', normalized_consent_source,
      'doNotContact', p_do_not_contact
    )
  );
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      p_workspace_id::text || E'\x1fm3_add_party_contact\x1f'
        || actor_user_id::text || E'\x1f' || normalized_key,
      0
    )
  );
  select receipt.* into existing_receipt
  from public.party_command_receipts receipt
  where receipt.workspace_id = p_workspace_id
    and receipt.actor_user_id = app.current_user_id()
    and receipt.command_type = 'm3_add_party_contact'
    and receipt.idempotency_key = normalized_key;
  if found then
    if existing_receipt.command_fingerprint <> request_fingerprint then
      raise exception using errcode = '23505',
        message = 'party idempotency key was used for different contact input';
    end if;
    return query select
      (existing_receipt.result ->> 'contact_id')::uuid,
      (existing_receipt.result ->> 'party_id')::uuid,
      (existing_receipt.result ->> 'aggregate_version')::bigint,
      (existing_receipt.result ->> 'audit_event_id')::uuid,
      (existing_receipt.result ->> 'outbox_event_id')::uuid,
      true;
    return;
  end if;

  select party.* into party_row
  from public.parties party
  where party.workspace_id = p_workspace_id and party.id = p_party_id
  for update;
  if not found or party_row.status <> 'active' then
    raise exception using errcode = '23514', message = 'active workspace party is required';
  end if;
  next_version := party_row.version + 1;
  new_contact_id := pg_catalog.gen_random_uuid();
  insert into public.party_contacts (
    id, workspace_id, party_id, logical_contact_id, version,
    contact_type, value, normalized_value, is_primary, is_preferred,
    do_not_contact, consent_status, consent_source, consent_recorded_by,
    created_by
  ) values (
    new_contact_id, p_workspace_id, p_party_id, new_contact_id, 1,
    p_contact_type, pg_catalog.btrim(p_value), normalized_value,
    p_is_primary, p_is_preferred, p_do_not_contact, p_consent_status,
    normalized_consent_source, actor_user_id, actor_user_id
  );
  update public.parties set version = next_version
  where workspace_id = p_workspace_id and id = p_party_id;

  new_audit_event_id := app.write_audit_event(
    p_workspace_id => p_workspace_id,
    p_action => 'party.contact_added',
    p_entity_type => 'party',
    p_entity_id => p_party_id,
    p_actor_user_id => actor_user_id,
    p_actor_type => 'user',
    p_before_data => pg_catalog.jsonb_build_object('version', party_row.version),
    p_after_data => pg_catalog.jsonb_build_object(
      'version', next_version,
      'contact_id', new_contact_id,
      'contact_type', p_contact_type,
      'consent_status', p_consent_status,
      'is_primary', p_is_primary,
      'is_preferred', p_is_preferred,
      'do_not_contact', p_do_not_contact
    ),
    p_request_id => p_request_id,
    p_correlation_id => p_correlation_id,
    p_auth_assurance => coalesce(auth.jwt() ->> 'aal', 'unknown'),
    p_metadata => pg_catalog.jsonb_build_object('idempotency_key', normalized_key)
  );
  new_outbox_event_id := app.append_m3_crm_outbox_event(
    p_workspace_id, 'party.contact_added', p_party_id, next_version,
    pg_catalog.jsonb_build_object(
      'partyId', p_party_id,
      'contactId', new_contact_id,
      'contactType', p_contact_type,
      'aggregateVersion', next_version
    ), actor_user_id, p_correlation_id
  );
  result_payload := pg_catalog.jsonb_build_object(
    'contact_id', new_contact_id,
    'party_id', p_party_id,
    'aggregate_version', next_version,
    'audit_event_id', new_audit_event_id,
    'outbox_event_id', new_outbox_event_id
  );
  insert into public.party_command_receipts (
    workspace_id, actor_user_id, command_type, idempotency_key,
    command_fingerprint, party_id, result, audit_event_id, outbox_event_id
  ) values (
    p_workspace_id, actor_user_id, 'm3_add_party_contact', normalized_key,
    request_fingerprint, p_party_id, result_payload,
    new_audit_event_id, new_outbox_event_id
  );
  return query select
    new_contact_id, p_party_id, next_version,
    new_audit_event_id, new_outbox_event_id, false;
end;
$$;

create function app.m3_add_party_address(
  p_workspace_id uuid,
  p_idempotency_key text,
  p_party_id uuid,
  p_address_type text,
  p_line_1 text,
  p_line_2 text,
  p_locality text,
  p_region text,
  p_postal_code text,
  p_country_code text,
  p_is_primary boolean,
  p_request_id text,
  p_correlation_id uuid
)
returns table (
  address_id uuid,
  party_id uuid,
  aggregate_version bigint,
  audit_event_id uuid,
  outbox_event_id uuid,
  replayed boolean
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_user_id uuid;
  normalized_key text;
  normalized_line_1 text;
  normalized_line_2 text;
  normalized_locality text;
  normalized_region text;
  normalized_postal_code text;
  normalized_country_code text;
  request_fingerprint text;
  existing_receipt public.party_command_receipts%rowtype;
  party_row public.parties%rowtype;
  next_version bigint;
  new_address_id uuid;
  new_audit_event_id uuid;
  new_outbox_event_id uuid;
  result_payload jsonb;
begin
  actor_user_id := app.require_m3_crm_permission(
    p_workspace_id, 'crm.update', false
  );
  normalized_key := pg_catalog.btrim(coalesce(p_idempotency_key, ''));
  normalized_line_1 := pg_catalog.btrim(coalesce(p_line_1, ''));
  normalized_line_2 := nullif(pg_catalog.btrim(p_line_2), '');
  normalized_locality := pg_catalog.btrim(coalesce(p_locality, ''));
  normalized_region := pg_catalog.btrim(coalesce(p_region, ''));
  normalized_postal_code := pg_catalog.btrim(coalesce(p_postal_code, ''));
  normalized_country_code := pg_catalog.upper(pg_catalog.btrim(coalesce(p_country_code, '')));
  if pg_catalog.char_length(normalized_key) not between 8 and 200
    or coalesce(p_address_type, '')
      !~ '^[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)*$'
    or normalized_line_1 = '' or pg_catalog.char_length(normalized_line_1) > 200
    or (normalized_line_2 is not null and pg_catalog.char_length(normalized_line_2) > 200)
    or normalized_locality = '' or pg_catalog.char_length(normalized_locality) > 100
    or normalized_region = '' or pg_catalog.char_length(normalized_region) > 100
    or normalized_postal_code = '' or pg_catalog.char_length(normalized_postal_code) > 32
    or normalized_country_code !~ '^[A-Z]{2}$'
    or p_is_primary is null
    or p_correlation_id is null
    or (p_request_id is not null and pg_catalog.char_length(p_request_id) > 200) then
    raise exception using errcode = '22023', message = 'invalid party address command';
  end if;
  request_fingerprint := app.vertical_slice_fingerprint(
    pg_catalog.jsonb_build_object(
      'partyId', p_party_id,
      'addressType', p_address_type,
      'line1', normalized_line_1,
      'line2', normalized_line_2,
      'locality', normalized_locality,
      'region', normalized_region,
      'postalCode', normalized_postal_code,
      'countryCode', normalized_country_code,
      'isPrimary', p_is_primary
    )
  );
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      p_workspace_id::text || E'\x1fm3_add_party_address\x1f'
        || actor_user_id::text || E'\x1f' || normalized_key,
      0
    )
  );
  select receipt.* into existing_receipt
  from public.party_command_receipts receipt
  where receipt.workspace_id = p_workspace_id
    and receipt.actor_user_id = app.current_user_id()
    and receipt.command_type = 'm3_add_party_address'
    and receipt.idempotency_key = normalized_key;
  if found then
    if existing_receipt.command_fingerprint <> request_fingerprint then
      raise exception using errcode = '23505',
        message = 'party idempotency key was used for different address input';
    end if;
    return query select
      (existing_receipt.result ->> 'address_id')::uuid,
      (existing_receipt.result ->> 'party_id')::uuid,
      (existing_receipt.result ->> 'aggregate_version')::bigint,
      (existing_receipt.result ->> 'audit_event_id')::uuid,
      (existing_receipt.result ->> 'outbox_event_id')::uuid,
      true;
    return;
  end if;
  select party.* into party_row
  from public.parties party
  where party.workspace_id = p_workspace_id and party.id = p_party_id
  for update;
  if not found or party_row.status <> 'active' then
    raise exception using errcode = '23514', message = 'active workspace party is required';
  end if;
  next_version := party_row.version + 1;
  new_address_id := pg_catalog.gen_random_uuid();
  insert into public.party_addresses (
    id, workspace_id, party_id, logical_address_id, version, address_type,
    line_1, line_2, locality, region, postal_code, country_code,
    is_primary, created_by
  ) values (
    new_address_id, p_workspace_id, p_party_id, new_address_id, 1,
    p_address_type, normalized_line_1, normalized_line_2,
    normalized_locality, normalized_region, normalized_postal_code,
    normalized_country_code, p_is_primary, actor_user_id
  );
  update public.parties set version = next_version
  where workspace_id = p_workspace_id and id = p_party_id;
  new_audit_event_id := app.write_audit_event(
    p_workspace_id => p_workspace_id,
    p_action => 'party.address_added',
    p_entity_type => 'party',
    p_entity_id => p_party_id,
    p_actor_user_id => actor_user_id,
    p_actor_type => 'user',
    p_before_data => pg_catalog.jsonb_build_object('version', party_row.version),
    p_after_data => pg_catalog.jsonb_build_object(
      'version', next_version,
      'address_id', new_address_id,
      'address_type', p_address_type,
      'country_code', normalized_country_code,
      'is_primary', p_is_primary
    ),
    p_request_id => p_request_id,
    p_correlation_id => p_correlation_id,
    p_auth_assurance => coalesce(auth.jwt() ->> 'aal', 'unknown'),
    p_metadata => pg_catalog.jsonb_build_object('idempotency_key', normalized_key)
  );
  new_outbox_event_id := app.append_m3_crm_outbox_event(
    p_workspace_id, 'party.address_added', p_party_id, next_version,
    pg_catalog.jsonb_build_object(
      'partyId', p_party_id,
      'addressId', new_address_id,
      'addressType', p_address_type,
      'aggregateVersion', next_version
    ), actor_user_id, p_correlation_id
  );
  result_payload := pg_catalog.jsonb_build_object(
    'address_id', new_address_id,
    'party_id', p_party_id,
    'aggregate_version', next_version,
    'audit_event_id', new_audit_event_id,
    'outbox_event_id', new_outbox_event_id
  );
  insert into public.party_command_receipts (
    workspace_id, actor_user_id, command_type, idempotency_key,
    command_fingerprint, party_id, result, audit_event_id, outbox_event_id
  ) values (
    p_workspace_id, actor_user_id, 'm3_add_party_address', normalized_key,
    request_fingerprint, p_party_id, result_payload,
    new_audit_event_id, new_outbox_event_id
  );
  return query select
    new_address_id, p_party_id, next_version,
    new_audit_event_id, new_outbox_event_id, false;
end;
$$;

create function app.m3_add_party_relationship(
  p_workspace_id uuid,
  p_idempotency_key text,
  p_party_id uuid,
  p_related_party_id uuid,
  p_relationship_type text,
  p_effective_from date,
  p_effective_to date,
  p_request_id text,
  p_correlation_id uuid
)
returns table (
  relationship_id uuid,
  party_id uuid,
  aggregate_version bigint,
  audit_event_id uuid,
  outbox_event_id uuid,
  replayed boolean
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_user_id uuid;
  normalized_key text;
  normalized_relationship_type text;
  request_fingerprint text;
  existing_receipt public.party_command_receipts%rowtype;
  party_row public.parties%rowtype;
  next_version bigint;
  new_relationship_id uuid;
  new_audit_event_id uuid;
  new_outbox_event_id uuid;
  result_payload jsonb;
begin
  actor_user_id := app.require_m3_crm_permission(
    p_workspace_id,
    'crm.update',
    false
  );
  normalized_key := pg_catalog.btrim(p_idempotency_key);
  normalized_relationship_type := pg_catalog.btrim(p_relationship_type);
  if p_party_id is null
    or p_related_party_id is null
    or p_party_id = p_related_party_id
    or pg_catalog.char_length(normalized_key) not between 8 and 200
    or normalized_relationship_type
      !~ '^[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)*$'
    or (p_effective_to is not null and p_effective_from is not null
      and p_effective_to < p_effective_from)
    or p_correlation_id is null
    or (p_request_id is not null and pg_catalog.char_length(p_request_id) > 200) then
    raise exception using errcode = '22023', message = 'invalid party relationship command';
  end if;
  request_fingerprint := app.vertical_slice_fingerprint(
    pg_catalog.jsonb_build_object(
      'partyId', p_party_id,
      'relatedPartyId', p_related_party_id,
      'relationshipType', normalized_relationship_type,
      'effectiveFrom', p_effective_from,
      'effectiveTo', p_effective_to
    )
  );
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      p_workspace_id::text || E'\x1fm3_add_party_relationship\x1f'
        || actor_user_id::text || E'\x1f' || normalized_key,
      0
    )
  );
  select receipt.* into existing_receipt
  from public.party_command_receipts receipt
  where receipt.workspace_id = p_workspace_id
    and receipt.actor_user_id = app.current_user_id()
    and receipt.command_type = 'm3_add_party_relationship'
    and receipt.idempotency_key = normalized_key;
  if found then
    if existing_receipt.command_fingerprint <> request_fingerprint then
      raise exception using
        errcode = '23505',
        message = 'party idempotency key was used for different relationship input';
    end if;
    return query select
      (existing_receipt.result ->> 'relationship_id')::uuid,
      (existing_receipt.result ->> 'party_id')::uuid,
      (existing_receipt.result ->> 'aggregate_version')::bigint,
      (existing_receipt.result ->> 'audit_event_id')::uuid,
      (existing_receipt.result ->> 'outbox_event_id')::uuid,
      true;
    return;
  end if;

  select party.* into party_row
  from public.parties party
  where party.workspace_id = p_workspace_id and party.id = p_party_id
  for update;
  if not found or party_row.status <> 'active' then
    raise exception using errcode = '23514', message = 'active workspace party is required';
  end if;
  if not exists (
    select 1
    from public.parties related_party
    where related_party.workspace_id = p_workspace_id
      and related_party.id = p_related_party_id
      and related_party.status = 'active'
  ) then
    raise exception using
      errcode = '23514',
      message = 'related party must be active in the same workspace';
  end if;

  next_version := party_row.version + 1;
  new_relationship_id := pg_catalog.gen_random_uuid();
  insert into public.party_relationships (
    id, workspace_id, party_id, related_party_id, relationship_type,
    version, effective_from, effective_to, created_by
  ) values (
    new_relationship_id, p_workspace_id, p_party_id, p_related_party_id,
    normalized_relationship_type, 1, p_effective_from, p_effective_to,
    actor_user_id
  );
  update public.parties set version = next_version
  where workspace_id = p_workspace_id and id = p_party_id;

  new_audit_event_id := app.write_audit_event(
    p_workspace_id => p_workspace_id,
    p_action => 'party.relationship_added',
    p_entity_type => 'party',
    p_entity_id => p_party_id,
    p_actor_user_id => actor_user_id,
    p_actor_type => 'user',
    p_before_data => pg_catalog.jsonb_build_object('version', party_row.version),
    p_after_data => pg_catalog.jsonb_build_object(
      'version', next_version,
      'relationship_id', new_relationship_id,
      'related_party_id', p_related_party_id,
      'relationship_type', normalized_relationship_type
    ),
    p_request_id => p_request_id,
    p_correlation_id => p_correlation_id,
    p_auth_assurance => coalesce(auth.jwt() ->> 'aal', 'unknown'),
    p_metadata => pg_catalog.jsonb_build_object('idempotency_key', normalized_key)
  );
  new_outbox_event_id := app.append_m3_crm_outbox_event(
    p_workspace_id,
    'party.relationship_added',
    p_party_id,
    next_version,
    pg_catalog.jsonb_build_object(
      'partyId', p_party_id,
      'relationshipId', new_relationship_id,
      'relatedPartyId', p_related_party_id,
      'relationshipType', normalized_relationship_type,
      'aggregateVersion', next_version
    ),
    actor_user_id,
    p_correlation_id
  );
  result_payload := pg_catalog.jsonb_build_object(
    'relationship_id', new_relationship_id,
    'party_id', p_party_id,
    'aggregate_version', next_version,
    'audit_event_id', new_audit_event_id,
    'outbox_event_id', new_outbox_event_id
  );
  insert into public.party_command_receipts (
    workspace_id, actor_user_id, command_type, idempotency_key,
    command_fingerprint, party_id, result, audit_event_id, outbox_event_id
  ) values (
    p_workspace_id, actor_user_id, 'm3_add_party_relationship', normalized_key,
    request_fingerprint, p_party_id, result_payload,
    new_audit_event_id, new_outbox_event_id
  );
  return query select
    new_relationship_id,
    p_party_id,
    next_version,
    new_audit_event_id,
    new_outbox_event_id,
    false;
end;
$$;

create function app.m3_set_party_communication_preference(
  p_workspace_id uuid,
  p_idempotency_key text,
  p_party_id uuid,
  p_expected_version bigint,
  p_channel_key text,
  p_allowed boolean,
  p_do_not_contact boolean,
  p_consent_status text,
  p_consent_source text,
  p_request_id text,
  p_correlation_id uuid
)
returns table (
  preference_id uuid,
  party_id uuid,
  aggregate_version bigint,
  audit_event_id uuid,
  outbox_event_id uuid,
  replayed boolean
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_user_id uuid;
  normalized_key text;
  normalized_channel_key text;
  normalized_consent_source text;
  request_fingerprint text;
  existing_receipt public.party_command_receipts%rowtype;
  party_row public.parties%rowtype;
  current_preference public.party_communication_preferences%rowtype;
  next_preference_version bigint;
  next_aggregate_version bigint;
  new_preference_id uuid;
  new_audit_event_id uuid;
  new_outbox_event_id uuid;
  result_payload jsonb;
begin
  actor_user_id := app.require_m3_crm_permission(
    p_workspace_id,
    'crm.update',
    false
  );
  normalized_key := pg_catalog.btrim(p_idempotency_key);
  normalized_channel_key := pg_catalog.btrim(p_channel_key);
  normalized_consent_source := nullif(pg_catalog.btrim(p_consent_source), '');
  if p_party_id is null
    or p_expected_version is null or p_expected_version < 1
    or pg_catalog.char_length(normalized_key) not between 8 and 200
    or normalized_channel_key
      !~ '^[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)*$'
    or p_allowed is null
    or p_do_not_contact is null
    or (p_do_not_contact and p_allowed)
    or p_consent_status not in ('unknown', 'granted', 'denied', 'withdrawn')
    or (p_consent_status = 'granted' and normalized_consent_source is null)
    or pg_catalog.char_length(normalized_consent_source) > 500
    or p_correlation_id is null
    or (p_request_id is not null and pg_catalog.char_length(p_request_id) > 200) then
    raise exception using
      errcode = '22023',
      message = 'invalid communication preference command';
  end if;

  request_fingerprint := app.vertical_slice_fingerprint(
    pg_catalog.jsonb_build_object(
      'partyId', p_party_id,
      'expectedVersion', p_expected_version,
      'channelKey', normalized_channel_key,
      'allowed', p_allowed,
      'doNotContact', p_do_not_contact,
      'consentStatus', p_consent_status,
      'consentSource', normalized_consent_source
    )
  );
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      p_workspace_id::text || E'\x1fm3_set_party_communication_preference\x1f'
        || actor_user_id::text || E'\x1f' || normalized_key,
      0
    )
  );
  select receipt.* into existing_receipt
  from public.party_command_receipts receipt
  where receipt.workspace_id = p_workspace_id
    and receipt.actor_user_id = app.current_user_id()
    and receipt.command_type = 'm3_set_party_communication_preference'
    and receipt.idempotency_key = normalized_key;
  if found then
    if existing_receipt.command_fingerprint <> request_fingerprint then
      raise exception using
        errcode = '23505',
        message = 'party idempotency key was used for different preference input';
    end if;
    return query select
      (existing_receipt.result ->> 'preference_id')::uuid,
      (existing_receipt.result ->> 'party_id')::uuid,
      (existing_receipt.result ->> 'aggregate_version')::bigint,
      (existing_receipt.result ->> 'audit_event_id')::uuid,
      (existing_receipt.result ->> 'outbox_event_id')::uuid,
      true;
    return;
  end if;

  select party.* into party_row
  from public.parties party
  where party.workspace_id = p_workspace_id and party.id = p_party_id
  for update;
  if not found or party_row.status <> 'active' then
    raise exception using errcode = '23514', message = 'active workspace party is required';
  end if;
  if party_row.version <> p_expected_version then
    raise exception using
      errcode = '40001',
      message = 'party version conflict',
      detail = pg_catalog.format(
        'expected version %s but found %s',
        p_expected_version,
        party_row.version
      );
  end if;

  select preference.* into current_preference
  from public.party_communication_preferences preference
  where preference.workspace_id = p_workspace_id
    and preference.party_id = p_party_id
    and preference.channel_key = normalized_channel_key
    and preference.status = 'active'
  for update;
  next_preference_version := coalesce(current_preference.version, 0) + 1;
  if current_preference.id is not null then
    update public.party_communication_preferences
    set status = 'replaced', replaced_at = pg_catalog.statement_timestamp()
    where workspace_id = p_workspace_id and id = current_preference.id;
  end if;

  new_preference_id := pg_catalog.gen_random_uuid();
  insert into public.party_communication_preferences (
    id, workspace_id, party_id, channel_key, version, allowed,
    do_not_contact, consent_status, consent_source,
    replaces_preference_id, created_by
  ) values (
    new_preference_id, p_workspace_id, p_party_id, normalized_channel_key,
    next_preference_version, p_allowed, p_do_not_contact, p_consent_status,
    normalized_consent_source, current_preference.id, actor_user_id
  );
  next_aggregate_version := party_row.version + 1;
  update public.parties set version = next_aggregate_version
  where workspace_id = p_workspace_id and id = p_party_id;

  new_audit_event_id := app.write_audit_event(
    p_workspace_id => p_workspace_id,
    p_action => 'party.communication_preference_set',
    p_entity_type => 'party',
    p_entity_id => p_party_id,
    p_actor_user_id => actor_user_id,
    p_actor_type => 'user',
    p_before_data => pg_catalog.jsonb_build_object(
      'version', party_row.version,
      'prior_preference_id', current_preference.id
    ),
    p_after_data => pg_catalog.jsonb_build_object(
      'version', next_aggregate_version,
      'preference_id', new_preference_id,
      'channel_key', normalized_channel_key,
      'allowed', p_allowed,
      'do_not_contact', p_do_not_contact,
      'consent_status', p_consent_status,
      'preference_version', next_preference_version
    ),
    p_request_id => p_request_id,
    p_correlation_id => p_correlation_id,
    p_auth_assurance => coalesce(auth.jwt() ->> 'aal', 'unknown'),
    p_metadata => pg_catalog.jsonb_build_object('idempotency_key', normalized_key)
  );
  new_outbox_event_id := app.append_m3_crm_outbox_event(
    p_workspace_id,
    'party.communication_preference_set',
    p_party_id,
    next_aggregate_version,
    pg_catalog.jsonb_build_object(
      'partyId', p_party_id,
      'preferenceId', new_preference_id,
      'channelKey', normalized_channel_key,
      'allowed', p_allowed,
      'doNotContact', p_do_not_contact,
      'consentStatus', p_consent_status,
      'preferenceVersion', next_preference_version,
      'aggregateVersion', next_aggregate_version
    ),
    actor_user_id,
    p_correlation_id
  );
  result_payload := pg_catalog.jsonb_build_object(
    'preference_id', new_preference_id,
    'party_id', p_party_id,
    'aggregate_version', next_aggregate_version,
    'audit_event_id', new_audit_event_id,
    'outbox_event_id', new_outbox_event_id
  );
  insert into public.party_command_receipts (
    workspace_id, actor_user_id, command_type, idempotency_key,
    command_fingerprint, party_id, result, audit_event_id, outbox_event_id
  ) values (
    p_workspace_id, actor_user_id, 'm3_set_party_communication_preference',
    normalized_key, request_fingerprint, p_party_id, result_payload,
    new_audit_event_id, new_outbox_event_id
  );
  return query select
    new_preference_id,
    p_party_id,
    next_aggregate_version,
    new_audit_event_id,
    new_outbox_event_id,
    false;
end;
$$;

create function app.m3_update_party(
  p_workspace_id uuid,
  p_idempotency_key text,
  p_party_id uuid,
  p_expected_version bigint,
  p_display_name text,
  p_preferred_locale text,
  p_given_name text,
  p_family_name text,
  p_preferred_name text,
  p_birth_date date,
  p_legal_name text,
  p_registration_name text,
  p_request_id text,
  p_correlation_id uuid
)
returns table (
  party_id uuid,
  aggregate_version bigint,
  audit_event_id uuid,
  outbox_event_id uuid,
  replayed boolean
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_user_id uuid;
  normalized_key text;
  normalized_display_name text;
  normalized_given_name text;
  normalized_family_name text;
  normalized_preferred_name text;
  normalized_legal_name text;
  normalized_registration_name text;
  request_fingerprint text;
  existing_receipt public.party_command_receipts%rowtype;
  party_row public.parties%rowtype;
  next_version bigint;
  next_profile_version bigint;
  new_audit_event_id uuid;
  new_outbox_event_id uuid;
  result_payload jsonb;
begin
  actor_user_id := app.require_m3_crm_permission(
    p_workspace_id,
    'crm.update',
    false
  );
  normalized_key := pg_catalog.btrim(p_idempotency_key);
  normalized_display_name := pg_catalog.regexp_replace(
    pg_catalog.btrim(coalesce(p_display_name, '')),
    '\s+',
    ' ',
    'g'
  );
  normalized_given_name := nullif(pg_catalog.btrim(p_given_name), '');
  normalized_family_name := nullif(pg_catalog.btrim(p_family_name), '');
  normalized_preferred_name := nullif(pg_catalog.btrim(p_preferred_name), '');
  normalized_legal_name := nullif(pg_catalog.btrim(p_legal_name), '');
  normalized_registration_name := nullif(
    pg_catalog.btrim(p_registration_name),
    ''
  );
  if p_party_id is null
    or p_expected_version is null or p_expected_version < 1
    or pg_catalog.char_length(normalized_key) not between 8 and 200
    or normalized_display_name = ''
    or pg_catalog.char_length(normalized_display_name) > 200
    or p_preferred_locale not in ('en', 'fr')
    or p_correlation_id is null
    or (p_request_id is not null and pg_catalog.char_length(p_request_id) > 200) then
    raise exception using errcode = '22023', message = 'invalid party update command';
  end if;

  request_fingerprint := app.vertical_slice_fingerprint(
    pg_catalog.jsonb_build_object(
      'partyId', p_party_id,
      'expectedVersion', p_expected_version,
      'displayName', normalized_display_name,
      'preferredLocale', p_preferred_locale,
      'givenName', normalized_given_name,
      'familyName', normalized_family_name,
      'preferredName', normalized_preferred_name,
      'birthDate', p_birth_date,
      'legalName', normalized_legal_name,
      'registrationName', normalized_registration_name
    )
  );
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      p_workspace_id::text || E'\x1fm3_update_party\x1f'
        || actor_user_id::text || E'\x1f' || normalized_key,
      0
    )
  );
  select receipt.* into existing_receipt
  from public.party_command_receipts receipt
  where receipt.workspace_id = p_workspace_id
    and receipt.actor_user_id = app.current_user_id()
    and receipt.command_type = 'm3_update_party'
    and receipt.idempotency_key = normalized_key;
  if found then
    if existing_receipt.command_fingerprint <> request_fingerprint then
      raise exception using
        errcode = '23505',
        message = 'party idempotency key was used for different update input';
    end if;
    return query select
      (existing_receipt.result ->> 'party_id')::uuid,
      (existing_receipt.result ->> 'aggregate_version')::bigint,
      (existing_receipt.result ->> 'audit_event_id')::uuid,
      (existing_receipt.result ->> 'outbox_event_id')::uuid,
      true;
    return;
  end if;

  select party.* into party_row
  from public.parties party
  where party.workspace_id = p_workspace_id and party.id = p_party_id
  for update;
  if not found or party_row.status <> 'active' then
    raise exception using errcode = '23514', message = 'active workspace party is required';
  end if;
  if party_row.version <> p_expected_version then
    raise exception using
      errcode = '40001',
      message = 'party version conflict',
      detail = pg_catalog.format(
        'expected version %s but found %s',
        p_expected_version,
        party_row.version
      );
  end if;

  if party_row.party_type = 'person' then
    if normalized_given_name is null
      or pg_catalog.char_length(normalized_given_name) > 100
      or normalized_family_name is null
      or pg_catalog.char_length(normalized_family_name) > 100
      or pg_catalog.char_length(normalized_preferred_name) > 100
      or normalized_legal_name is not null
      or normalized_registration_name is not null then
      raise exception using errcode = '22023', message = 'invalid person profile update';
    end if;
    update public.party_person_profiles profile
    set given_name = normalized_given_name,
        family_name = normalized_family_name,
        preferred_name = normalized_preferred_name,
        birth_date = p_birth_date,
        preferred_locale = p_preferred_locale,
        version = profile.version + 1
    where profile.workspace_id = p_workspace_id
      and profile.party_id = p_party_id
    returning profile.version into next_profile_version;
  else
    if normalized_legal_name is null
      or pg_catalog.char_length(normalized_legal_name) > 200
      or pg_catalog.char_length(normalized_registration_name) > 200
      or normalized_given_name is not null
      or normalized_family_name is not null
      or normalized_preferred_name is not null
      or p_birth_date is not null then
      raise exception using errcode = '22023', message = 'invalid organization profile update';
    end if;
    update public.party_organization_profiles profile
    set legal_name = normalized_legal_name,
        registration_name = normalized_registration_name,
        preferred_locale = p_preferred_locale,
        version = profile.version + 1
    where profile.workspace_id = p_workspace_id
      and profile.party_id = p_party_id
    returning profile.version into next_profile_version;
  end if;
  if next_profile_version is null then
    raise exception using errcode = '23514', message = 'party profile is missing';
  end if;

  next_version := party_row.version + 1;
  update public.parties party
  set display_name = normalized_display_name, version = next_version
  where party.workspace_id = p_workspace_id and party.id = p_party_id;

  new_audit_event_id := app.write_audit_event(
    p_workspace_id => p_workspace_id,
    p_action => 'party.updated',
    p_entity_type => 'party',
    p_entity_id => p_party_id,
    p_actor_user_id => actor_user_id,
    p_actor_type => 'user',
    p_before_data => pg_catalog.jsonb_build_object(
      'display_name', party_row.display_name,
      'version', party_row.version
    ),
    p_after_data => pg_catalog.jsonb_build_object(
      'display_name', normalized_display_name,
      'preferred_locale', p_preferred_locale,
      'version', next_version,
      'profile_version', next_profile_version
    ),
    p_request_id => p_request_id,
    p_correlation_id => p_correlation_id,
    p_auth_assurance => coalesce(auth.jwt() ->> 'aal', 'unknown'),
    p_metadata => pg_catalog.jsonb_build_object('idempotency_key', normalized_key)
  );
  new_outbox_event_id := app.append_m3_crm_outbox_event(
    p_workspace_id,
    'party.updated',
    p_party_id,
    next_version,
    pg_catalog.jsonb_build_object(
      'partyId', p_party_id,
      'partyType', party_row.party_type,
      'profileVersion', next_profile_version,
      'aggregateVersion', next_version
    ),
    actor_user_id,
    p_correlation_id
  );
  result_payload := pg_catalog.jsonb_build_object(
    'party_id', p_party_id,
    'aggregate_version', next_version,
    'audit_event_id', new_audit_event_id,
    'outbox_event_id', new_outbox_event_id
  );
  insert into public.party_command_receipts (
    workspace_id, actor_user_id, command_type, idempotency_key,
    command_fingerprint, party_id, result, audit_event_id, outbox_event_id
  ) values (
    p_workspace_id, actor_user_id, 'm3_update_party', normalized_key,
    request_fingerprint, p_party_id, result_payload,
    new_audit_event_id, new_outbox_event_id
  );
  return query select
    p_party_id,
    next_version,
    new_audit_event_id,
    new_outbox_event_id,
    false;
end;
$$;

create function app.m3_archive_party(
  p_workspace_id uuid,
  p_idempotency_key text,
  p_party_id uuid,
  p_expected_version bigint,
  p_reason text,
  p_request_id text,
  p_correlation_id uuid
)
returns table (
  party_id uuid,
  aggregate_version bigint,
  audit_event_id uuid,
  outbox_event_id uuid,
  replayed boolean
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_user_id uuid;
  normalized_key text;
  normalized_reason text;
  request_fingerprint text;
  existing_receipt public.party_command_receipts%rowtype;
  party_row public.parties%rowtype;
  next_version bigint;
  new_audit_event_id uuid;
  new_outbox_event_id uuid;
  result_payload jsonb;
begin
  actor_user_id := app.require_m3_crm_permission(
    p_workspace_id,
    'crm.update',
    false
  );
  normalized_key := pg_catalog.btrim(p_idempotency_key);
  normalized_reason := pg_catalog.btrim(p_reason);
  if p_party_id is null
    or p_expected_version is null or p_expected_version < 1
    or pg_catalog.char_length(normalized_key) not between 8 and 200
    or pg_catalog.char_length(normalized_reason) not between 1 and 2000
    or p_correlation_id is null
    or (p_request_id is not null and pg_catalog.char_length(p_request_id) > 200) then
    raise exception using errcode = '22023', message = 'invalid party archive command';
  end if;

  request_fingerprint := app.vertical_slice_fingerprint(
    pg_catalog.jsonb_build_object(
      'partyId', p_party_id,
      'expectedVersion', p_expected_version,
      'reason', normalized_reason
    )
  );
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      p_workspace_id::text || E'\x1fm3_archive_party\x1f'
        || actor_user_id::text || E'\x1f' || normalized_key,
      0
    )
  );
  select receipt.* into existing_receipt
  from public.party_command_receipts receipt
  where receipt.workspace_id = p_workspace_id
    and receipt.actor_user_id = app.current_user_id()
    and receipt.command_type = 'm3_archive_party'
    and receipt.idempotency_key = normalized_key;
  if found then
    if existing_receipt.command_fingerprint <> request_fingerprint then
      raise exception using
        errcode = '23505',
        message = 'party idempotency key was used for different archive input';
    end if;
    return query select
      (existing_receipt.result ->> 'party_id')::uuid,
      (existing_receipt.result ->> 'aggregate_version')::bigint,
      (existing_receipt.result ->> 'audit_event_id')::uuid,
      (existing_receipt.result ->> 'outbox_event_id')::uuid,
      true;
    return;
  end if;

  select party.* into party_row
  from public.parties party
  where party.workspace_id = p_workspace_id and party.id = p_party_id
  for update;
  if not found or party_row.status <> 'active' then
    raise exception using errcode = '23514', message = 'active workspace party is required';
  end if;
  if party_row.version <> p_expected_version then
    raise exception using
      errcode = '40001',
      message = 'party version conflict',
      detail = pg_catalog.format(
        'expected version %s but found %s',
        p_expected_version,
        party_row.version
      );
  end if;
  if exists (
    select 1
    from public.legal_entities entity
    where entity.workspace_id = p_workspace_id
      and entity.organization_party_id = p_party_id
      and entity.status = 'active'
  ) then
    raise exception using
      errcode = '23514',
      message = 'party is the active organization for a legal entity';
  end if;

  next_version := party_row.version + 1;
  update public.parties set status = 'archived', version = next_version
  where workspace_id = p_workspace_id and id = p_party_id;
  new_audit_event_id := app.write_audit_event(
    p_workspace_id => p_workspace_id,
    p_action => 'party.archived',
    p_entity_type => 'party',
    p_entity_id => p_party_id,
    p_actor_user_id => actor_user_id,
    p_actor_type => 'user',
    p_before_data => pg_catalog.jsonb_build_object(
      'status', party_row.status,
      'version', party_row.version
    ),
    p_after_data => pg_catalog.jsonb_build_object(
      'status', 'archived',
      'version', next_version
    ),
    p_request_id => p_request_id,
    p_correlation_id => p_correlation_id,
    p_auth_assurance => coalesce(auth.jwt() ->> 'aal', 'unknown'),
    p_metadata => pg_catalog.jsonb_build_object(
      'idempotency_key', normalized_key,
      'reason', normalized_reason
    )
  );
  new_outbox_event_id := app.append_m3_crm_outbox_event(
    p_workspace_id,
    'party.archived',
    p_party_id,
    next_version,
    pg_catalog.jsonb_build_object(
      'partyId', p_party_id,
      'aggregateVersion', next_version
    ),
    actor_user_id,
    p_correlation_id
  );
  result_payload := pg_catalog.jsonb_build_object(
    'party_id', p_party_id,
    'aggregate_version', next_version,
    'audit_event_id', new_audit_event_id,
    'outbox_event_id', new_outbox_event_id
  );
  insert into public.party_command_receipts (
    workspace_id, actor_user_id, command_type, idempotency_key,
    command_fingerprint, party_id, result, audit_event_id, outbox_event_id
  ) values (
    p_workspace_id, actor_user_id, 'm3_archive_party', normalized_key,
    request_fingerprint, p_party_id, result_payload,
    new_audit_event_id, new_outbox_event_id
  );
  return query select
    p_party_id,
    next_version,
    new_audit_event_id,
    new_outbox_event_id,
    false;
end;
$$;

create or replace function app.create_party(
  p_workspace_id uuid,
  p_idempotency_key text,
  p_party_type text,
  p_display_name text,
  p_request_id text,
  p_correlation_id uuid
)
returns table (party_id uuid, replayed boolean)
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_user_id uuid;
  normalized_idempotency_key text;
  normalized_display_name text;
  compatibility_given_name text;
  compatibility_family_name text;
  compatibility_preferred_locale text;
  request_fingerprint text;
  existing_party_id uuid;
  existing_fingerprint text;
  new_party_id uuid;
  new_audit_event_id uuid;
begin
  actor_user_id := app.require_m3_crm_permission(
    p_workspace_id,
    'crm.create',
    false
  );
  normalized_idempotency_key := pg_catalog.btrim(coalesce(p_idempotency_key, ''));
  normalized_display_name := pg_catalog.regexp_replace(
    pg_catalog.btrim(coalesce(p_display_name, '')),
    '\s+',
    ' ',
    'g'
  );
  if pg_catalog.char_length(normalized_idempotency_key) not between 8 and 200 then
    raise exception using errcode = '22023', message = 'invalid party idempotency key';
  end if;
  if p_party_type not in ('person', 'organization') then
    raise exception using errcode = '22023', message = 'invalid party type';
  end if;
  if normalized_display_name = ''
    or pg_catalog.char_length(normalized_display_name) > 200 then
    raise exception using errcode = '22023', message = 'invalid party display name';
  end if;
  if p_correlation_id is null then
    raise exception using errcode = '23502', message = 'correlation ID is required';
  end if;

  select case when workspace.default_locale like 'fr%' then 'fr' else 'en' end
    into strict compatibility_preferred_locale
  from public.workspaces workspace
  where workspace.id = p_workspace_id;
  if p_party_type = 'person' then
    compatibility_given_name := pg_catalog.left(
      pg_catalog.split_part(normalized_display_name, ' ', 1),
      100
    );
    compatibility_family_name := coalesce(
      nullif(
        pg_catalog.left(
          pg_catalog.btrim(
            pg_catalog.regexp_replace(
              normalized_display_name,
              '^[^ ]+[ ]*',
              ''
            )
          ),
          100
        ),
        ''
      ),
      compatibility_given_name
    );
  end if;

  request_fingerprint := app.vertical_slice_fingerprint(
    pg_catalog.jsonb_build_object(
      'party_type', p_party_type,
      'display_name', normalized_display_name
    )
  );
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      p_workspace_id::text || E'\x1fcreate_party\x1f'
        || actor_user_id::text || E'\x1f' || normalized_idempotency_key,
      0
    )
  );
  select party.id, party.command_fingerprint
    into existing_party_id, existing_fingerprint
  from public.parties party
  where party.workspace_id = p_workspace_id
    and party.idempotency_actor_user_id = actor_user_id
    and party.idempotency_key = normalized_idempotency_key;
  if found then
    if existing_fingerprint <> request_fingerprint then
      raise exception using
        errcode = '23505',
        message = 'party idempotency key was used for a different request';
    end if;
    return query select existing_party_id, true;
    return;
  end if;

  new_party_id := pg_catalog.gen_random_uuid();
  insert into public.parties (
    id, workspace_id, party_type, display_name, idempotency_key,
    idempotency_actor_user_id, command_fingerprint, created_by
  ) values (
    new_party_id, p_workspace_id, p_party_type, normalized_display_name,
    normalized_idempotency_key, actor_user_id, request_fingerprint,
    actor_user_id
  );
  if p_party_type = 'person' then
    insert into public.party_person_profiles (
      party_id, workspace_id, given_name, family_name, preferred_name,
      birth_date, preferred_locale, version
    ) values (
      new_party_id, p_workspace_id, compatibility_given_name,
      compatibility_family_name, null, null,
      compatibility_preferred_locale, 1
    );
  else
    insert into public.party_organization_profiles (
      party_id, workspace_id, legal_name, registration_name,
      preferred_locale, version
    ) values (
      new_party_id, p_workspace_id, normalized_display_name, null,
      compatibility_preferred_locale, 1
    );
  end if;
  new_audit_event_id := app.write_audit_event(
    p_workspace_id => p_workspace_id,
    p_action => 'party.created',
    p_entity_type => 'party',
    p_entity_id => new_party_id,
    p_actor_user_id => actor_user_id,
    p_actor_type => 'user',
    p_after_data => pg_catalog.jsonb_build_object(
      'party_type', p_party_type,
      'display_name', normalized_display_name,
      'status', 'active',
      'version', 1
    ),
    p_request_id => p_request_id,
    p_correlation_id => p_correlation_id,
    p_auth_assurance => coalesce(auth.jwt() ->> 'aal', 'unknown'),
    p_metadata => pg_catalog.jsonb_build_object(
      'idempotency_key', normalized_idempotency_key,
      'api', 'legacy'
    )
  );
  perform app.append_m3_crm_outbox_event(
    p_workspace_id,
    'party.created',
    new_party_id,
    1,
    pg_catalog.jsonb_build_object(
      'partyId', new_party_id,
      'partyType', p_party_type,
      'aggregateVersion', 1,
      'api', 'legacy'
    ),
    actor_user_id,
    p_correlation_id
  );
  return query select new_party_id, false;
end;
$$;

revoke all on function app.set_party_idempotency_actor()
  from public, anon, authenticated, service_role;
revoke all on function app.require_m3_crm_permission(uuid, text, boolean)
  from public, anon, authenticated, service_role;
revoke all on function app.can_read_m3_crm(uuid, text)
  from public, anon, authenticated, service_role;
revoke all on function app.m3_crm_identifier_runtime_key()
  from public, anon, authenticated, service_role;
revoke all on function app.m3_crm_identifier_fingerprint(text)
  from public, anon, authenticated, service_role;
revoke all on function app.m3_crm_encrypt_identifier(text)
  from public, anon, authenticated, service_role;
revoke all on function app.m3_crm_decrypt_identifier(bytea)
  from public, anon, authenticated, service_role;
revoke all on function app.append_m3_crm_outbox_event(
  uuid, text, uuid, bigint, jsonb, uuid, uuid
) from public, anon, authenticated, service_role;
revoke all on function app.assert_party_profile_type()
  from public, anon, authenticated, service_role;
revoke all on function app.guard_party_version_history()
  from public, anon, authenticated, service_role;
revoke all on function app.prevent_party_command_receipt_mutation()
  from public, anon, authenticated, service_role;
revoke all on function app.guard_legal_entity_lifecycle()
  from public, anon, authenticated, service_role;
revoke all on function app.assert_legal_entity_organization_party()
  from public, anon, authenticated, service_role;

revoke all on function app.m3_list_parties(uuid)
  from public, anon, authenticated, service_role;
revoke all on function app.m3_get_party(uuid, uuid)
  from public, anon, authenticated, service_role;
revoke all on function app.m3_create_party(
  uuid, text, text, text, text, text, text, text, date, text, text, text, uuid
) from public, anon, authenticated, service_role;
revoke all on function app.m3_add_party_contact(
  uuid, text, uuid, text, text, boolean, boolean, text, text, boolean, text, uuid
) from public, anon, authenticated, service_role;
revoke all on function app.m3_add_party_address(
  uuid, text, uuid, text, text, text, text, text, text, text, boolean, text, uuid
) from public, anon, authenticated, service_role;
revoke all on function app.m3_replace_party_identifier(
  uuid, text, uuid, text, text, text, date, date, text, text, uuid
) from public, anon, authenticated, service_role;
revoke all on function app.m3_reveal_party_identifier(
  uuid, uuid, text, text, uuid
) from public, anon, authenticated, service_role;
revoke all on function app.m3_add_party_relationship(
  uuid, text, uuid, uuid, text, date, date, text, uuid
) from public, anon, authenticated, service_role;
revoke all on function app.m3_set_party_communication_preference(
  uuid, text, uuid, bigint, text, boolean, boolean, text, text, text, uuid
) from public, anon, authenticated, service_role;
revoke all on function app.m3_update_party(
  uuid, text, uuid, bigint, text, text, text, text, text, date,
  text, text, text, uuid
) from public, anon, authenticated, service_role;
revoke all on function app.m3_archive_party(
  uuid, text, uuid, bigint, text, text, uuid
) from public, anon, authenticated, service_role;
revoke all on function app.create_party(uuid, text, text, text, text, uuid)
  from public, anon, authenticated, service_role;

grant execute on function app.can_read_m3_crm(uuid, text) to authenticated;
grant execute on function app.m3_list_parties(uuid) to authenticated;
grant execute on function app.m3_get_party(uuid, uuid) to authenticated;
grant execute on function app.m3_create_party(
  uuid, text, text, text, text, text, text, text, date, text, text, text, uuid
) to authenticated;
grant execute on function app.m3_add_party_contact(
  uuid, text, uuid, text, text, boolean, boolean, text, text, boolean, text, uuid
) to authenticated;
grant execute on function app.m3_add_party_address(
  uuid, text, uuid, text, text, text, text, text, text, text, boolean, text, uuid
) to authenticated;
grant execute on function app.m3_replace_party_identifier(
  uuid, text, uuid, text, text, text, date, date, text, text, uuid
) to authenticated;
grant execute on function app.m3_reveal_party_identifier(
  uuid, uuid, text, text, uuid
) to authenticated;
grant execute on function app.m3_add_party_relationship(
  uuid, text, uuid, uuid, text, date, date, text, uuid
) to authenticated;
grant execute on function app.m3_set_party_communication_preference(
  uuid, text, uuid, bigint, text, boolean, boolean, text, text, text, uuid
) to authenticated;
grant execute on function app.m3_update_party(
  uuid, text, uuid, bigint, text, text, text, text, text, date,
  text, text, text, uuid
) to authenticated;
grant execute on function app.m3_archive_party(
  uuid, text, uuid, bigint, text, text, uuid
) to authenticated;
grant execute on function app.create_party(uuid, text, text, text, text, uuid)
  to authenticated;

comment on table public.legal_entities is
  'Tenant-neutral workspace legal parties for deal ownership and document headers; no tax or identifier policy.';
comment on table public.party_identifiers is
  'Restricted encrypted party identifiers. Ordinary CRM projections expose only masked suffixes.';
comment on table public.party_command_receipts is
  'Append-only, actor-scoped idempotency receipts for M3 party commands.';
comment on function app.m3_reveal_party_identifier(uuid, uuid, text, text, uuid) is
  'Explicit recent-AAL2 restricted reveal that records an audit event and never emits an outbox payload containing plaintext.';
