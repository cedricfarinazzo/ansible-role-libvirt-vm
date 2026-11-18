# 🖥️ Ansible Role: libvirt_vm

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Ansible Galaxy](https://img.shields.io/badge/Ansible%20Galaxy-cedricfarinazzo.libvirt__vm-blue)](https://galaxy.ansible.com/cedricfarinazzo/libvirt_vm)

> **[libvirt](https://libvirt.org/) domain XML for KVM VMs, one file per VM, checked with `virt-xml-validate`. The role never defines, starts or autostarts a domain: Pacemaker's [`ocf:heartbeat:VirtualDomain`](https://github.com/ClusterLabs/resource-agents/blob/main/heartbeat/VirtualDomain) runs each VM from its file.**

VirtualDomain undefines a defined domain before every start and creates it again from its `config` file, so a role that defines domains fights it. This role writes the file only. The files go in a directory outside `/etc/libvirt` and `/var/lib/libvirt`, because an undefine deletes files there. The libvirt daemon, QEMU, disk images, storage pools, bridges and the Pacemaker resources are out of the role's scope.

## 🚀 Quick Start

Install from Ansible Galaxy ([cedricfarinazzo.libvirt_vm](https://galaxy.ansible.com/cedricfarinazzo/libvirt_vm)), pinned to a release:

```yaml
# requirements.yml
roles:
  - name: cedricfarinazzo.libvirt_vm
    version: 1.0.0
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
- ✅ Remove the file of a VM set `absent`
- ✅ Never run `virsh define`, `start` or `autostart`: a rerun changes nothing and libvirt knows no domain from the role

## 📋 Requirements

- Ansible 2.15+, `become: true`
- On the host: libvirt and QEMU for the VMs to run (installed by you or another role)
- For `firmware: efi`: the `ovmf` package (Debian, Ubuntu)

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
| `failure` | A bad, multicast or duplicate MAC, a name with a space, a trailing or embedded newline, a duplicate name, a `..` disk path, a newline in `vnc_listen`, an unknown key, the XML directory under `/var/lib/libvirt`: each fails with a message naming the input, nothing written |
| `virtualdomain` | A single-node Pacemaker in the container: no domain before Pacemaker; `ocf:heartbeat:VirtualDomain` with the rendered `config` starts the VM under TCG (`crm_mon -1`: Started), transient, VNC on `127.0.0.1` only, the guest agent channel in the running domain; after a stop the file is still there |

A container has no `/dev/kvm`: the `virtualdomain` scenario runs the VM with `type: qemu`. KVM itself is only proven on hosts.

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
