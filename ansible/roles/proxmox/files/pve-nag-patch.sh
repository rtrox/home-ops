#!/bin/sh
# Managed by Ansible (roles/proxmox). Disables the "No valid subscription"
# popup in the web UI. Re-run after every proxmox-widget-toolkit upgrade by
# /etc/apt/apt.conf.d/99-pve-nag-patch. Safe to run repeatedly.
set -eu
f=/usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js
[ -f "$f" ] || exit 0
grep -q "void({ //Ext.Msg.show" "$f" && exit 0
sed -Ezi "s/(Ext\.Msg\.show\(\{\s+title: gettext\('No valid sub)/void({ \/\/\1/g" "$f"
systemctl restart pveproxy.service
