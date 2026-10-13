-- =============================================================================
-- Antigravity Remote Relay Schema for Supabase (Option A: Zero-Infra Managed)
-- Enables Realtime messaging, Device Secret Auth, and Row-Level Security (RLS)
-- =============================================================================

-- 1. Devices Table
create table if not exists public.devices (
    device_id text primary key,
    role text not null check (role in ('host', 'client')),
    device_name text not null,
    public_key text not null, -- Curve25519 (X25519) Public Key (Base64)
    last_seen_at timestamptz default now(),
    is_online boolean default false,
    created_at timestamptz default now()
);

-- Enable RLS
alter table public.devices enable row level security;

create policy "Devices can view registered devices"
    on public.devices for select
    using (true);

create policy "Devices can update own presence"
    on public.devices for update
    using (device_id = current_setting('request.headers', true)::json->>'x-device-id');

-- 2. Pairings Table (Device authorization registry)
create table if not exists public.device_pairings (
    id uuid default gen_random_uuid() primary key,
    host_device_id text references public.devices(device_id) on delete cascade,
    client_device_id text references public.devices(device_id) on delete cascade,
    pair_token text not null,
    status text not null default 'pending' check (status in ('pending', 'authorized', 'revoked')),
    created_at timestamptz default now(),
    unique(host_device_id, client_device_id)
);

alter table public.device_pairings enable row level security;

create policy "Pairings viewable by participant devices"
    on public.device_pairings for select
    using (
        host_device_id = current_setting('request.headers', true)::json->>'x-device-id' or
        client_device_id = current_setting('request.headers', true)::json->>'x-device-id'
    );

-- 3. Encrypted Message Transport Buffer (Realtime Stream)
create table if not exists public.encrypted_messages (
    id uuid default gen_random_uuid() primary key,
    sender_id text not null references public.devices(device_id),
    target_id text not null references public.devices(device_id),
    message_type text not null,
    encrypted_payload jsonb not null, -- { senderKeyId, nonce, ciphertext, sequenceNumber }
    created_at timestamptz default now()
);

alter table public.encrypted_messages enable row level security;

-- Enforce strict RLS: Sender can insert, only Target can read
create policy "Senders can insert encrypted messages"
    on public.encrypted_messages for insert
    with check (
        sender_id = current_setting('request.headers', true)::json->>'x-device-id'
    );

create policy "Target can read encrypted messages"
    on public.encrypted_messages for select
    using (
        target_id = current_setting('request.headers', true)::json->>'x-device-id'
    );

-- Enable Supabase Realtime for instant push delivery
alter publication supabase_realtime add table public.encrypted_messages;
alter publication supabase_realtime add table public.devices;

-- Function to prune expired messages older than 24 hours
create or replace function prune_old_messages() returns void as $$
begin
    delete from public.encrypted_messages where created_at < now() - interval '24 hours';
end;
$$ language plpgsql;
