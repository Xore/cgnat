# cowrie-gpu — high-fidelity GPU server honeypot persona

> Compatibility deployment only. The canonical, actively deployed source is
> [`Xore/honeypot-stack/cowrie`](https://github.com/Xore/honeypot-stack/tree/main/cowrie);
> this Compose file builds that public Git context directly.
> Do not run this wrapper beside the integrated stack because both publish
> ports 22 and 23.

Mimics a **Dell PowerEdge R7525** joined to a fictional corporate AD domain
`nexusai.local`, running dual AMD EPYC 7742 (128 cores), 512 GB ECC RAM,
and two NVIDIA A100 SXM4 80GB GPUs on Ubuntu 22.04.4 LTS.

## Deception layers

**Layer 1 — Hardware identity** (`fakefs/`)

Bind-mounted over the container's real `/proc` and `/sys/class/dmi/id/`. Covers
`/proc/cpuinfo` (128 EPYC cores), `/proc/meminfo` (512 GB), `/proc/version`
(Ubuntu 22.04 kernel string), DMI product/vendor/board, and `/proc/net/tcp`
(pre-populated with the fake connection state table).

**Layer 2 — Command output** (`txtcmds/`)

Static files served verbatim by Cowrie's txtcmds engine:

| Command | Fakes |
|---|---|
| `ps aux` / `ps -ef` | GPU inference workers, training job, smbd, sssd, winbindd, Jenkins |
| `top` | Live-looking load average matching GPU workload |
| `netstat` / `ss` | ESTABLISHED connections to `ad.nexusai.local:ldap/kerberos/445`, `fs01`, `fs02` |
| `mount` | CIFS mounts: netlogon, sysvol, data, models, backup |
| `nvidia-smi` | Dual A100 SXM4 80GB with active compute processes |
| `nvcc` | CUDA 12.2 compiler version |
| `lscpu` / `free` / `df` / `lspci` | Full hardware profile |
| `smbstatus` | Active SMB3.1.1 sessions to AD |
| `wbinfo -u` | Domain user list (NEXUSAI domain) |
| `id` | root with domain users group membership |
| `who` / `w` / `last` | Plausible login history |
| `nmap` | AD port scan output for `ad.nexusai.local` |
| `dd` | Realistic throughput timing |

**Layer 3 — Filesystem identity** (`honeyfs/`)

`/etc/hosts`, `/etc/hostname`, `/etc/resolv.conf`, `/etc/krb5.conf`,
`/etc/sssd/sssd.conf`, `/etc/samba/smb.conf` — all internally consistent
with the `nexusai.local` domain and `10.10.1.x` AD subnet.

## Fake corporate topology

```
nexusai.local (NEXUSAI)
├── ad.nexusai.local    10.10.1.10  (Windows Server 2022 DC)
├── fs01.nexusai.local  10.10.1.20  (file server — /data, /models)
├── fs02.nexusai.local  10.10.1.21  (file server — /backup)
├── gpu01.nexusai.local 10.10.10.42 (this node — honeypot)
├── prometheus          10.10.0.5
└── gw                  10.10.0.1
```

## Deploy

```bash
cd cgnat/examples/cowrie-gpu
docker compose up -d --build
```

## Persona hardening

The canonical image includes realistic `dmesg`, CPU frequency sysfs entries,
Kerberos `klist`, domain-aware authentication logs, dynamic command output, and
payload capture. Make persona changes only in the `honeypot-stack` repository.
