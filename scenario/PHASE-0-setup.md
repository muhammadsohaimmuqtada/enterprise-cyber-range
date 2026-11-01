# Phase 0 — Range setup and ground rules

> Reference scenario — authorized lab use only. See [`../DISCLAIMER.md`](../DISCLAIMER.md).

## Video concept

Ground rules (isolated lab, authorization, defensive goal) and the red/blue/
purple framing that the whole scenario series runs on.

## Objective

Bring the enterprise cyber range up, confirm every segment is healthy, enable
the simulated weaknesses used by the phases, and agree on how to reset
between runs.

## Setup steps

```bash
# 1) Configure the environment (dc01 admin password; WEAK_AUTH for the phases)
cp .env.example .env
sed -i 's/^WEAK_AUTH=.*/WEAK_AUTH=1/' .env   # phases 2-7 need the simulated bypass

# 2) Start the range (first run builds images; the Kali/ Metasploit build is
#    the slow one - expect a long first build)
docker compose up -d            # or: make up

# 3) Wait for healthchecks: watch the STATUS column until every service that
#    should be is (healthy). dc01 provisions the domain on first boot; ws1/ws2
#    join it afterwards - give the whole stack a few minutes.
watch docker compose ps

# 4) Confirm the firewall policy is loaded and see the per-rule counters
make status

# 5) Quick liveness checks from the blue team's seat
docker exec web01 curl -s http://localhost/health
docker exec dc01 smbclient -L //localhost -U 'administrator%Lab-Admin#2026!'
docker exec filesrv smbclient -L //localhost -U 'fileshare%F1leShare!2026!'
docker exec ws1 getent passwd jsmith          # domain join worked (may take a minute)
```

WEAK_AUTH notes: the value is read at container create time. After editing
`.env`, recreate only the web tier:

```bash
docker compose up -d web01     # recreates web01 with the new WEAK_AUTH value
```

`WEAK_AUTH=0` hardens the portal: the login bypass is rejected and
`/console?token=DEV-2026` returns 404. Phases 1 and the blue-team walkthroughs
still work; phases 2-7 require `WEAK_AUTH=1`.

## Reset and snapshots

```bash
make reset    # docker compose down -v, wipe state volumes, start fresh
              # (dc01 re-provisions, workstations re-join, files regenerate)
make down     # stop, keep volumes
make up       # resume
make clean    # stop and remove containers, volumes, and locally built images
```

State that survives a plain restart: the domain database (`dc01_state`), the
dc01 Samba config (`dc01_etc`), the filesrv account database
(`filesrv_state`). `make reset` is the "snapshot restore" of this range:
there is nothing else to snapshot.

## Ground rules (from the video)

- **Isolated lab** — every host runs inside the compose project's private
  bridge networks; nothing here touches a real network.
- **Authorization** — you only attack machines you own, built from this
  repository, on your own machine or Codespace.
- **Defensive goal** — every attacker action has a matching defender view;
  each phase ends with "what the blue team sees".

## Purple-team tip

Run every phase twice: once driving the attacker commands, once with the
attacker window closed and the blue-team commands open, replaying the log
lines the first run produced. The second pass is where the detection
knowledge actually sticks — ideally with a second person playing defender who
does not read the attacker steps.
