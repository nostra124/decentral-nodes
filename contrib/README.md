# contrib

Helper scripts that live outside the main `bin/` + `libexec/` command
surface — platform glue that the portable bash nodes can't provide.

## `Install-ForgejoRunner.ps1`

A PowerShell installer for a **Forgejo Actions runner on Windows**.

`forgejo-node runner` (bash) can register a Windows runner and emit its
labels, but it can't install a *native* Windows service — there is no
systemd or launchd on Windows. This script closes that gap: it downloads
`forgejo-runner.exe`, registers it, and installs it as a service so it
survives reboots.

### Usage

From an **elevated** PowerShell prompt (Administrator):

```powershell
# Host-backend runner (jobs run on the Windows host)
.\Install-ForgejoRunner.ps1 -InstanceUrl https://git.example.org -Token XXXX -Platform windows

# Docker-backend runner (needs Docker Desktop)
.\Install-ForgejoRunner.ps1 -InstanceUrl https://git.example.org -Token XXXX -Platform docker
```

Get the `-Token` from the instance: **Site / Org / Repo → Settings →
Actions → Runners → Create new runner**.

### Platforms (labels)

The label presets match `forgejo-node runner platforms`:

| `-Platform` | Labels | Backend |
|---|---|---|
| `windows` (default) | `windows:host,windows-latest:host,self-hosted:host` | host (jobs run on the Windows host) |
| `docker` | `docker:docker://node:20-bookworm,…` | containers (needs Docker Desktop) |
| `host` | `host:host,self-hosted:host` | generic host |

Override with `-Labels "a:b://c,…"`. Override the docker base image with
the `FORGEJO_RUNNER_IMAGE` environment variable.

### Service

The script prefers [nssm](https://nssm.cc/) (forgejo-runner is a console
app, so it needs a service wrapper). If nssm isn't on `PATH`, it falls
back to a **Scheduled Task** that runs at startup as `SYSTEM`. Install
nssm and re-run for a first-class Windows service.

### Other options

| Parameter | Default | Purpose |
|---|---|---|
| `-Name` | `$env:COMPUTERNAME` | Runner name in the UI |
| `-Version` | `6.3.1` | forgejo-runner version to download |
| `-InstallDir` | `%ProgramFiles%\forgejo-runner` | Where `forgejo-runner.exe` lands |
| `-WorkDir` | `%ProgramData%\forgejo-runner` | Holds `.runner` + `config.yaml` |
| `-NoService` | (off) | Register/configure only; don't install a service |

See `forgejo-node-runner(1)` for the Unix equivalent.
