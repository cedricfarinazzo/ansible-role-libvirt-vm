# CLAUDE.md — ansible-role-libvirt-vm

Orientation for Claude Code sessions in this repository. `AGENTS.md` is a symlink to this file.

## Purpose

Public Ansible role `cedricfarinazzo.libvirt_vm` (Ansible Galaxy): one libvirt domain XML file per VM, checked with `virt-xml-validate`, for Pacemaker's `ocf:heartbeat:VirtualDomain` to run from its `config` file; it also creates missing disks from a size or an image and builds cloud-init seed ISOs. With `libvirt_vm_pacemaker: true` (default) the role never defines, starts or autostarts a domain: VirtualDomain undefines a defined domain before every start. `false` allows `define`/`autostart`/`start` per VM. Generic by design: no reference to any downstream project, host, user or network in code, defaults, docs or commit messages.

## Layout

- `defaults/main.yml` — every user-facing variable (`libvirt_vm_*`), with its generic default.
- `vars/main.yml` — internal values (`__libvirt_vm_*`): the per-VM base values, allowed keys and value lists, the anchored regexes, the forbidden libvirt directories, the present and EFI VM names.
- `tasks/main.yml` — `validate.yml` (every input, before any change), `disks.yml` (downloads by checksum into the cache, missing disks by `qemu-img`), `cloud_init.yml` (seed files `no_log`, ISO by `xorrisofs` when they change), `render.yml` (packages, XML, NVRAM and console log directories, one template per present VM with `validate:`, the files of absent VMs removed), `define.yml` (`libvirt_vm_pacemaker: false` only: `virsh define`, `autostart`, `start`, undefine of absent VMs).
- `templates/domain.xml.j2` — the domain XML.
- `meta/main.yml` — Galaxy metadata; `platforms` lists exactly what CI tests.
- `molecule/shared/` — `collections.yml` (the docker driver), `prepare.yml` (policy-rc.d removed, `libvirt-daemon-system`, `libxml2-utils` and the scenario's `molecule_packages`), `converge.yml`, `run.sh` and `recap.yml` (a rerun from the control node, its recap checked), `xpath.yml` (exact XPath values by `xmllint`), `no_domain.yml` (`virsh list --all` empty).
- `molecule/default/` — three VMs with every option, every distribution; check mode, idempotence, reruns: no change, check mode, a change, a VM absent.
- `molecule/uefi/` — an EFI VM next to a BIOS one; OVMF paths on the host.
- `molecule/options/` — no validation or package, other directories and OVMF files, shared defaults.
- `molecule/absent/` — VMs removed by their state, then all through the defaults.
- `molecule/check/` — check mode on a fresh host writes nothing.
- `molecule/failure/` — each bad input refused with its name, nothing written.
- `molecule/virtualdomain/` — single-node Pacemaker; VirtualDomain starts a rendered file under TCG.
- `molecule/regression/` — 1.0.0 inputs against `files/`, the XML tag 1.0.0 rendered: byte for byte.
- `molecule/{disks,backing,cloudinit,nics,hostdevs,graphics,boot}/` — one option group each, values checked by XPath; `backing` serves its image over a local HTTP server.
- `molecule/autostart/` — `libvirt_vm_pacemaker: false`: define, autostart, start, undefine.
- `tests/validate.test.sh` — good and bad inputs against `tasks/validate.yml` on localhost.
- `run-tests.sh` / `Makefile` — local Molecule entry points; several distros or `all` run in parallel, one log each in `.molecule-logs/`.
- `requirements.yml` (none at runtime), `requirements-dev.txt` (controller tooling, exact pins), `package.json`, `bun.lock`, `.releaserc.json` (semantic-release only).
- `.github/workflows/` — `ci.yml` (lint, Galaxy description length, shellcheck, input tests, default on every distribution, the other scenarios on Debian 13), `pr-title.yml`, `release.yml`.
- `renovate.json` — dependency updates.

## Conventions

- **Conventional Commits** (`conventionalcommits` preset). `feat:` → minor, `fix:` / `perf:` → patch, `!` or `BREAKING CHANGE:` → major; `docs:` / `ci:` / `chore:` / `test:` / `refactor:` / `build:` release nothing. A squash merge lands the **PR title** (`pr-title.yml` checks it).
- **Breaking = a consumer must act:** dropping a platform, renaming or removing a variable or VM key, changing a default that changes the rendered XML or its path.
- **Tags are bare semver** (`1.2.3`), notes in GitHub Releases; no `CHANGELOG.md`.
- **No ruleset or branch protection on `main`:** a ruleset blocks semantic-release. Changes still go through a PR with green CI.
- **Variables:** every user-facing variable starts with `libvirt_vm_`, is defined in `defaults/main.yml`, asserted in `tasks/validate.yml` (with a case in `tests/validate.test.sh`) and documented in `README.md` in the same PR; a new VM key also goes in `__libvirt_vm_base` and `__libvirt_vm_vm_keys`. Internal values start with `__libvirt_vm_`.
- **Every input checked before any change.** Every regex ends in `\Z`, never `$`, and lives in `vars/main.yml` (a Jinja literal unescapes `\`); bad cases feed trailing and embedded newlines.
- **Never define, start or autostart a domain under Pacemaker:** `virsh` only in `define.yml`, imported when `libvirt_vm_pacemaker` is false; no `community.libvirt`. Every scenario but `autostart` lists `virsh list --all` and fails on any domain.
- **1.0.0 inputs render the 1.0.0 XML:** a new key renders nothing at its default; the `regression` scenario compares bytes. Regenerate `files/` only for a breaking change.
- **Secrets never printed:** `-v` prints each loop item in full, so with a graphics password or `cloud_init` anywhere every task looping over VMs is `no_log: "{{ __libvirt_vm_secret }}"`; seed staging is always `no_log`. A new task looping over VMs takes the same line. The `cloudinit` and `graphics` side effects grep `-vvv --diff` output for the secret.
- **An existing disk is data:** created only when missing (`creates:`), never resized or rewritten.
- **No file under `/etc/libvirt` or `/var/lib/libvirt`:** an undefine deletes files there; `validate.yml` refuses those directories.
- **The NVRAM file is the VM's state:** never removed by the role.
- **Examples never copy a real deployment:** made-up names, locally administered or `52:54:00` MACs, documentation addresses.
- **GitHub Actions pinned by full commit SHA**, tag in a trailing comment. Exact pins for tooling; `renovate.json` identical in the sibling roles: change them together.
- **License:** MIT.

## Supported platforms

`meta/main.yml` `platforms`, the CI matrix, the `README.md` table, `run-tests.sh --help` and the `Makefile` list the same set.

## How releases work

1. A PR is squash-merged into `main` with a Conventional Commit title.
2. When `ci.yml` passes on the push to `main`, `release.yml` runs `bunx semantic-release`: tag, GitHub Release, comments on released PRs.
3. Ansible Galaxy imports each new tag by itself.

## Commands

- Lint: `source .venv/bin/activate && yamllint . && ansible-lint && shellcheck run-tests.sh tests/*.sh molecule/shared/*.sh`
- Input tests: `tests/validate.test.sh`
- Molecule: `./run-tests.sh debian13`, `./run-tests.sh -s <scenario> debian13`, `./run-tests.sh all`

## Gotchas

- VirtualDomain reads the domain name with `egrep '<name>.*</name>'` on one line: a one-line XML fails with 'Unable to determine domain name' then 'environment is invalid'. The template keeps `<name>` alone on its line.
- A container has no `/dev/kvm`: the `virtualdomain` scenario uses `type: qemu` and `cpu_mode: maximum` (`host-passthrough` needs KVM).
- Docker's 64 MB `/dev/shm` fills with corosync's and pacemaker's libqb buffers: the `virtualdomain` platform sets `shm_size: 512m`.
- `xmllint --xpath 'string(...)'` prints the value with no newline; `count(...)` prints an integer: compare as strings (`xpath.yml`).
- Jinja `\n` in a plain YAML scalar stays backslash-n: an assert comparing file content with `\n` is double-quoted.
- `-e libvirt_vm_defaults=...` replaces the whole mapping: the base values live in `vars/main.yml` (`__libvirt_vm_base`) and `libvirt_vm_defaults` is merged over them, so a partial mapping works.

## Self Improvement Loop

Keep `CLAUDE.md` and `README.md` accurate, in the same PR as the change. Update when a variable, platform, file or convention changes, or a trap costs a debugging round (one Gotchas line: symptom, cause, fix). New fact replaces the old clause; never append a changelog.
