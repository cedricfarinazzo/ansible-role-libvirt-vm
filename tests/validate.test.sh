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
# A run with a graphics password or cloud-init is no_log: its failure is censored.
bad() {
  if run "$2"; then echo "FAIL accepted: $1" >&2; fails=$((fails + 1))
  elif grep -qE '"assertion"|Action failed: |"censored"' "$WORK/out"; then echo "ok   rejected: $1"
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
bad "an unknown VM key" "$(vm ', "autostrat": true')"
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
bad "an unknown key in the defaults" '{"libvirt_vm_defaults": {"autostrat": true}}'
bad "a bad value from the defaults" '{"libvirt_vm_defaults": {"firmware": "coreboot"}, "libvirt_vm_vms": [{"name": "a"}]}'

# Options added in 1.1.0: one good and the bad cases of each
nic() { echo "{\"libvirt_vm_vms\": [{\"name\": \"a\", \"interfaces\": [{\"mac\": \"02:00:00:00:00:01\"$1}]}]}"; }
disk() { echo "{\"libvirt_vm_vms\": [{\"name\": \"a\", \"disks\": [{\"target\": \"vda\"$1}]}]}"; }
hd() { echo "{\"libvirt_vm_vms\": [{\"name\": \"a\", \"hostdevs\": [{$1}]}]}"; }
gr() { echo "{\"libvirt_vm_vms\": [{\"name\": \"a\", \"graphics\": {$1}}]}"; }
ci() { echo "{\"libvirt_vm_vms\": [{\"name\": \"a\", \"cloud_init\": {$1}}]}"; }
SHA=sha256:$(printf '%064d' 0)
good "every 1.1.0 VM option" "$(vm ', "uuid": "4C4C4544-0000-1000-8000-000000000001", "arch": "aarch64", "machine": "virt", "emulator": "/usr/bin/qemu-system-aarch64", "clock_offset": "localtime", "boot": ["network", "cdrom", "hd"], "bootmenu": true, "bios_useserial": true, "video": "qxl", "rng": true, "console_log": "/var/log/libvirt_vm/web.log", "console_log_append": true, "xml_template": "templates/my-domain.xml.j2"')"
good "a deterministic UUID" "$(vm ', "uuid_deterministic": true')"
good "define, autostart and start without Pacemaker" "{\"libvirt_vm_pacemaker\": false, \"libvirt_vm_vms\": [{$VM, \"define\": true, \"autostart\": true, \"start\": true}]}"
good "define only without Pacemaker" "{\"libvirt_vm_pacemaker\": false, \"libvirt_vm_vms\": [{$VM, \"define\": true}]}"
good "another libvirt URI" '{"libvirt_vm_uri": "qemu+ssh://root@host.example/system"}'
good "a network interface, driver and alias" "$(nic ', "type": "network", "network": "default", "model": "e1000", "driver": {"name": "vhost", "queues": 4}, "alias": "lan0", "name": "tap-a0", "trust_guest_rx_filters": true')"
good "a direct interface, mode bridge" "$(nic ', "type": "direct", "dev": "eth0", "mode": "bridge"')"
good "a driver with queues only" "$(nic ', "bridge": "br0", "driver": {"queues": 2}')"
good "a cdrom, read-only, io" "$(disk ', "file": "/srv/iso/install.iso", "device": "cdrom", "bus": "sata", "readonly": true, "io": "threads"')"
good "a new disk of a size" "$(disk ', "file": "/srv/a.qcow2", "format": "qcow2", "size": "20G", "io": "io_uring"')"
good "a disk backed by a local image, checksum" "$(disk ', "file": "/srv/a.qcow2", "format": "qcow2", "size": "20G", "backing_file": "/srv/base.qcow2", "backing_format": "raw", "checksum": "'"$SHA"'"')"
good "a disk backed by a URL" "$(disk ', "file": "/srv/a.qcow2", "format": "qcow2", "size": "20G", "backing_file": "https://cloud.example.com/images/base.qcow2", "checksum": "'"$SHA"'"')"
good "a disk copied from a URL" "$(disk ', "file": "/srv/a.raw", "image": "http://cloud.example.com/base.raw", "checksum": "sha512:'"$(printf '%0128d' 0)"'"')"
good "a PCI hostdev, every key" "$(hd '"type": "pci", "source": "0000:3B:00.1", "destination": "0000:00:10.0", "alias": "gpu0", "managed": false')"
good "a USB hostdev" "$(hd '"type": "usb", "vendor": "0x1050", "product": "0x0407"')"
good "spice graphics, port, password" "$(gr '"type": "spice", "listen": "0.0.0.0", "port": 5901, "password": "s3cr#t"')"
good "no graphics" "$(gr '"type": "none"')"
good "graphics from the defaults" '{"libvirt_vm_defaults": {"graphics": {"type": "vnc", "password": "s3cr#t"}}, "libvirt_vm_vms": [{"name": "a"}]}'
gl() { echo "{\"libvirt_vm_vms\": [{\"name\": \"a\", \"graphics\": [$1]}]}"; }
good "a graphics list, VNC and SPICE" "$(gl '{"type": "vnc", "listen": "127.0.0.1"}, {"type": "spice", "listen": "127.0.0.1"}')"
good "a graphics list, a password, fixed ports" "$(gl '{"port": 5901}, {"type": "spice", "port": 5902, "password": "s3cr#t"}')"
good "a graphics list of one none" "$(gl '{"type": "none"}')"
good "a graphics list from the defaults" '{"libvirt_vm_defaults": {"graphics": [{"type": "vnc"}, {"type": "spice"}]}, "libvirt_vm_vms": [{"name": "a"}]}'
good "cloud-init, every file, own ISO" "$(ci '"enabled": true, "files": {"user-data": "#cloud-config\n", "meta-data": "instance-id: a\n", "network-config": "version: 2\n", "vendor-data": ""}, "iso": "/srv/seed/a.iso", "target": "sdy"')"
good "cloud-init disabled, no files" "$(ci '"enabled": false')"
bad "a bad UUID" "$(vm ', "uuid": "not-a-uuid"')"
bad "a UUID with a trailing newline" "$(vm ', "uuid": "4c4c4544-0000-1000-8000-000000000001\n"')"
bad "uuid_deterministic as a string" "$(vm ', "uuid_deterministic": "yes"')"
bad "an unknown arch" "$(vm ', "arch": "riscv64"')"
bad "a relative emulator" "$(vm ', "emulator": "qemu-system-x86_64"')"
bad "an emulator with an embedded newline" "$(vm ', "emulator": "/usr/bin/qemu\nx"')"
bad "an unknown clock offset" "$(vm ', "clock_offset": "timezone"')"
bad "boot as a string" "$(vm ', "boot": "hd"')"
bad "an empty boot list" "$(vm ', "boot": []')"
bad "an unknown boot device" "$(vm ', "boot": ["fd"]')"
bad "a boot device twice" "$(vm ', "boot": ["hd", "hd"]')"
bad "bootmenu as a string" "$(vm ', "bootmenu": "yes"')"
bad "bios_useserial as a number" "$(vm ', "bios_useserial": 1')"
bad "an unknown video" "$(vm ', "video": "cirrus"')"
bad "rng as a string" "$(vm ', "rng": "on"')"
bad "a relative console log" "$(vm ', "console_log": "web.log"')"
bad "a console log with a trailing newline" "$(vm ', "console_log": "/var/log/web.log\n"')"
bad "hostdevs as a mapping" "$(vm ', "hostdevs": {"type": "usb"}')"
bad "an xml_template that is no .j2" "$(vm ', "xml_template": "my.xml"')"
bad "an xml_template with a .. segment" "$(vm ', "xml_template": "../x.j2"')"
bad "an xml_template with a trailing newline" "$(vm ', "xml_template": "x.j2\n"')"
bad "autostart under Pacemaker" "$(vm ', "define": true, "autostart": true')"
bad "define under Pacemaker" "$(vm ', "define": true')"
bad "start under Pacemaker" "$(vm ', "define": true, "start": true')"
bad "autostart without define" "{\"libvirt_vm_pacemaker\": false, \"libvirt_vm_vms\": [{$VM, \"autostart\": true}]}"
bad "start without define" "{\"libvirt_vm_pacemaker\": false, \"libvirt_vm_vms\": [{$VM, \"start\": true}]}"
bad "define as a string" "{\"libvirt_vm_pacemaker\": false, \"libvirt_vm_vms\": [{$VM, \"define\": \"yes\"}]}"
bad "pacemaker as a string" '{"libvirt_vm_pacemaker": "no"}'
bad "a URI with a trailing newline" '{"libvirt_vm_uri": "qemu:///system\n"}'
bad "a URI of another hypervisor" '{"libvirt_vm_uri": "xen:///system"}'
bad "an image cache under /var/lib/libvirt" '{"libvirt_vm_image_cache_dir": "/var/lib/libvirt/images"}'
bad "a cloud-init dir with an embedded newline" '{"libvirt_vm_cloud_init_dir": "/srv/ci\nx"}'
bad "disk packages as a string" '{"libvirt_vm_disk_packages": "qemu-utils"}'
bad "cloud-init packages as a mapping" '{"libvirt_vm_cloud_init_packages": {"a": 1}}'
bad "an unknown interface type" "$(nic ', "type": "user"')"
bad "a network interface with a bridge" "$(nic ', "type": "network", "network": "default", "bridge": "br0"')"
bad "a network interface without its network" "$(nic ', "type": "network"')"
bad "a direct interface without dev" "$(nic ', "type": "direct"')"
bad "a network name with a trailing newline" "$(nic ', "type": "network", "network": "default\n"')"
bad "a direct dev with an embedded newline" "$(nic ', "type": "direct", "dev": "eth0\nx"')"
bad "an unknown direct mode" "$(nic ', "type": "direct", "dev": "eth0", "mode": "vlan"')"
bad "a driver as a string" "$(nic ', "bridge": "br0", "driver": "vhost"')"
bad "an empty driver" "$(nic ', "bridge": "br0", "driver": {}')"
bad "an unknown driver name" "$(nic ', "bridge": "br0", "driver": {"name": "vfio"}')"
bad "zero queues" "$(nic ', "bridge": "br0", "driver": {"queues": 0}')"
bad "queues as a string" "$(nic ', "bridge": "br0", "driver": {"queues": "4"}')"
bad "an unknown driver key" "$(nic ', "bridge": "br0", "driver": {"txmode": "iothread"}')"
bad "an alias with a space" "$(nic ', "bridge": "br0", "alias": "lan 0"')"
bad "an alias with a trailing newline" "$(nic ', "bridge": "br0", "alias": "lan0\n"')"
bad "a target name libvirt reserves" "$(nic ', "bridge": "br0", "name": "vnet0"')"
bad "a target name with an embedded newline" "$(nic ', "bridge": "br0", "name": "tap\nx"')"
bad "trust_guest_rx_filters as a string" "$(nic ', "bridge": "br0", "trust_guest_rx_filters": "yes"')"
bad "an unknown device" "$(disk ', "file": "/srv/a.img", "device": "floppy"')"
bad "readonly as a string" "$(disk ', "file": "/srv/a.img", "readonly": "yes"')"
bad "an unknown io" "$(disk ', "file": "/srv/a.img", "io": "aio"')"
bad "a size on a block disk" "$(disk ', "dev": "/dev/sda", "size": "20G"')"
bad "a size on a cdrom" "$(disk ', "file": "/srv/a.iso", "device": "cdrom", "size": "1G"')"
bad "a size with a unit of its own" "$(disk ', "file": "/srv/a.img", "size": "20GB"')"
bad "a size with a trailing newline" "$(disk ', "file": "/srv/a.img", "size": "20G\n"')"
bad "a backing file without a size" "$(disk ', "file": "/srv/a.qcow2", "format": "qcow2", "backing_file": "/srv/base.qcow2"')"
bad "a backing file on a raw disk" "$(disk ', "file": "/srv/a.img", "size": "1G", "backing_file": "/srv/base.qcow2"')"
bad "a backing file and an image" "$(disk ', "file": "/srv/a.qcow2", "format": "qcow2", "size": "1G", "backing_file": "/srv/b.qcow2", "image": "/srv/c.qcow2"')"
bad "a relative backing file" "$(disk ', "file": "/srv/a.qcow2", "format": "qcow2", "size": "1G", "backing_file": "base.qcow2"')"
bad "a backing URL without a checksum" "$(disk ', "file": "/srv/a.qcow2", "format": "qcow2", "size": "1G", "backing_file": "https://cloud.example.com/base.qcow2"')"
bad "a backing URL with a quote" "$(disk ', "file": "/srv/a.qcow2", "format": "qcow2", "size": "1G", "backing_file": "https://cloud.example.com/b'"'"'.qcow2", "checksum": "'"$SHA"'"')"
bad "a backing URL with a trailing newline" "$(disk ', "file": "/srv/a.qcow2", "format": "qcow2", "size": "1G", "backing_file": "https://cloud.example.com/b.qcow2\n", "checksum": "'"$SHA"'"')"
bad "an ftp image" "$(disk ', "file": "/srv/a.img", "image": "ftp://cloud.example.com/b.img", "checksum": "'"$SHA"'"')"
bad "a checksum of an unknown algorithm" "$(disk ', "file": "/srv/a.img", "image": "/srv/b.img", "checksum": "md5:0123456789abcdef0123456789abcdef"')"
bad "a checksum with a trailing newline" "$(disk ', "file": "/srv/a.img", "image": "/srv/b.img", "checksum": "'"$SHA"'\n"')"
bad "a checksum with no image" "$(disk ', "file": "/srv/a.img", "checksum": "'"$SHA"'"')"
bad "a backing format with no backing file" "$(disk ', "file": "/srv/a.img", "backing_format": "raw"')"
bad "an unknown backing format" "$(disk ', "file": "/srv/a.qcow2", "format": "qcow2", "size": "1G", "backing_file": "/srv/b.img", "backing_format": "vmdk"')"
bad "a hostdev with no type" "$(hd '"source": "0000:01:00.0"')"
bad "an unknown hostdev type" "$(hd '"type": "scsi", "source": "0000:01:00.0"')"
bad "a PCI hostdev without source" "$(hd '"type": "pci"')"
bad "a PCI hostdev with a vendor" "$(hd '"type": "pci", "source": "0000:01:00.0", "vendor": "0x8086"')"
bad "a PCI source without domain" "$(hd '"type": "pci", "source": "01:00.0"')"
bad "a PCI source with a trailing newline" "$(hd '"type": "pci", "source": "0000:01:00.0\n"')"
bad "a PCI function above 7" "$(hd '"type": "pci", "source": "0000:01:00.8"')"
bad "a USB hostdev without product" "$(hd '"type": "usb", "vendor": "0x1050"')"
bad "a USB hostdev with a source" "$(hd '"type": "usb", "vendor": "0x1050", "product": "0x0407", "source": "0000:01:00.0"')"
bad "a USB vendor without 0x" "$(hd '"type": "usb", "vendor": "1050", "product": "0x0407"')"
bad "a USB product with an embedded newline" "$(hd '"type": "usb", "vendor": "0x1050", "product": "0x04\n07"')"
bad "a bad destination" "$(hd '"type": "pci", "source": "0000:01:00.0", "destination": "slot 10"')"
bad "a hostdev alias with a slash" "$(hd '"type": "pci", "source": "0000:01:00.0", "alias": "gpu/0"')"
bad "managed as a string" "$(hd '"type": "pci", "source": "0000:01:00.0", "managed": "yes"')"
bad "an unknown hostdev key" "$(hd '"type": "pci", "source": "0000:01:00.0", "rom": "off"')"
bad "a PCI device given twice" '{"libvirt_vm_vms": [{"name": "a", "hostdevs": [{"type": "pci", "source": "0000:01:00.0"}]}, {"name": "b", "hostdevs": [{"type": "pci", "source": "0000:01:00.0"}]}]}'
bad "graphics as a string" "{\"libvirt_vm_vms\": [{\"name\": \"a\", \"graphics\": \"vnc\"}]}"
bad "an unknown graphics type" "$(gr '"type": "rdp"')"
bad "a graphics listen that is no address" "$(gr '"listen": "localhost"')"
bad "a graphics port below 5900" "$(gr '"port": 22')"
bad "a graphics port as a string" "$(gr '"port": "5901"')"
bad "a password with a quote" "$(gr '"password": "a'"'"'b"')"
bad "a password with a trailing newline" "$(gr '"password": "secret\n"')"
bad "a password with an embedded newline" "$(gr '"password": "sec\nret"')"
bad "a password too long" "$(gr '"password": "'"$(printf 'a%.0s' {1..65})"'"')"
bad "an unknown graphics key" "$(gr '"keymap": "fr"')"
bad "a graphics type from the defaults that is unknown" '{"libvirt_vm_defaults": {"graphics": {"type": "rdp"}}, "libvirt_vm_vms": [{"name": "a"}]}'
bad "a graphics password from the defaults with a quote" '{"libvirt_vm_defaults": {"graphics": {"type": "vnc", "password": "a'"'"'b"}}, "libvirt_vm_vms": [{"name": "a"}]}'
bad "a graphics password from the defaults with a trailing newline" '{"libvirt_vm_defaults": {"graphics": {"type": "vnc", "password": "pw\n"}}, "libvirt_vm_vms": [{"name": "a"}]}'
bad "an empty graphics list" "$(gl '')"
bad "a graphics list holding a string" "$(gl '"vnc"')"
bad "a graphics list with a type twice" "$(gl '{"type": "spice"}, {"type": "spice", "listen": "::1"}')"
bad "a graphics list with two default VNC" "$(gl '{"listen": "127.0.0.1"}, {"listen": "::1"}')"
bad "a graphics list with none and VNC" "$(gl '{"type": "none"}, {"type": "vnc"}')"
bad "a graphics list with a fixed port twice" "$(gl '{"port": 5901}, {"type": "spice", "port": 5901}')"
bad "a graphics list entry with an unknown key" "$(gl '{"type": "vnc"}, {"type": "spice", "keymap": "fr"}')"
bad "a graphics list entry with an unknown type" "$(gl '{"type": "vnc"}, {"type": "rdp"}')"
bad "a graphics list listen with a trailing newline" "$(gl '{"type": "vnc"}, {"type": "spice", "listen": "127.0.0.1\n"}')"
bad "a graphics list listen with an embedded newline" "$(gl '{"type": "vnc", "listen": "127.0.0.1\n::1"}')"
bad "a graphics list password with a trailing newline" "$(gl '{"type": "vnc"}, {"type": "spice", "password": "pw\n"}')"
bad "a graphics list password with a carriage return" "$(gl '{"type": "spice", "password": "p\rw"}')"
bad "a graphics list from the defaults with a type twice" '{"libvirt_vm_defaults": {"graphics": [{"type": "vnc"}, {"type": "vnc"}]}, "libvirt_vm_vms": [{"name": "a"}]}'
bad "cloud-init as a boolean" "{\"libvirt_vm_vms\": [{\"name\": \"a\", \"cloud_init\": true}]}"
bad "cloud-init with no enabled" "$(ci '"files": {"user-data": "x"}')"
bad "cloud-init enabled as a string" "$(ci '"enabled": "yes", "files": {"user-data": "x"}')"
bad "cloud-init enabled without user-data" "$(ci '"enabled": true, "files": {"meta-data": "x"}')"
bad "an unknown cloud-init file" "$(ci '"enabled": true, "files": {"user-data": "x", "cloud.cfg": "y"}')"
bad "a cloud-init file that is no string" "$(ci '"enabled": true, "files": {"user-data": {"a": 1}}')"
bad "a seed ISO under /var/lib/libvirt" "$(ci '"enabled": true, "files": {"user-data": "x"}, "iso": "/var/lib/libvirt/images/a.iso"')"
bad "a seed ISO with a trailing newline" "$(ci '"enabled": true, "files": {"user-data": "x"}, "iso": "/srv/a.iso\n"')"
bad "a seed target with an embedded newline" "$(ci '"enabled": true, "files": {"user-data": "x"}, "target": "sd\nz"')"
bad "a seed target used by a disk" '{"libvirt_vm_vms": [{"name": "a", "disks": [{"file": "/srv/a.img", "target": "sdz"}], "cloud_init": {"enabled": true, "files": {"user-data": "x"}}}]}'
bad "an unknown cloud-init key" "$(ci '"enabled": false, "seed": "x"')"

# IOThreads and the balloon
good "iothreads and the balloon options" "$(vm ", \"iothreads\": 2, \"balloon_free_page_reporting\": true, \"balloon_autodeflate\": true")"
good "iothreads from the defaults" "{\"libvirt_vm_defaults\": {\"iothreads\": 1, \"balloon_free_page_reporting\": true}, \"libvirt_vm_vms\": [{$VM}]}"
good "a disk on iothread 2" "{\"libvirt_vm_vms\": [{\"name\": \"a\", \"iothreads\": 2, \"disks\": [{\"dev\": \"/dev/vg0/a\", \"target\": \"vda\", \"iothread\": 2}]}]}"
bad "iothreads as a string" "$(vm ", \"iothreads\": \"1\"")"
bad "iothreads as a boolean" "$(vm ", \"iothreads\": true")"
bad "negative iothreads" "$(vm ", \"iothreads\": -1")"
bad "too many iothreads" "$(vm ", \"iothreads\": 65")"
bad "free page reporting as a string" "$(vm ", \"balloon_free_page_reporting\": \"on\"")"
bad "autodeflate as a number" "$(vm ", \"balloon_autodeflate\": 1")"
bad "a disk iothread the VM lacks" "{\"libvirt_vm_vms\": [{\"name\": \"a\", \"iothreads\": 1, \"disks\": [{\"dev\": \"/dev/vg0/a\", \"target\": \"vda\", \"iothread\": 2}]}]}"
bad "a disk iothread without iothreads" "{\"libvirt_vm_vms\": [{\"name\": \"a\", \"disks\": [{\"dev\": \"/dev/vg0/a\", \"target\": \"vda\", \"iothread\": 1}]}]}"
bad "a disk iothread of zero" "{\"libvirt_vm_vms\": [{\"name\": \"a\", \"iothreads\": 1, \"disks\": [{\"dev\": \"/dev/vg0/a\", \"target\": \"vda\", \"iothread\": 0}]}]}"
bad "a disk iothread as a string" "{\"libvirt_vm_vms\": [{\"name\": \"a\", \"iothreads\": 1, \"disks\": [{\"dev\": \"/dev/vg0/a\", \"target\": \"vda\", \"iothread\": \"1\"}]}]}"
bad "a disk iothread on a SATA disk" "{\"libvirt_vm_vms\": [{\"name\": \"a\", \"iothreads\": 1, \"disks\": [{\"dev\": \"/dev/vg0/a\", \"target\": \"sda\", \"bus\": \"sata\", \"iothread\": 1}]}]}"

if [[ $fails -gt 0 ]]; then echo "$fails failed" >&2; exit 1; fi
echo "all passed"
