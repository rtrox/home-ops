# /// script
# requires-python = ">=3.11"
# dependencies = ["pyyaml==6.0.2", "jsonschema==4.23.0"]
# ///
"""Validate inventory/sites.yaml and inventory/hosts.yaml.

Run with `task inventory:check`. Checks the JSON Schemas in schema/, then the
sheet's own rules: each address inside its VLAN's CIDR and its subnet, no
duplicate addresses or names (reserved LoadBalancer addresses and moves_to
destinations included), every site block inside the supernet, every host has a site and a vlan that exist.
Exits non-zero on any error. Warnings (e.g. a router outside its VLAN) don't fail.
"""

from __future__ import annotations

import ipaddress as ip
import json
import sys
from pathlib import Path

import yaml
from jsonschema import Draft202012Validator

HERE = Path(__file__).resolve().parent
errors: list[str] = []
# (address, owner, moves_to address or None) for every reserved LoadBalancer address,
# filled by check_sites and claimed alongside the hosts' addresses.
reserved_claims: list[tuple[ip.IPv4Address, str, ip.IPv4Address | None]] = []
warnings: list[str] = []


def err(msg: str) -> None:
    errors.append(msg)


def load(name: str):
    return yaml.safe_load((HERE / name).read_text())


def validate_schema(doc, schema_name: str, label: str) -> bool:
    schema = json.loads((HERE / "schema" / schema_name).read_text())
    found = sorted(Draft202012Validator(schema).iter_errors(doc), key=lambda e: list(e.absolute_path))
    for e in found:
        path = "/".join(str(p) for p in e.absolute_path) or "<root>"
        err(f"{label}: {path}: {e.message}")
    return not found


def net(value: str, where: str):
    try:
        return ip.ip_network(value, strict=True)
    except ValueError as e:
        err(f"{where}: bad CIDR {value!r}: {e}")
        return None


def addr(value: str, where: str):
    try:
        return ip.ip_address(value)
    except ValueError as e:
        err(f"{where}: bad address {value!r}: {e}")
        return None


def overlapping(items: list[tuple[str, ip.IPv4Network]], what: str) -> None:
    for i, (na, a) in enumerate(items):
        for nb, b in items[i + 1 :]:
            if a.overlaps(b):
                err(f"{what}: {na} ({a}) overlaps {nb} ({b})")


def check_sites(sites: dict, supernet_cidr: str) -> dict:
    """Returns {site: {vlan: (network, {subnet: network})}} for the host checks."""
    parsed: dict = {}
    blocks = []
    supernet = net(supernet_cidr, "supernet")
    for sname, site in sites.items():
        block = net(site["block"], f"sites.{sname}.block")
        if block:
            blocks.append((sname, block))
            if supernet and not block.subnet_of(supernet):
                err(f"sites.{sname}.block: {block} is outside the supernet {supernet}")
        he = site.get("ipv6", {}).get("he_prefix")
        he_net = net(he, f"sites.{sname}.ipv6.he_prefix") if he else None
        parsed[sname] = {}
        vlan_nets, ids = [], {}
        for vname, vlan in site.get("vlans", {}).items():
            where = f"sites.{sname}.vlans.{vname}"
            vnet = net(vlan["cidr"], f"{where}.cidr")
            if not vnet:
                continue
            if block and not vnet.subnet_of(block):
                err(f"{where}: {vnet} is outside the site block {block}")
            if vlan["id"] in ids:
                err(f"{where}: VLAN id {vlan['id']} already used by {ids[vlan['id']]}")
            ids[vlan["id"]] = vname
            vlan_nets.append((vname, vnet))
            if "router" in vlan:
                r = addr(vlan["router"], f"{where}.router")
                if r and r not in vnet:
                    warnings.append(f"{where}.router: {r} is outside {vnet} (see the TODO in sites.yaml)")
            if "dhcp" in vlan:
                s = addr(vlan["dhcp"]["start"], f"{where}.dhcp.start")
                e = addr(vlan["dhcp"]["end"], f"{where}.dhcp.end")
                for label, a in (("start", s), ("end", e)):
                    if a and a not in vnet:
                        err(f"{where}.dhcp.{label}: {a} is outside {vnet}")
                if s and e and s > e:
                    err(f"{where}.dhcp: start {s} is after end {e}")
            if "ipv6" in vlan:
                v6 = net(vlan["ipv6"], f"{where}.ipv6")
                if v6 and he_net and not v6.subnet_of(he_net):
                    err(f"{where}.ipv6: {v6} is outside {he_net}")
            subnets = []
            for subname, sub in vlan.get("subnets", {}).items():
                snet = net(sub["cidr"], f"{where}.subnets.{subname}.cidr")
                if not snet:
                    continue
                if not snet.subnet_of(vnet):
                    err(f"{where}.subnets.{subname}: {snet} is outside the VLAN {vnet}")
                subnets.append((subname, snet))
            overlapping(subnets, f"{where}.subnets")
            parsed[sname][vname] = (vnet, dict(subnets))
        overlapping(vlan_nets, f"sites.{sname}.vlans")
        for vname in site.get("firewall", {}):
            if vname not in site.get("vlans", {}):
                err(f"sites.{sname}.firewall.{vname}: no such VLAN")
        pods = []
        for cname, c in site.get("clusters", {}).items():
            n = net(c["pod_cidr"], f"sites.{sname}.clusters.{cname}.pod_cidr")
            if n:
                pods.append((f"{sname}/{cname}", n))
        parsed.setdefault("_pods", []).extend(pods)
        for pname, pool in site.get("loadbalancer_pools", {}).items():
            where = f"sites.{sname}.loadbalancer_pools.{pname}"
            p = net(pool["cidr"], f"{where}.cidr")
            m = net(pool["moves_to"], f"{where}.moves_to") if "moves_to" in pool else None
            if m and p and m.overlaps(p):
                err(f"{where}: moves_to {m} overlaps the current pool {p}")
            for rname, r in pool.get("reserved", {}).items():
                rl = f"{where}.reserved.{rname}"
                ra = addr(r["address"], f"{rl}.address")
                if ra and p and ra not in p:
                    err(f"{rl}: {ra} is outside the pool {p}")
                rm = None
                if "moves_to" in r:
                    rm = addr(r["moves_to"], f"{rl}.moves_to")
                    if rm and not m:
                        err(f"{rl}: moves_to is set but the pool has no moves_to")
                    elif rm and m and rm not in m:
                        err(f"{rl}: moves_to {rm} is outside the pool's moves_to {m}")
                    elif rm and ra and int(rm) - int(m.network_address) != int(ra) - int(p.network_address):
                        err(f"{rl}: moves_to {rm} does not keep the host number of {ra}")
                if ra:
                    reserved_claims.append((ra, f"{sname}/{pname}/{rname}", rm))
    overlapping(blocks, "site blocks")
    overlapping(parsed.pop("_pods", []), "cluster pod CIDRs")
    return parsed


def flatten_hosts(doc: dict) -> dict:
    hosts: dict = {}
    groups = doc["all"]["children"]
    for gname, group in groups.items():
        for child in (group.get("children") or {}):
            if child not in groups:
                err(f"hosts: group {gname} lists unknown child group {child!r}")
    for gname, group in groups.items():
        for hname, h in (group.get("hosts") or {}).items():
            if hname in hosts:
                err(f"hosts: {hname} is defined in more than one group ({hosts[hname][0]}, {gname})")
            hosts[hname] = (gname, h or {})
    return hosts


def check_hosts(hosts: dict, parsed: dict) -> None:
    seen_addr: dict[ip.IPv4Address, str] = {}
    seen_dns: dict[str, str] = {}
    moves: list[tuple[ip.IPv4Address, str]] = []

    def where_is(site, vlan, label):
        if site not in parsed:
            err(f"{label}: unknown site {site!r}")
            return None
        if vlan not in parsed[site]:
            err(f"{label}: site {site!r} has no VLAN {vlan!r}")
            return None
        return parsed[site][vlan]

    def claim(a: ip.IPv4Address, owner: str) -> None:
        if a in seen_addr:
            err(f"duplicate address {a}: {seen_addr[a]} and {owner}")
        seen_addr[a] = owner

    for hname, (gname, h) in sorted(hosts.items()):
        label = f"hosts.{hname}"
        found = where_is(h.get("site"), h.get("vlan"), label)
        dns = h.get("dns_name")
        if dns:
            if dns in seen_dns:
                err(f"duplicate DNS name {dns}: {seen_dns[dns]} and {hname}")
            seen_dns[dns] = hname
        if "address" in h and "ansible_host" in h and h["address"] != h["ansible_host"]:
            err(f"{label}: ansible_host {h['ansible_host']} differs from address {h['address']}")
        if "address" in h:
            a = addr(h["address"], f"{label}.address")
            if a and found:
                vnet, subnets = found
                if a not in vnet:
                    err(f"{label}: {a} is outside VLAN {h['vlan']} ({vnet})")
                if "subnet" in h:
                    if h["subnet"] not in subnets:
                        err(f"{label}: VLAN {h['vlan']} has no subnet {h['subnet']!r}")
                    elif a not in subnets[h["subnet"]]:
                        err(f"{label}: {a} is outside subnet {h['subnet']} ({subnets[h['subnet']]})")
            if a:
                claim(a, hname)
        elif "subnet" in h:
            err(f"{label}: subnet is set but address is not")
        for i, extra in enumerate(h.get("extra_addresses", [])):
            xl = f"{label}.extra_addresses[{i}]"
            x = where_is(h["site"], extra["vlan"], xl)
            a = addr(extra["address"], xl)
            if a and x and a not in x[0]:
                err(f"{xl}: {a} is outside VLAN {extra['vlan']} ({x[0]})")
            if a:
                claim(a, f"{hname} ({extra['vlan']})")
        if "moves_to" in h:
            m = h["moves_to"]
            ml = f"{label}.moves_to"
            x = where_is(m["site"], m["vlan"], ml)
            a = addr(m["address"], ml)
            if a and x and a not in x[0]:
                err(f"{ml}: {a} is outside VLAN {m['vlan']} ({x[0]})")
            if a:
                moves.append((a, hname))

    # Reserved LoadBalancer addresses share the address space with the hosts.
    for ra, owner, rm in reserved_claims:
        claim(ra, owner)
        if rm:
            moves.append((rm, owner))
    # Destination addresses aren't claimed (they're free until the move), but
    # they must not collide with each other or with any current address.
    seen_moves: dict[ip.IPv4Address, str] = {}
    for a, owner in moves:
        if a in seen_moves:
            err(f"duplicate moves_to address {a}: {seen_moves[a]} and {owner}")
        seen_moves[a] = owner
        if a in seen_addr:
            err(f"{owner}.moves_to: {a} is already used by {seen_addr[a]}")


def main() -> int:
    sites_doc, hosts_doc = load("sites.yaml"), load("hosts.yaml")
    ok = validate_schema(sites_doc, "sites.schema.json", "sites.yaml")
    ok = validate_schema(hosts_doc, "hosts.schema.json", "hosts.yaml") and ok
    if ok:
        parsed = check_sites(sites_doc["sites"], sites_doc["supernet"])
        check_hosts(flatten_hosts(hosts_doc), parsed)
    for w in warnings:
        print(f"warning: {w}")
    for e in errors:
        print(f"error: {e}")
    if errors:
        print(f"inventory check failed: {len(errors)} error(s)")
        return 1
    print("inventory check passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
