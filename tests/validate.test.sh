#!/usr/bin/env bash
# The role's input checks: each bad input fails before anything changes, the good ones pass.
# Runs tasks/validate.yml on localhost; needs ansible-playbook on PATH, no host.
set -euo pipefail

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir "$WORK/roles"
ln -s "$REPO" "$WORK/roles/libvirt_vm"
cat > "$WORK/play.yml" <<'PLAY'
- name: Validate libvirt_vm inputs
  hosts: localhost
  gather_facts: false
  tasks:
    - name: Validate
      ansible.builtin.include_role:
        name: libvirt_vm
        tasks_from: validate.yml
PLAY
fails=0
run() { ANSIBLE_ROLES_PATH=$WORK/roles ansible-playbook -i localhost, -c local -e "$1" "$WORK/play.yml" > "$WORK/out" 2>&1; }
good() { if run "$2"; then echo "ok   accepted: $1"; else echo "FAIL rejected a good input: $1" >&2; tail -5 "$WORK/out" >&2; fails=$((fails + 1)); fi; }
# Rejected by an assert, never by a templating crash: that would pass for the wrong reason.
bad() {
  if run "$2"; then echo "FAIL accepted: $1" >&2; fails=$((fails + 1))
  elif grep -qE '"assertion"|Action failed: ' "$WORK/out"; then echo "ok   rejected: $1"
  else echo "FAIL failed without an assertion: $1" >&2; grep -m3 -E 'ERROR|fatal' "$WORK/out" >&2; fails=$((fails + 1)); fi
}


# A good VM; each bad case changes one input of it
VM='"name": "web", "disks": [{"dev": "/dev/vg0/web", "target": "vda"}], "interfaces": [{"bridge": "br0", "mac": "02:00:00:00:00:01"}]'
vm() { echo "{\"libvirt_vm_vms\": [{$VM$1}]}"; }
good "no VM" '{}'
good "one VM, defaults" "$(vm '')"
good "every option" "$(vm ', "state": "present", "memory_mib": 4096, "vcpus": 4, "type": "qemu", "machine": "pc-q35-9.2", "cpu_mode": "maximum", "firmware": "efi", "vnc": false, "vnc_listen": "::1", "serial": false, "guest_agent": false')"
good "a file disk, every disk option" '{"libvirt_vm_vms": [{"name": "db", "disks": [{"file": "/srv/images/db.qcow2", "format": "qcow2", "target": "sda", "bus": "scsi", "cache": "writeback", "discard": "ignore"}]}]}'
good "an upper-case MAC, model e1000e" '{"libvirt_vm_vms": [{"name": "a", "interfaces": [{"bridge": "br-lan.20", "mac": "52:54:00:AB:CD:EF", "model": "e1000e"}]}]}'
good "VNC on every address" "$(vm ', "vnc_listen": "0.0.0.0"')"
good "absent" "$(vm ', "state": "absent"')"
good "two VMs" '{"libvirt_vm_vms": [{"name": "a"}, {"name": "b", "cpu_mode": "none"}]}'
good "defaults changed" '{"libvirt_vm_defaults": {"memory_mib": 2048, "firmware": "efi"}, "libvirt_vm_vms": [{"name": "a"}]}'
good "other directories" '{"libvirt_vm_xml_dir": "/srv/vm-xml", "libvirt_vm_nvram_dir": "/srv/vm-nvram"}'
good "no validation, no packages" '{"libvirt_vm_validate": false, "libvirt_vm_packages": []}'
bad "VMs as a mapping" '{"libvirt_vm_vms": {"name": "a"}}'
bad "a VM as a string" '{"libvirt_vm_vms": ["a"]}'
bad "an unknown VM key" "$(vm ', "autostart": true')"
bad "no name" '{"libvirt_vm_vms": [{"memory_mib": 512}]}'
bad "a name with a space" '{"libvirt_vm_vms": [{"name": "my vm"}]}'
bad "a name with a trailing newline" '{"libvirt_vm_vms": [{"name": "web\n"}]}'
bad "a name with an embedded newline" '{"libvirt_vm_vms": [{"name": "web\nx"}]}'
bad "a name with a slash" '{"libvirt_vm_vms": [{"name": "../web"}]}'
bad "a name starting with a dot" '{"libvirt_vm_vms": [{"name": ".web"}]}'
bad "a duplicate name" '{"libvirt_vm_vms": [{"name": "a"}, {"name": "a"}]}'
bad "an unknown state" "$(vm ', "state": "running"')"
bad "memory as a string" "$(vm ', "memory_mib": "1G"')"
bad "memory too small" "$(vm ', "memory_mib": 8')"
bad "zero vCPUs" "$(vm ', "vcpus": 0')"
bad "vCPUs as a boolean" "$(vm ', "vcpus": true')"
bad "an unknown type" "$(vm ', "type": "xen"')"
bad "a machine with a quote" "$(vm ', "machine": "q35'"'"'"')"
bad "a machine with a trailing newline" "$(vm ', "machine": "q35\n"')"
bad "an unknown CPU mode" "$(vm ', "cpu_mode": "custom"')"
bad "an unknown firmware" "$(vm ', "firmware": "uefi"')"
bad "vnc as a string" "$(vm ', "vnc": "yes"')"
bad "a VNC listen that is no address" "$(vm ', "vnc_listen": "localhost"')"
bad "a VNC listen with an octet above 255" "$(vm ', "vnc_listen": "999.1.1.1"')"
bad "a VNC listen with a trailing newline" "$(vm ', "vnc_listen": "127.0.0.1\n"')"
bad "serial as a string" "$(vm ', "serial": "no"')"
bad "guest_agent as a number" "$(vm ', "guest_agent": 1')"
bad "disks as a mapping" '{"libvirt_vm_vms": [{"name": "a", "disks": {"dev": "/dev/sda"}}]}'
bad "a disk with both dev and file" '{"libvirt_vm_vms": [{"name": "a", "disks": [{"dev": "/dev/sda", "file": "/srv/a.img", "target": "vda"}]}]}'
bad "a disk with neither dev nor file" '{"libvirt_vm_vms": [{"name": "a", "disks": [{"target": "vda"}]}]}'
bad "a disk with no target" '{"libvirt_vm_vms": [{"name": "a", "disks": [{"dev": "/dev/sda"}]}]}'
bad "a dev outside /dev" '{"libvirt_vm_vms": [{"name": "a", "disks": [{"dev": "/srv/sda", "target": "vda"}]}]}'
bad "a dev with a .. segment" '{"libvirt_vm_vms": [{"name": "a", "disks": [{"dev": "/dev/../etc/shadow", "target": "vda"}]}]}'
bad "a relative file" '{"libvirt_vm_vms": [{"name": "a", "disks": [{"file": "a.img", "target": "vda"}]}]}'
bad "a file with a quote" '{"libvirt_vm_vms": [{"name": "a", "disks": [{"file": "/srv/a'"'"'.img", "target": "vda"}]}]}'
bad "a file with a trailing newline" '{"libvirt_vm_vms": [{"name": "a", "disks": [{"file": "/srv/a.img\n", "target": "vda"}]}]}'
bad "a bad target" '{"libvirt_vm_vms": [{"name": "a", "disks": [{"dev": "/dev/sda", "target": "nvme0"}]}]}'
bad "a duplicate target" '{"libvirt_vm_vms": [{"name": "a", "disks": [{"dev": "/dev/sda", "target": "vda"}, {"dev": "/dev/sdb", "target": "vda"}]}]}'
bad "an unknown format" '{"libvirt_vm_vms": [{"name": "a", "disks": [{"dev": "/dev/sda", "target": "vda", "format": "vmdk"}]}]}'
bad "an unknown bus" '{"libvirt_vm_vms": [{"name": "a", "disks": [{"dev": "/dev/sda", "target": "vda", "bus": "ide"}]}]}'
bad "an unknown cache" '{"libvirt_vm_vms": [{"name": "a", "disks": [{"dev": "/dev/sda", "target": "vda", "cache": "fast"}]}]}'
bad "an unknown discard" '{"libvirt_vm_vms": [{"name": "a", "disks": [{"dev": "/dev/sda", "target": "vda", "discard": "on"}]}]}'
bad "an unknown disk key" '{"libvirt_vm_vms": [{"name": "a", "disks": [{"dev": "/dev/sda", "target": "vda", "serial": "x"}]}]}'
bad "a bad MAC" '{"libvirt_vm_vms": [{"name": "a", "interfaces": [{"bridge": "br0", "mac": "02:00:00:00:00"}]}]}'
bad "a MAC with a trailing newline" '{"libvirt_vm_vms": [{"name": "a", "interfaces": [{"bridge": "br0", "mac": "02:00:00:00:00:01\n"}]}]}'
bad "a multicast MAC" '{"libvirt_vm_vms": [{"name": "a", "interfaces": [{"bridge": "br0", "mac": "01:00:5e:00:00:01"}]}]}'
bad "a MAC used twice" '{"libvirt_vm_vms": [{"name": "a", "interfaces": [{"bridge": "br0", "mac": "02:00:00:00:00:01"}]}, {"name": "b", "interfaces": [{"bridge": "br0", "mac": "02:00:00:00:00:01"}]}]}'
bad "a MAC used twice, other case" '{"libvirt_vm_vms": [{"name": "a", "interfaces": [{"bridge": "br0", "mac": "02:00:00:00:00:0a"}, {"bridge": "br1", "mac": "02:00:00:00:00:0A"}]}]}'
bad "no MAC" '{"libvirt_vm_vms": [{"name": "a", "interfaces": [{"bridge": "br0"}]}]}'
bad "no bridge" '{"libvirt_vm_vms": [{"name": "a", "interfaces": [{"mac": "02:00:00:00:00:01"}]}]}'
bad "a bridge name too long" '{"libvirt_vm_vms": [{"name": "a", "interfaces": [{"bridge": "bridge-name-too-long", "mac": "02:00:00:00:00:01"}]}]}'
bad "a bridge with an embedded newline" '{"libvirt_vm_vms": [{"name": "a", "interfaces": [{"bridge": "br0\nx", "mac": "02:00:00:00:00:01"}]}]}'
bad "an unknown model" '{"libvirt_vm_vms": [{"name": "a", "interfaces": [{"bridge": "br0", "mac": "02:00:00:00:00:01", "model": "ne2k"}]}]}'
bad "an unknown interface key" '{"libvirt_vm_vms": [{"name": "a", "interfaces": [{"bridge": "br0", "mac": "02:00:00:00:00:01", "vlan": 20}]}]}'
bad "the XML directory under /etc/libvirt" '{"libvirt_vm_xml_dir": "/etc/libvirt/qemu"}'
bad "the XML directory under /var/lib/libvirt" '{"libvirt_vm_xml_dir": "/var/lib/libvirt/xml"}'
bad "the XML directory with a double slash into /etc/libvirt" '{"libvirt_vm_xml_dir": "//etc//libvirt"}'
bad "the XML directory with a .. segment" '{"libvirt_vm_xml_dir": "/etc/libvirt_vm/../libvirt"}'
bad "a relative XML directory" '{"libvirt_vm_xml_dir": "vms"}'
bad "an XML directory with a trailing newline" '{"libvirt_vm_xml_dir": "/etc/libvirt_vm\n"}'
bad "the NVRAM directory under /var/lib/libvirt" '{"libvirt_vm_nvram_dir": "/var/lib/libvirt/qemu/nvram"}'
bad "an OVMF path with a quote" '{"libvirt_vm_ovmf_code": "/usr/share/OVMF/a'"'"'b.fd"}'
bad "validate as a string" '{"libvirt_vm_validate": "yes"}'
bad "packages as a string" '{"libvirt_vm_packages": "libvirt-clients"}'
bad "a name in the defaults" '{"libvirt_vm_defaults": {"name": "x"}}'
bad "an unknown key in the defaults" '{"libvirt_vm_defaults": {"autostart": true}}'
bad "a bad value from the defaults" '{"libvirt_vm_defaults": {"firmware": "coreboot"}, "libvirt_vm_vms": [{"name": "a"}]}'

if [[ $fails -gt 0 ]]; then echo "$fails failed" >&2; exit 1; fi
echo "all passed"
