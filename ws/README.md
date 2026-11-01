# ws — domain workstations (reference configuration)

> Reference configuration — authorized lab use only.

One image, two instances (`ws1` at `10.10.20.5`, `ws2` at `10.10.20.6`). They
are the video's "client OS" half of the client-vs-server chapter: real
Debian hosts joined as **domain members** of `LAB.LOCAL` against `dc01`
(`10.10.30.10`), with sssd/realmd/krb5 doing exactly what a Windows box does
under the hood — DNS discovery of the DC, Kerberos machine authentication,
and identity lookup through NSS.

## First boot

The entrypoint:

1. pins its default route through `fw` (`10.10.20.1`),
2. points `/etc/resolv.conf` at the domain controller (`10.10.30.10`) —
   Docker's embedded DNS does not know AD SRV records,
3. starts `dbus-daemon` (there is no systemd in the container; `realm`
   speaks to realmd over the system bus),
4. waits for `dc01:88` (Kerberos) to answer,
5. runs `realm join LAB.LOCAL -U administrator` with the password piped from
   `DC_ADMIN_PASS`, retrying up to 5 times,
6. adjusts `/etc/sssd/sssd.conf` (short names, homedir template), restarts
   sssd, and drops the marker file `/var/lib/range/joined`.

## Fail-soft semantics

If the join fails after 5 retries (or dc01:88 never opens), the workstation
**keeps the container up** and touches `/var/lib/range/join-failed` instead of
exiting. The compose healthcheck is `test -f /var/lib/range/joined`, so:

- join OK        → container reports `healthy`
- join failed    → container reports `unhealthy` but stays running, so the
  rest of the range still comes up and the scenario still runs

This is deliberate: a broken workstation join must not take the whole range
down with it. Inspect and retry:

```bash
docker logs ws1            # shows the exact realm error per attempt
docker compose restart ws1 # re-runs the entrypoint (join is retried)
```

## Using the workstations

```bash
docker exec ws1 getent passwd jsmith       # domain identity via sssd
docker exec ws1 id mchen
docker exec ws1 kinit jsmith               # Kerberos auth (password: Summer2026!)
docker exec ws1 smbclient -L //filesrv -k  # Kerberos-signed SMB listing
```

The workstations sit behind the firewall's workstation rule (FW-12..FW-16):
SMB to filesrv, AD service ports to dc01, HTTPS to the DMZ portal, nothing
else — the video's "workstation may speak file sharing to this one server".
