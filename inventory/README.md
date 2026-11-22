# Inventory

Source of truth for addressing, replacing the "Home Network VLANs & Addresses" spreadsheet.

- [`sites.yaml`](sites.yaml): sites (house, apartment, and the two free blocks), their VLANs, subnets, DHCP ranges, IPv6 prefixes, cluster pod ranges, LoadBalancer pools and firewall rules.
- [`hosts.yaml`](hosts.yaml): hosts in Ansible's YAML inventory format. Every host has `site` and `vlan` (keys into `sites.yaml`), and where known `address`, `subnet` and `dns_name`. Hosts in the `unmanaged` group need DNS but don't run Ansible plays; plays targeting `all` exclude it.
- [`schema/`](schema): JSON Schemas for both files.
- [`check.py`](check.py): the validator. Beyond the schemas it enforces that each address is inside its VLAN's CIDR and its subnet, that subnets sit inside their VLAN and don't overlap, that every site block lies inside the `supernet`, that each reserved LoadBalancer address (and its `moves_to`) is inside its pool, and that addresses, `moves_to` destinations and DNS names are unique.

```sh
task inventory:check
```

CI runs the same check on every PR that touches `inventory/`. Warnings (a router outside its VLAN, which is a known TODO) don't fail it.

`group_vars/` is committed. The SSH user is `rtrox` on every host (`all.yaml`).

`TODO` comments mark values the sheet got wrong or didn't have; they are open questions, not decisions.
