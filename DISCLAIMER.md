# DISCLAIMER — authorized lab use only

`enterprise-cyber-range` is an educational cyber range. It exists to make the
concepts from the explainer video ("Red Team vs Blue Team — Cybersecurity
Terms & Concepts Explained") runnable and observable: segmentation, the kill
chain, firewall policy, Active Directory, SIEM detections, IOC vs IoA.

Everything inside is simulated:

- Isolated networks only. The compose project defines four private Docker
  bridge networks. No service publishes a port on the host, and the default
  firewall ruleset blocks internal hosts from reaching anything outside the
  compose project.
- All data is fake. Board notes, financials, "passport scans", credentials,
  user accounts, and the ISP page are invented and clearly marked SIMULATED.
  There is no real personal information anywhere in this repository.
- The vulnerabilities are staged. The auth bypass and the `/console` dev
  shell are simulated teaching devices mounted only when `WEAK_AUTH=1`.

## The video's three ground rules

- **Isolated lab** — every host runs inside the compose project's private
  networks; nothing here is reachable from, or reaches, a real network.
- **Authorization** — you only ever attack machines you own: the containers
  you built from this repository, on your own machine.
- **Defensive goal** — every attacker action has a matching defender view;
  the point of each phase is to learn the detection, not just the technique.

If you are not operating inside this repository's compose project, stop.
This range is a training aid, not a toolkit, and it is licensed for lab use.
