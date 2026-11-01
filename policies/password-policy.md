# Password policy — the GPO analog (reference documentation)

> Reference documentation — authorized lab use only.

The video's security-policy chapter distinguishes local policy, GPO delivered
via SYSVOL, application control (AppLocker/WDAC), and MDM. This range is
Linux, so the **Default Domain Password Policy** — the one GPO everyone
actually configures — is represented by Samba's domain password settings on
`dc01`, applied at provision time (see `dc01/entrypoint.sh`).

## The policy (as applied by dc01 on first boot)

```bash
# Complexity requirements ON (upper, lower, digit, special - the classic four)
docker exec dc01 samba-tool domain passwordsettings set --complexity=on

# Minimum password length
docker exec dc01 samba-tool domain passwordsettings set --min-pwd-length=12

# Password history (no reusing the last N passwords)
docker exec dc01 samba-tool domain passwordsettings set --history-length=5

# Inspect the resulting policy
docker exec dc01 samba-tool domain passwordsettings show
```

These are exactly the commands `dc01/entrypoint.sh` runs after provisioning;
the policy lives in the domain database (the GPO-analog store), not in any
one host's config — change it once, every domain member enforces it.

## Ordering note (deliberate, and a finding)

Users are seeded **before** the policy is hardened: `jsmith / Summer2026!`
(10 chars) and `mchen / Welcome123!` (11 chars) both violate the 12-character
minimum, but policy is enforced at *change* time, so the seeded users keep
their weak legacy passwords. That is realistic and intentional — "accounts
grandfathered in before the password policy" is one of the most common real
findings. Try to change `mchen`'s password to something short and watch the
policy reject it:

```bash
docker exec -it dc01 samba-tool user setpassword mchen --newpassword='short'
#   expected: password does not meet complexity/length requirements
```

## Mapping the video's other policy types

| Video concept | Representation in this range |
|---|---|
| Local policy (per-machine settings) | PAM/sssd configuration baked into the `ws` image; per-container environment blocks (`WEAK_AUTH`) |
| GPO via SYSVOL (domain-wide, central) | `samba-tool domain passwordsettings` above + the provisioned `sysvol` tree (`dc01/share-setup.md`) |
| AppLocker / WDAC (application allowlisting) | The container images themselves: a service can only run the binaries baked into its image — allowlisting by construction. The web shell in phase 2 is the documented exception that shows why allowlisting matters |
| MDM (device configuration management) | `docker-compose.yml` environment blocks: declarative per-"device" configuration applied at deploy time, re-applied on every recreate |

## What the blue team checks (policy-as-detection)

- `samba-tool domain passwordsettings show` — is the baseline actually set?
- `docker exec dc01 samba-tool user list` — who exists in the domain?
- `docker exec filesrv pdbedit -L` — does the file server's local account
  mirror match the domain inventory? (Phase 7 plants a `backdoor` account —
  inventory review is what catches it.)
- Password age/rotation: the seeded "legacy" credentials are the exercise —
  finding which accounts predate the policy.
