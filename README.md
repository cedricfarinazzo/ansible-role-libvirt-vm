# 🖥️ Ansible Role: libvirt_vm

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Ansible Galaxy](https://img.shields.io/badge/Ansible%20Galaxy-cedricfarinazzo.libvirt__vm-blue)](https://galaxy.ansible.com/cedricfarinazzo/libvirt_vm)

> **[libvirt](https://libvirt.org/) domain XML for KVM VMs, one file per VM, checked with `virt-xml-validate`. By default the role never defines, starts or autostarts a domain: Pacemaker's [`ocf:heartbeat:VirtualDomain`](https://github.com/ClusterLabs/resource-agents/blob/main/heartbeat/VirtualDomain) runs each VM from its file. With `libvirt_vm_pacemaker: false` it defines them for libvirt alone.**

VirtualDomain undefines a defined domain before every start and creates it again from its `config` file, so a role that defines domains fights it. This role writes the file only. The files go in a directory outside `/etc/libvirt` and `/var/lib/libvirt`, because an undefine deletes files there. It also creates missing disk files from a size or a cloud image (a path or a URL, downloaded once and checksum-verified) and builds cloud-init NoCloud seed ISOs. The libvirt daemon, QEMU, storage pools, bridges, libvirt networks and the Pacemaker resources are out of the role's scope.

## 🚀 Quick Start

Install from Ansible Galaxy ([cedricfarinazzo.libvirt_vm](https://galaxy.ansible.com/cedricfarinazzo/libvirt_vm)), pinned to a release:

```yaml
# requirements.yml
roles:
  - name: cedricfarinazzo.libvirt_vm
    version: 1.1.0
```

```bash
ansible-galaxy role install -r requirements.yml
```

```yaml
- hosts: hypervisors
  become: true
  roles:
    - role: cedricfarinazzo.libvirt_vm
      vars:
        libvirt_vm_vms:
          - name: web
            memory_mib: 2048
            vcpus: 2
            disks:
              - dev: /dev/drbd/by-res/web/0
                target: vda
            interfaces:
              - bridge: br0
                mac: "52:54:00:12:34:56"
```

Then point a VirtualDomain resource at the file:

```bash
pcs resource create web ocf:heartbeat:VirtualDomain \
  config=/etc/libvirt_vm/web.xml hypervisor=qemu:///system migration_transport=ssh
```

The role will:
- ✅ Check every input before any change (anchored patterns, no newline in any value, unicast and unique MACs, unique names and disk targets); a bad value fails with a message naming it, and no file is written
- ✅ Install `libvirt-clients` (for `virt-xml-validate`) and check each file with it before it replaces the old one
- ✅ Write `/etc/libvirt_vm/<name>.xml` (root, `0600`, directory `0700`): block or file disks, bridge NICs, BIOS or EFI (OVMF), a pty serial console, the `org.qemu.guest_agent.0` channel (`virsh domifaddr --source agent`), VNC on `127.0.0.1` by default
- ✅ Create a missing file disk (`size`, `backing_file` or `image`, from a path or an http(s) URL with its checksum); never touch an existing one
- ✅ Build a NoCloud seed ISO per VM with `cloud_init.enabled` and attach it as a read-only cdrom; the seed files never reach the output
- ✅ Remove the file of a VM set `absent`
- ✅ With `libvirt_vm_pacemaker: true` (the default), never run `virsh define`, `start` or `autostart`: a rerun changes nothing and libvirt knows no domain from the role

## 📋 Requirements

- Ansible 2.15+, `become: true`
- On the host: libvirt and QEMU for the VMs to run (installed by you or another role)
- For `firmware: efi`: the `ovmf` package (Debian, Ubuntu)
- Installed by the role when a VM needs them: `qemu-utils` (disks it creates), `xorriso` (seed ISOs)

### Supported Distributions

| Distribution | Version | Status |
|--------------|---------|--------|
| Debian       | 13 (trixie) | ✅ Tested |
| Ubuntu       | 24.04 (noble) | ✅ Tested |
| Ubuntu       | 26.04 (resolute) | ✅ Tested |

The scenarios beyond the default one run on Debian 13.

## ⚙️ Configuration

```yaml
libvirt_vm_vms: []                     # the VMs, see below
libvirt_vm_defaults: {}                # per-VM keys shared by every VM, e.g. {memory_mib: 2048, firmware: efi}
libvirt_vm_xml_dir: /etc/libvirt_vm    # <name>.xml; never under /etc/libvirt or /var/lib/libvirt
libvirt_vm_ovmf_code: /usr/share/OVMF/OVMF_CODE_4M.fd   # EFI loader
libvirt_vm_ovmf_vars: /usr/share/OVMF/OVMF_VARS_4M.fd   # EFI NVRAM template
libvirt_vm_nvram_dir: /var/lib/libvirt_vm/nvram         # <name>_VARS.fd, copied from the template at first start
libvirt_vm_validate: true              # false: no virt-xml-validate check
libvirt_vm_packages:                   # installed when libvirt_vm_validate
  - libvirt-clients
libvirt_vm_pacemaker: true             # false: the role may define, autostart and start VMs (see below)
libvirt_vm_uri: qemu:///system         # virsh's connection, libvirt_vm_pacemaker false only
libvirt_vm_image_cache_dir: /var/cache/libvirt_vm       # downloaded images, <hash>-<file name>
libvirt_vm_cloud_init_dir: /var/lib/libvirt_vm/cloud-init  # seed files and <name>-seed.iso
libvirt_vm_disk_packages:              # installed when the role creates a disk
  - qemu-utils
libvirt_vm_cloud_init_packages:        # installed when a VM has cloud_init.enabled
  - xorriso
```

Each VM (a key the VM leaves out comes from `libvirt_vm_defaults`, then from the value below):

```yaml
- name: web                 # required; [A-Za-z0-9][A-Za-z0-9_.-], up to 63 characters
  state: present            # absent: the file is removed (the NVRAM file is kept)
  memory_mib: 1024          # 16 or more
  vcpus: 1                  # 1-512
  type: kvm                 # qemu: software emulation (TCG), where there is no /dev/kvm
  machine: q35              # e.g. pc, pc-q35-9.2
  cpu_mode: host-passthrough  # host-model | maximum (best for TCG) | none (no <cpu> element)
  firmware: bios            # efi: OVMF loader and NVRAM
  disks:                    # in boot order
    - dev: /dev/vg0/web     # a block device, or file: /srv/images/web.qcow2 (exactly one of them)
      target: vda           # vd*, sd*, hd*; unique within the VM
      format: raw           # qcow2
      bus: virtio           # sata | scsi
      cache: none           # default | writeback | writethrough | directsync | unsafe
      discard: unmap        # ignore
  interfaces:
    - bridge: br0           # an existing Linux bridge, up to 15 characters
      mac: "52:54:00:12:34:56"  # unicast, unique across the VMs; fix it, or the guest sees a new NIC at each start
      model: virtio         # e1000e | rtl8139
  vnc: true                 # a VNC console (autoport from 5900)
  vnc_listen: 127.0.0.1     # an IPv4 or IPv6 address; 0.0.0.0 exposes the console to the network
  serial: true              # a pty serial console (virsh console)
  guest_agent: true         # the org.qemu.guest_agent.0 virtio-serial channel
```

Every key below was added in 1.1.0; at its default it renders exactly what 1.0.0 rendered.

```yaml
  uuid: null                # a fixed UUID; or uuid_deterministic: true, derived from the name
  uuid_deterministic: false
  arch: x86_64              # aarch64 (set machine: virt and the AAVMF firmware paths)
  emulator: null            # e.g. /usr/bin/qemu-system-x86_64; libvirt picks one when unset
  clock_offset: utc         # localtime (Windows guests)
  boot:                     # boot devices in order, kept in the XML: hd | cdrom | network
    - hd
  bootmenu: false           # the firmware's boot menu
  bios_useserial: false     # SeaBIOS output on the serial console
  graphics: null            # replaces vnc/vnc_listen when set, see Graphics
  video: virtio             # vga | qxl | bochs | none (with graphics)
  rng: false                # a virtio-rng device fed by /dev/urandom
  console_log: null         # an absolute path: the serial console goes to this file instead of a pty
  console_log_append: false
  hostdevs: []              # host devices, see Host devices
  cloud_init:               # see Cloud-init
    enabled: false
  xml_template: null        # your own template (relative to the playbook, .j2), given the same __libvirt_vm_vm
  define: false             # libvirt_vm_pacemaker false only: virsh define
  autostart: false          # ... and start at host boot (needs define)
  start: false              # ... and start now (needs define)
  disks:
    - file: /srv/images/web.qcow2
      target: vda
      device: disk          # cdrom (always read-only, no discard)
      readonly: false
      io: null              # native | threads | io_uring
      size: 20G             # created by qemu-img when the file is missing: K, M, G, T
      backing_file: null    # a path or an http(s) URL: a qcow2 overlay on it (needs size, format qcow2)
      backing_format: qcow2 # raw
      image: null           # a path or an http(s) URL: a full copy, grown to size if given
      checksum: null        # sha256:<hex> | sha512:<hex>; required with a URL
  interfaces:
    - type: bridge          # network (a libvirt network) | direct (macvtap)
      bridge: br0           # type bridge; network: default for type network; dev: eth0 for type direct
      mode: vepa            # type direct: bridge | private | passthrough
      mac: "52:54:00:12:34:56"
      model: virtio         # e1000e | e1000 | rtl8139
      driver: null          # {name: vhost | qemu, queues: 1-256}
      alias: null           # rendered ua-<alias>
      name: null            # the host tap name (not vnet*, macvtap*)
      trust_guest_rx_filters: false
```

The boot order is the ordered `boot` list (`<os><boot dev=.../>`); the role does not use per-device `<boot order=>`, which libvirt refuses next to it.

### Pacemaker, define and autostart

With `libvirt_vm_pacemaker: true` (the default) `define`, `start` and `autostart` must stay `false`: validation refuses them. VirtualDomain undefines the domain before each start and starts it itself; a libvirt autostart would start the VM on a node at boot while Pacemaker starts it on another, and the same disk would run twice. Set `libvirt_vm_pacemaker: false` only for VMs that libvirt alone runs: each VM with `define: true` is defined from its file (again when the file changes), `autostart` is set as asked, `start: true` starts it if it is not running, and a VM set `absent` is stopped and undefined with `--keep-nvram`.

### Disks from images

A file disk with `size`, `backing_file` or `image` is created when its file is missing, and never touched after: a later size or image change does nothing to an existing disk. A URL is downloaded once into `libvirt_vm_image_cache_dir`, named by its checksum, and verified with it; a local image with a `checksum` is checked before use. A wrong checksum fails the run before any disk or XML is written. Private images (credentials) are out of scope: download them yourself and give the path.

### Cloud-init

```yaml
cloud_init:
  enabled: true
  files:
    user-data: "{{ lookup('ansible.builtin.template', 'user-data.j2') }}"   # required
    meta-data: "instance-id: web-01\n"     # default: instance-id and local-hostname = the VM name
    network-config: "{{ lookup('ansible.builtin.file', 'web-network.yaml') }}"
    vendor-data: ""
  iso: /srv/shared/web-seed.iso           # default libvirt_vm_cloud_init_dir/<name>-seed.iso; e.g. on a replicated volume
  target: sdz                             # the cdrom's target, sata bus
```

The files are staged in `libvirt_vm_cloud_init_dir/<name>/` (root `0600`) and the ISO (volume id `cidata`, root `0600`) is rebuilt only when one of them changes. Every task that handles their content is `no_log`: give secrets through vaulted variables, never inline, and expect no diff for them.

### Graphics

```yaml
graphics:
  type: spice               # none | vnc | spice
  listen: 127.0.0.1
  port: -1                  # -1 = autoport; or 5900-65535
  password: "{{ vault_web_console_password }}"   # by variable; lands in the XML file (root 0600)
```

A VM with a password renders `no_log`, so neither the password nor that file's diff is printed.

### Host devices

```yaml
hostdevs:
  - type: pci
    source: "0000:3b:00.1"          # the host address, as lspci -D prints it
    destination: "0000:00:10.0"     # optional guest address
    alias: nic0                     # rendered ua-nic0
    managed: true                   # libvirt detaches it from the host driver
  - type: usb
    vendor: "0x1050"
    product: "0x0407"
```

A PCI device can be given to one VM only. Under Pacemaker the device must exist at the same address on every node the VM may run on.

Live migration (`allow-migrate=true` on the resource) needs the same file, disks and bridges on every node: run the role on each.

### EFI

The defaults are the OVMF files of Debian 13 and Ubuntu (package `ovmf`). For Secure Boot with Microsoft keys, set `libvirt_vm_ovmf_code: /usr/share/OVMF/OVMF_CODE_4M.ms.fd` and `libvirt_vm_ovmf_vars: /usr/share/OVMF/OVMF_VARS_4M.ms.fd`. The NVRAM file is the VM's EFI state: it lives outside `/var/lib/libvirt`, so an undefine never removes it, and the role never removes it either. For a VM that moves between nodes, put `libvirt_vm_nvram_dir` on shared storage.

### Removal

`state: absent` (on the VM, or `libvirt_vm_defaults: {state: absent}` for all) removes `<name>.xml`. Remove the Pacemaker resource first: VirtualDomain cannot start a VM without its file. A VM dropped from `libvirt_vm_vms` keeps its file: set it `absent` for one run before dropping it.

## 🎯 Usage Examples

### Two hypervisors, VMs on DRBD, migrated live

```yaml
- hosts: hypervisors
  become: true
  roles:
    - role: cedricfarinazzo.libvirt_vm
      vars:
        libvirt_vm_defaults:
          firmware: efi
          memory_mib: 4096
          vcpus: 2
        libvirt_vm_vms:
          - name: db
            disks:
              - dev: /dev/drbd/by-res/db/0
                target: vda
            interfaces:
              - bridge: br-lan
                mac: "52:54:00:00:00:10"
          - name: dns
            memory_mib: 1024
            disks:
              - dev: /dev/drbd/by-res/dns/0
                target: vda
            interfaces:
              - bridge: br-lan
                mac: "52:54:00:00:00:11"
```

```bash
pcs resource create db ocf:heartbeat:VirtualDomain config=/etc/libvirt_vm/db.xml \
  hypervisor=qemu:///system migration_transport=ssh meta allow-migrate=true
```

### A cloud image VM with cloud-init

```yaml
libvirt_vm_vms:
  - name: app
    memory_mib: 2048
    disks:
      - file: /srv/images/app.qcow2
        format: qcow2
        size: 20G
        backing_file: https://cloud.example.com/images/debian-13-genericcloud-amd64.qcow2
        checksum: "sha512:{{ debian_image_sha512 }}"
        target: vda
    interfaces:
      - bridge: br0
        mac: "52:54:00:00:00:20"
    cloud_init:
      enabled: true
      files:
        user-data: |
          #cloud-config
          ssh_authorized_keys:
            - "{{ app_ssh_public_key }}"
```

### A VM libvirt runs alone, started at boot

```yaml
libvirt_vm_pacemaker: false
libvirt_vm_vms:
  - name: tools
    define: true
    autostart: true
    start: true
    disks:
      - dev: /dev/vg0/tools
        target: vda
    interfaces:
      - type: network
        network: default
        mac: "52:54:00:00:00:30"
        driver:
          name: vhost
          queues: 2
```

### A test VM on a host without KVM

```yaml
libvirt_vm_vms:
  - name: test
    type: qemu
    cpu_mode: maximum
    memory_mib: 256
    disks:
      - file: /srv/images/test.qcow2
        format: qcow2
        target: vda
    vnc: false
```

## 🧪 Testing

```bash
./run-tests.sh                           # default scenario, Debian 13
./run-tests.sh all                       # every distribution, in parallel
./run-tests.sh -s virtualdomain debian13 # Pacemaker's VirtualDomain
tests/validate.test.sh                   # the input checks
```

| Scenario | What it proves |
|----------|----------------|
| `default` | Three VMs with every disk, interface and device option on and off: check mode before converge, files root `0600` in a `0700` directory, `virt-xml-validate` passes, each XML holds what its VM asked for; idempotence; a rerun and check mode change nothing; a changed VM rewritten and a VM set absent removed, the others kept, the absent rerun changes nothing; `virsh list --all` empty after every run |
| `uefi` | An EFI VM next to a BIOS one: the OVMF loader and NVRAM template paths exist on the host, NVRAM directory `0711` outside `/var/lib/libvirt`, `virt-xml-validate` passes, idempotence, no domain defined |
| `options` | No validation and no package (`libvirt-clients` not installed), other XML and NVRAM directories, other OVMF files, `libvirt_vm_defaults` shared and overridden per VM, idempotence |
| `absent` | One VM absent by its own state, then all through `libvirt_vm_defaults`; each rerun changes nothing; the NVRAM directory kept |
| `check` | Check mode on a fresh host reports changes and writes nothing: no directory, no package |
| `failure` | Define or autostart under Pacemaker, a bad, multicast or duplicate MAC, a name with a space, a trailing or embedded newline, a duplicate name, a `..` disk path, a newline in `vnc_listen`, an unknown key, the XML directory under `/var/lib/libvirt`: each fails with a message naming the input, nothing written |
| `regression` | The 1.0.0 inputs (four VMs, BIOS and EFI) render files equal byte for byte to the ones tag 1.0.0 rendered (`files/`); idempotence |
| `disks` | File, block and cdrom disks, read-only, cache, io and discard, four targets in list order (XPath); disks created by `qemu-img` at their format and size; an existing disk keeps its data and size on a rerun with another size |
| `backing` | A local backing file and a backing URL (a local HTTP server) under qcow2 overlays, a full copy from a URL grown to its size; the URL used by two disks downloaded once; with the server stopped a rerun changes nothing (cache); a wrong checksum fails, no disk and no XML written |
| `cloudinit` | Seed ISOs with volume id `cidata` and exactly the given files, meta-data defaulting to the name, ISO `0600`, a read-only sata cdrom in the XML, an ISO at a path of its own; `enabled: false`: no cdrom, no ISO; a changed user-data rebuilds that ISO only and its secret never appears at `-vvv --diff`; then a rerun changes nothing |
| `nics` | Bridge, network and direct interfaces in list order, MAC lower-cased, model, driver name and queues, alias, tap name, trustGuestRxFilters (XPath) |
| `hostdevs` | PCI by host address with a guest address and alias, unmanaged PCI, USB by vendor and product: each attribute exact (XPath) |
| `graphics` | `none` (no graphics, no video), VNC on an address, SPICE on a fixed port with a password from a variable, the 1.0.0 `vnc_listen` still honoured; a changed password rewrites the file and appears nowhere at `-vvv --diff` |
| `boot` | The boot list order kept in the XML (a template that reorders it fails the verify: mutation proven), boot menu, BIOS serial, fixed and deterministic UUIDs, clock, emulator, rng, console log file and its `0750` directory |
| `autostart` | `libvirt_vm_pacemaker: false`: a VM defined, autostarted and running under TCG, one defined with autostart off, one only rendered; autostart turned off on a rerun; all absent: stopped and undefined |
| `virtualdomain` | A single-node Pacemaker in the container: no domain before Pacemaker; `ocf:heartbeat:VirtualDomain` with the rendered `config` starts the VM under TCG (`crm_mon -1`: Started), transient, VNC on `127.0.0.1` only, the guest agent channel in the running domain; after a stop the file is still there |

Every scenario but `autostart` lists `virsh list --all` and fails on any domain. `tests/validate.test.sh` feeds a good and several bad inputs (trailing and embedded newlines included) for every option.

A container has no `/dev/kvm`: the `virtualdomain` and `autostart` scenarios run the VM with `type: qemu`. KVM itself, PCI and USB passthrough are only proven on hosts.

## 🚢 Releases

Once CI passes on `main`, [semantic-release](https://github.com/semantic-release/semantic-release) cuts the version from [Conventional Commits](https://www.conventionalcommits.org/): `fix:` releases a patch, `feat:` a minor, a `!` or `BREAKING CHANGE:` footer a major. A squash merge lands the pull request title (checked in CI), a merge commit lands each branch commit, so both must follow the convention. Each release gets a bare semver tag (`1.2.3`) and GitHub release notes; Ansible Galaxy imports the new tag from the repository. [Renovate](https://docs.renovatebot.com/) keeps the tooling and the pinned GitHub Actions up to date.

## 📦 Dependencies

- ✅ **Ansible Core Modules** (built-in); no collection
- ✅ **OS package** `libvirt-clients` (with `libvirt_vm_validate`)
- ✅ **libvirt and QEMU** on the host, and Pacemaker with `resource-agents` to run the VMs, e.g. from [cedricfarinazzo.pacemaker](https://galaxy.ansible.com/cedricfarinazzo/pacemaker)

## 👥 Authors & Contributors

**Cédric Farinazzo** ([@cedricfarinazzo](https://github.com/cedricfarinazzo)) - *Author and Maintainer*

## 📄 License

MIT, see [LICENSE](LICENSE).
