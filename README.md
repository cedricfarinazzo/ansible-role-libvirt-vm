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
  graphics: null            # a mapping or a list of them; replaces vnc/vnc_listen when set, see Graphics
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

### Role Variables

Every value is checked before any change; a bad one fails the run naming the input. Text values are matched to the end (a trailing or embedded newline is refused). "Shape" is what validation accepts: the role does not ask libvirt or QEMU whether a value exists on your host.

#### Role-level variables

| Variable | Default | Allowed | What it does |
|----------|---------|---------|--------------|
| `libvirt_vm_vms` | `[]` | list of VM mappings | The VMs. Names are unique; MACs are unique across VMs. |
| `libvirt_vm_defaults` | `{}` | mapping of the per-VM keys below, without `name` | Applied to every VM; a VM's own key wins. Checked like a VM's own keys. |
| `libvirt_vm_xml_dir` | `/etc/libvirt_vm` | absolute path of `A-Za-z0-9_.:+/-`, no `.` or `..` segment, not under `/etc/libvirt` or `/var/lib/libvirt` | Where `<name>.xml` goes (root `0700`). Outside libvirt's directories because an undefine deletes files there. |
| `libvirt_vm_ovmf_code`, `libvirt_vm_ovmf_vars` | OVMF 4M files of Debian and Ubuntu | absolute path (same shape) | EFI loader and NVRAM template for `firmware: efi`. Point to the `.ms.` files for Secure Boot with Microsoft keys. |
| `libvirt_vm_nvram_dir` | `/var/lib/libvirt_vm/nvram` | absolute path, not under `/etc/libvirt` or `/var/lib/libvirt` | Per-VM `<name>_VARS.fd`, copied from the template at first start; never removed by the role. Put it on shared storage for a VM that moves between nodes. |
| `libvirt_vm_validate` | `true` | boolean | `true`: each file passes `virt-xml-validate` before it is written. `false`: no check, no package. |
| `libvirt_vm_packages` | `[libvirt-clients]` | list | Installed when `libvirt_vm_validate` is true. `[]` installs nothing. |
| `libvirt_vm_pacemaker` | `true` | boolean | `true`: Pacemaker's VirtualDomain runs the domains; the role refuses `define`, `start`, `autostart` and never calls `virsh`. `false`: libvirt alone runs them, see Pacemaker, define and autostart. |
| `libvirt_vm_uri` | `qemu:///system` | `qemu[+transport]://[host]/system` or `/session` | virsh's connection; used with `libvirt_vm_pacemaker: false` only. |
| `libvirt_vm_image_cache_dir` | `/var/cache/libvirt_vm` | absolute path | Downloaded images, named `<checksum>-<file name>`. Only a missing disk's image is downloaded; a copied `image` is removed once its disks exist, a `backing_file` stays (its overlays read it). |
| `libvirt_vm_cloud_init_dir` | `/var/lib/libvirt_vm/cloud-init` | absolute path, not under libvirt's directories | Staged seed files and the default `<name>-seed.iso`. Root `0711`: qemu traverses it to open the ISO, nobody else lists it; each VM's staging directory is root `0700`. |
| `libvirt_vm_disk_packages` | `[qemu-utils]` | list | Installed only when a disk is created. |
| `libvirt_vm_cloud_init_packages` | `[xorriso]` | list | Installed only when a VM has `cloud_init.enabled`. |

#### Per-VM keys

| Key | Default | Allowed | What it does and when to pick it |
|-----|---------|---------|----------------------------------|
| `name` | required | `[A-Za-z0-9][A-Za-z0-9_.-]`, up to 63 characters | The domain name and the file name. |
| `state` | `present` | `present`, `absent` | `absent` removes the XML file, the staged seed files and the default-path seed ISO; disks and NVRAM are kept. With `libvirt_vm_pacemaker: false` it also stops and undefines the domain. |
| `memory_mib` | `1024` | integer, 16 or more | Guest RAM in MiB (also the current memory). |
| `vcpus` | `1` | integer, 1-512 | Virtual CPUs. |
| `type` | `kvm` | `kvm`, `qemu` | `kvm`: hardware acceleration, needs `/dev/kvm` on the host; use it on real hosts. `qemu`: software emulation (TCG), slow, for hosts without KVM (containers, CI) and for another `arch` than the host. |
| `machine` | `q35` | `[a-z0-9][a-z0-9_.-]`, up to 64 characters | The QEMU machine type; only its shape is checked, list valid ones with `qemu-system-x86_64 -machine help`. `q35`: modern x86_64 chipset (PCIe), the default. `pc`: the older i440fx chipset, for old guests. A versioned name (`pc-q35-9.2`) pins the guest hardware ABI: pick it for VMs live-migrated between hosts with different QEMU versions, so every host presents the same hardware. `virt`: the machine for `aarch64`. |
| `cpu_mode` | `host-passthrough` | `host-passthrough`, `host-model`, `maximum`, `none` | `host-passthrough`: the guest sees the host CPU exactly; fastest, but live migration needs identical CPUs. `host-model`: a named CPU model close to the host's; migratable across similar hosts. `maximum`: every feature QEMU can offer; the choice with `type: qemu`. `none`: no `<cpu>` element, libvirt's default for the machine. |
| `firmware` | `bios` | `bios`, `efi` | `bios`: SeaBIOS. `efi`: OVMF loader plus a per-VM NVRAM file (needs the `ovmf` package). See EFI. |
| `arch` | `x86_64` | `x86_64`, `aarch64` | Guest architecture. For `aarch64` also set `machine: virt` and the AAVMF firmware paths; it needs `type: qemu` on an x86_64 host. |
| `emulator` | `null` | absolute path | The QEMU binary, e.g. `/usr/bin/qemu-system-x86_64`. `null`: libvirt picks it. |
| `uuid` | `null` | `8-4-4-4-12` hex digits | A fixed UUID, kept across a redefinition. Wins over `uuid_deterministic`. |
| `uuid_deterministic` | `false` | boolean | `true` (and no `uuid`): the UUID is derived from the name, the same on every host and run. `false` with no `uuid`: libvirt generates one at define time. |
| `clock_offset` | `utc` | `utc`, `localtime` | The guest's hardware clock. `localtime` for Windows guests, which keep local time in the RTC. |
| `boot` | `[hd]` | non-empty list of distinct `hd`, `cdrom`, `network` | Boot devices in order: the firmware tries the first, then the next. The order is kept in `<os><boot dev=/>`. The role does not use per-device `<boot order=>`: libvirt refuses it next to `<os><boot>`. `[cdrom, hd]` installs from a cdrom and then boots the disk. |
| `bootmenu` | `false` | boolean | `true`: the firmware's boot menu is shown at start. |
| `bios_useserial` | `false` | boolean | `true`: SeaBIOS prints on the serial console (useful with `console_log`). BIOS only. |
| `disks` | `[]` | list of mappings, see below | The disks, in the order given. |
| `interfaces` | `[]` | list of mappings, see below | The network interfaces. |
| `vnc` | `true` | boolean | 1.0.0 key: `true` gives a VNC console on `vnc_listen`; `false` none. Ignored when `graphics` is set. |
| `vnc_listen` | `127.0.0.1` | IPv4 or IPv6 address | 1.0.0 key: the address the VNC console listens on; see Graphics. Ignored when `graphics` is set. |
| `graphics` | `null` | mapping, or a non-empty list of mappings, see below | The console. When set it replaces `vnc` and `vnc_listen`. A list gives one device per entry (VNC and SPICE at once): each type at most once, `none` only alone, each fixed port once; a SPICE entry in a list also adds the `com.redhat.spice.0` agent channel. |
| `video` | `virtio` | `virtio`, `vga`, `qxl`, `bochs`, `none` | The video device, one per VM, rendered only when there is a graphics device. `virtio`: the default for Linux guests. `vga`: the most compatible, for guests without virtio-gpu drivers. `qxl`: the SPICE-optimised device. `bochs`: a simple framebuffer for UEFI guests. `none`: no video model. |
| `serial` | `true` | boolean | A pty serial console, reached with `virsh console`. |
| `console_log` | `null` | absolute path | The serial console is written to this file instead of a pty (its directory is created `0750`). |
| `console_log_append` | `false` | boolean | `true`: keep the file across restarts and append. `false`: truncated at each start. |
| `guest_agent` | `true` | boolean | Adds the `org.qemu.guest_agent.0` virtio-serial channel; the agent in the guest then answers `virsh domifaddr --source agent` and clean shutdowns. |
| `rng` | `false` | boolean | `true`: a virtio-rng device fed by the host's `/dev/urandom`; gives guests entropy at boot. |
| `hostdevs` | `[]` | list of mappings, see below | PCI and USB devices of the host given to the guest. |
| `cloud_init` | `{enabled: false}` | mapping, see below | A NoCloud seed ISO attached as a read-only cdrom. |
| `xml_template` | `null` | relative path ending `.j2` | Your own template instead of `domain.xml.j2`, given the same variables. The role's validation still runs on its inputs, not on your template. |
| `define` | `false` | boolean | `libvirt_vm_pacemaker: false` only: `virsh define` the file (again when it changes). |
| `autostart` | `false` | boolean | `libvirt_vm_pacemaker: false` only, needs `define`: libvirt starts the domain at host boot. Keep `false` under Pacemaker: the cluster owns the start, and a libvirt autostart would run the same disk on two nodes. |
| `start` | `false` | boolean | `libvirt_vm_pacemaker: false` only, needs `define`: start the domain when it is not running. |

#### Disk keys

A disk has exactly one of `dev` and `file`, and a `target`.

| Key | Default | Allowed | What it does and when to pick it |
|-----|---------|---------|----------------------------------|
| `dev` | none | `/dev/...` of `A-Za-z0-9_.:+/-`, no `.` or `..` segment | A block device (LVM, DRBD, a LINSTOR resource). Never created by the role. |
| `file` | none | absolute path (same shape) | An image file. Created by the role only when `size`, `backing_file` or `image` is given and the file is missing. |
| `target` | required | `vd`, `sd` or `hd` plus 1-2 letters, unique in the VM | The guest device name, and the order within a bus. Pair it with `bus`: `vd*` for virtio. |
| `format` | `raw` | `raw`, `qcow2` | `raw`: no overhead, for block devices. `qcow2`: for files with snapshots, overlays or thin growth. |
| `bus` | `virtio` | `virtio`, `sata`, `scsi`, `usb` | `virtio`: fastest, needs guest drivers (every Linux). `sata`: the compatible choice for installers and cdroms. `scsi`: many disks, needs a SCSI controller in the guest. `usb`: removable media. |
| `cache` | `none` | `none`, `default`, `writeback`, `writethrough`, `directsync`, `unsafe` | `none`: bypass the host page cache; the right choice for replicated storage (DRBD) and for live migration. `writeback`: fast, data in the host cache is lost on a host crash. `writethrough`: reads cached, writes synced. `directsync`: no cache and every write synced, slowest. `unsafe`: ignores flushes, only for throwaway VMs. `default`: QEMU's own default. |
| `io` | `null` | `native`, `threads`, `io_uring` | The asynchronous I/O mode. `null`: libvirt's choice. `native`: Linux AIO, with `cache: none` on block devices. `threads`: portable, works with cached files. `io_uring`: lowest overhead on a recent kernel. |
| `discard` | `unmap` | `unmap`, `ignore` | `unmap`: the guest's TRIM frees blocks on thin volumes and sparse files. `ignore`: never frees. Not rendered for a cdrom. |
| `device` | `disk` | `disk`, `cdrom` | `cdrom` is always read-only and cannot be created by the role. |
| `readonly` | `false` | boolean | `true`: the guest cannot write; use it for a shared image. |
| `size` | none | `1-9 digits` plus optional `K`, `M`, `G`, `T` | Virtual size. With no `backing_file`/`image`, an empty disk of this size is created when the file is missing. |
| `backing_file` | none | absolute path or `http(s)://` URL | A qcow2 overlay on this base image (`format: qcow2` and `size` required). The base stays untouched and shared; the overlay holds the VM's changes. Created only when missing. |
| `backing_format` | `qcow2` | `raw`, `qcow2` | The format of the base image; only with `backing_file`. Cloud images are usually `qcow2`. |
| `image` | none | absolute path or `http(s)://` URL | A full independent copy of the image into `file`, converted to `format`, then grown to `size` when given. Created only when missing. Exclusive with `backing_file`. |
| `checksum` | none | `sha256:` plus 64 hex or `sha512:` plus 128 hex | Verifies the source image. Required with a URL; optional (checked before use) with a local path. A mismatch fails before any disk or XML is written. |

An existing disk file is the VM's data: later changes to `size`, `backing_file` or `image` do nothing to it.

#### Interface keys

`mac` is required for every interface (a stable address keeps the guest's NIC identity) and must be a unicast MAC.

| Key | Default | Allowed | What it does and when to pick it |
|-----|---------|---------|----------------------------------|
| `type` | `bridge` | `bridge`, `network`, `direct` | `bridge`: attach to an existing Linux bridge (`bridge`). `network`: a libvirt network (`network`). `direct`: a macvtap on a host NIC (`dev`, `mode`), no bridge needed but the host cannot talk to the guest through it. The key of the chosen type is required, the others are refused. |
| `bridge` | none | `A-Za-z0-9_.-`, up to 15 characters | The bridge name, `type: bridge`. |
| `network` | none | a name like a VM name | The libvirt network, `type: network`. |
| `dev` | none | `A-Za-z0-9_.-`, up to 15 characters | The host NIC, `type: direct`. |
| `mode` | `vepa` | `vepa`, `bridge`, `private`, `passthrough` | `type: direct` only. `vepa`: traffic goes out to the switch even between guests (needs a switch that reflects). `bridge`: guests on the same NIC talk directly. `private`: guests cannot talk to each other. `passthrough`: the guest takes the whole NIC (one guest per NIC). |
| `mac` | required | `xx:xx:xx:xx:xx:xx`, even first octet, upper or lower case | The guest MAC, stored lower-case; unique across VMs. |
| `model` | `virtio` | `virtio`, `e1000e`, `e1000`, `rtl8139` | `virtio`: fastest, needs guest drivers. `e1000e`, `e1000`: emulated Intel NICs for guests without virtio. `rtl8139`: the oldest guests. |
| `driver` | `null` | mapping `{name, queues}` | Host-side backend for a virtio NIC. `name: vhost`: packets handled in the host kernel (fast, the usual choice); `name: qemu`: handled in the QEMU process (needed in some restricted setups). `queues` 1-256: multiqueue, set it to the guest's vCPU count for high throughput, and enable it in the guest with `ethtool -L`. |
| `alias` | `null` | `A-Za-z0-9_-`, up to 32 characters | Rendered `ua-<alias>`: a stable device alias (libvirt keeps only `ua-` aliases). |
| `name` | `null` | like `bridge`, not starting `vnet`, `macvtap` or `macvlan` | The host tap device name, instead of a generated `vnetN`; useful for firewall and monitoring rules. |
| `trust_guest_rx_filters` | `false` | boolean | `true`: the host applies the guest's MAC and VLAN filter changes. Needed for some SR-IOV and macvtap setups; it lets the guest change what it receives, so keep it off for untrusted guests. |

#### Graphics keys

The console is served by the QEMU process on the host, not inside the guest: `listen` is an address of the host. Ports start at 5900 (display `:0` is 5900, `:1` is 5901); with `port: -1` libvirt takes the next free one, and `virsh vncdisplay <name>` (or `virsh domdisplay`) prints which. With `127.0.0.1` the console is reachable only on the host: use an SSH tunnel (`ssh -L 5900:127.0.0.1:5900 host`). `0.0.0.0` (or a LAN address) exposes it to the network; set a `password` then.

| Key | Default | Allowed | What it does |
|-----|---------|---------|--------------|
| `type` | `vnc` (a mapping with `vnc: false`: `none`) | `none`, `vnc`, `spice` | `none`: no graphics device and no video (headless, serial only). `vnc`: any VNC client. `spice`: SPICE client; better with `video: qxl`, clipboard and USB redirection. |
| `listen` | `vnc_listen` (`127.0.0.1`) | IPv4 or IPv6 address | The host address to bind. |
| `port` | `-1` | `-1` or an integer 5900-65535 | `-1`: autoport from 5900. A fixed port must be free on the host and distinct per VM. |
| `password` | none | 1-64 characters of `A-Za-z0-9` and ``!#$%()*+,./:;=?@^_{|}~-`` | The console password. Give it through a vaulted variable; it is written into the XML file (root `0600`) and never printed. |

#### Host device keys

| Key | Default | Allowed | What it does |
|-----|---------|---------|--------------|
| `type` | required | `pci`, `usb` | `pci`: a PCIe device (a NIC, a GPU, an HBA). `usb`: a USB device by id. |
| `source` | required for `pci` | `dddd:bb:ss.f`, as `lspci -D` prints | The device's address on the host. |
| `vendor`, `product` | required for `usb` | `0x` plus 4 hex digits | The ids `lsusb` prints (`ID vendor:product`). |
| `destination` | `null` | `dddd:bb:ss.f` | The address the guest sees; `null`: libvirt assigns one. |
| `alias` | `null` | like an interface alias | Rendered `ua-<alias>`. |
| `managed` | `true` | boolean | `true`: libvirt detaches the device from its host driver and binds `vfio-pci` at start, then gives it back. `false`: you bind it to `vfio-pci` yourself beforehand and libvirt only attaches it; pick it when the device must never return to a host driver. |

#### Cloud-init keys

| Key | Default | Allowed | What it does |
|-----|---------|---------|--------------|
| `enabled` | `false` | boolean | `true`: build a NoCloud seed ISO (volume id `cidata`) and attach it as a read-only cdrom. `false`: no cdrom, no ISO built. |
| `files` | `{}` | mapping of `user-data`, `meta-data`, `network-config`, `vendor-data` to strings | The seed content; `user-data` is required when enabled. `meta-data` defaults to `instance-id` and `local-hostname` set to the VM name. A file left out is removed from the seed. The ISO is rebuilt only when a file changes. |
| `iso` | `libvirt_vm_cloud_init_dir/<name>-seed.iso` | absolute path, not under libvirt's directories | Where the ISO lives; set it to put the seed on replicated storage, so a VM that moves between nodes finds it. An ISO at your own path is never removed by the role. |
| `target` | `sdz` | like a disk `target` | The cdrom's device name (sata bus); unique among the VM's disk targets. |

Seed content may hold passwords and keys: every task that handles it runs `no_log` and the staged files and the ISO are root `0600` (libvirt hands the ISO to the qemu user at start), the staging directories `0700`, `libvirt_vm_cloud_init_dir` `0711` so qemu can reach the ISO without listing it. Pass secrets through vaulted variables, never inline.

### Pacemaker, define and autostart

With `libvirt_vm_pacemaker: true` (the default) `define`, `start` and `autostart` must stay `false`: validation refuses them. VirtualDomain undefines the domain before each start and starts it itself; a libvirt autostart would start the VM on a node at boot while Pacemaker starts it on another, and the same disk would run twice. Set `libvirt_vm_pacemaker: false` only for VMs that libvirt alone runs: each VM with `define: true` is defined from its file (again when the file changes), `autostart` is set as asked, `start: true` starts it if it is not running, and a VM set `absent` is stopped and undefined with `--keep-nvram`.

### Disks from images

A file disk with `size`, `backing_file` or `image` is created when its file is missing, and never touched after: a later size or image change does nothing to an existing disk. A URL is downloaded into `libvirt_vm_image_cache_dir` only when a disk that needs it is missing, named by its checksum and verified with it; a copied `image` is removed after the copy, a `backing_file` is kept; a local image with a `checksum` is checked before use. A wrong checksum fails the run before any disk or XML is written. Private images (credentials) are out of scope: download them yourself and give the path.

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

Several consoles at once, each reached through an SSH tunnel to the host:

```yaml
graphics:
  - type: vnc
    listen: 127.0.0.1
  - type: spice
    listen: 127.0.0.1       # the list form adds the SPICE agent channel (clipboard, resolution)
```

The single mapping renders exactly what 1.1.0 rendered: no SPICE channel. Use a list of one entry to get it.

When any VM (or `libvirt_vm_defaults`) has a graphics password (in a mapping or a list entry) or a `cloud_init` key, every task whose loop item holds a VM runs `no_log`, so `-v` and `--diff` print neither the secret nor the files. A validation failure then reads `censored`: find the bad input by running without the secrets, or with `no_log` off in a private run.

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

`state: absent` (on the VM, or `libvirt_vm_defaults: {state: absent}` for all) removes `<name>.xml`, and its staged seed files and `<name>-seed.iso` in `libvirt_vm_cloud_init_dir` (an ISO at its own `cloud_init.iso` path is left to you); disk files are never removed. Remove the Pacemaker resource first: VirtualDomain cannot start a VM without its file. A VM dropped from `libvirt_vm_vms` keeps its file: set it `absent` for one run before dropping it.

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
| `regression` | The 1.0.0 inputs (four VMs, BIOS and EFI) and the 1.1.0 graphics mappings (VNC on a fixed port, SPICE with a password, none) render files equal byte for byte to the ones their tag rendered (`files/`); idempotence |
| `disks` | File, block and cdrom disks, read-only, cache, io and discard, four targets in list order (XPath); disks created by `qemu-img` at their format and size; an existing disk keeps its data and size on a rerun with another size |
| `backing` | A local backing file and a backing URL (a local HTTP server) under qcow2 overlays, a full copy from a URL grown to its size; each URL downloaded once, the copied image removed from the cache, the backing file kept; with the server stopped a rerun downloads nothing and changes nothing; a wrong checksum fails, no disk and no XML written |
| `cloudinit` | Seed ISOs with volume id `cidata` and exactly the given files, meta-data defaulting to the name, ISO `0600`, seed directory `0711` and staging `0700`, the qemu user reaches the ISO but lists neither, a read-only sata cdrom in the XML, an ISO at a path of its own; `enabled: false`: no cdrom, no ISO; a changed user-data rebuilds that ISO only and its secret never appears at `-vvv --diff`; then a rerun changes nothing; set absent, the staged files and default ISO removed, an ISO at its own path kept |
| `nics` | Bridge, network and direct interfaces in list order, MAC lower-cased, model, driver name and queues, alias, tap name, trustGuestRxFilters (XPath) |
| `hostdevs` | PCI by host address with a guest address and alias, unmanaged PCI, USB by vendor and product: each attribute exact (XPath) |
| `graphics` | `none` (no graphics, no video), VNC on an address, SPICE on a fixed port with a password from a variable, the 1.0.0 `vnc_listen` still honoured; a list of VNC and SPICE renders both in order with one video and the SPICE channel, a list of one `none` nothing, a list entry without a type VNC; a changed password rewrites the files and appears nowhere at `-vvv --diff`, nor a password held only in a list |
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
