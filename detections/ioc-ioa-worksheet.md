# IOC vs IoA worksheet

> Exercise worksheet — complete it while walking scenario phases 1-7.

The video's distinction, in one line: an **IOC** (indicator of compromise)
is a discrete artifact you can point at — a file hash, an IP, a URL, a
username. An **IoA** (indicator of attack) is a *behavior* — a sequence,
a timing, a pattern that matters even when every single event looks innocent.

Fill one row per phase as you run it. Row 1 is worked as the example.

| Phase | Concrete IOC you observed (artifact + where you saw it) | Concrete IoA you observed (behavior + why it is suspicious) | Kill chain step |
|---|---|---|---|
| 1 — remote entry *(example)* | Scanning source IP `172.31.100.3` in `FW-EDGE-DENY` lines and nginx access log | Six ports swept from one external source within a minute — the pattern of a scan | 1 reconnaissance |
| 2 — initial foothold | | | 2 initial access |
| 3 — execution + discovery | | | 3 execution |
| 4 — lateral movement | | | 6 lateral movement |
| 5 — privilege + critical access | | | 5 privilege escalation |
| 6 — exfiltration | | | 7 exfiltration |
| 7 — persistence + covering tracks | | | 4 persistence (+ 8 impact) |

## Hints (only if stuck)

- Phase 2: look for a literal string in the web logs that should never be a
  password, and a token in a URL.
- Phase 3: what does a *web server* doing an internal port sweep tell you?
- Phase 4: which account authenticated to filesrv, from which host?
- Phase 5: which file, read by which account, from which source?
- Phase 6: what artifact proved the data left, and what did the *timing/
  sequence* of the blocked attempts add?
- Phase 7: enumerate what changed on the hosts (account, cron entry) and
  describe the beacon's rhythm.

## Debrief questions

1. Which rows had an IOC but no useful IoA? Which had an IoA but the IOC was
   only visible after the fact?
2. Which indicators survive `make reset`? (Answer: none in the range state —
   which is why exports/SIEM copies matter.)
3. Pick any row: if you could keep only the IOC column or only the IoA column
   for your SOC, which would you keep, and why does the video say both
   matter?
