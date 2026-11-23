# Reads terraform-record cloudflare's state (`tofu state pull`, on stdin) and
# prints the locals block for imports.tf: Cloudflare object IDs only, keyed by
# this stack's addresses. Nothing else from the state is printed. Fails if any
# object this stack imports is missing or appears twice. MIGRATION.md step 1.
# Delete with imports.tf in the cleanup PR.

# terraform-record module -> zone.
def zones: {
  "module.cf_domain_lyb_app": "lyb.app",
  "module.cf_domain_missprissquilts_com": "missprissquilts.com",
  "module.cf_domain_rtrox_co": "rtrox.co",
  "module.cf_domain_rtrox_com": "rtrox.com",
  "module.cf_domain_rtrox_dev": "rtrox.dev",
  "module.cf_domain_rtrox_io": "rtrox.io",
  "module.cf_domain_troxel_io": "troxel.io",
  "module.cf_domain_trxl_ink": "trxl.ink",
  "module.cf_domain_trxl_io": "trxl.io",
  "module.cf_domain_trxl_tech": "trxl.tech"
};

# Zone -> terraform-record's for_each key -> this stack's key (records.tf).
# Records not listed (rtrox.io's host records) stay in terraform-record.
def records: {
  "rtrox.com": {
    "null_mx": "null_mx",
    "spf_none": "spf_none",
    "dmarc_reject": "dmarc_reject"
  },
  "rtrox.dev": {
    "rtrox_dev_simplelogin": "simplelogin_verification",
    "simplelogin_mx_10": "simplelogin_mx_10",
    "simplelogin_mx_20": "simplelogin_mx_20",
    "simplelogin_spf": "simplelogin_spf",
    "simplelogin_dkim": "simplelogin_dkim",
    "simplelogin_dkim_2": "simplelogin_dkim_2",
    "simplelogin_dkim_3": "simplelogin_dkim_3",
    "simplelogin_dmarc": "simplelogin_dmarc"
  },
  "rtrox.io": {
    "_atproto.rtrox.io_0": "bluesky_atproto",
    "_atproto.asdf2.rtrox.io_0": "bluesky_atproto_asdf2",
    "rtrox.io_0": "protonmail_verification",
    "protonmail_mx_10": "protonmail_mx_10",
    "protonmail_mx_20": "protonmail_mx_20",
    "protonmail_spf": "protonmail_spf",
    "protonmail_dkim": "protonmail_dkim",
    "protonmail_dkim_2": "protonmail_dkim_2",
    "protonmail_dkim_3": "protonmail_dkim_3",
    "protonmail_dmarc": "protonmail_dmarc",
    "resend_mx": "resend_mx",
    "resend_spf": "resend_spf",
    "resend_dkim": "resend_dkim"
  },
  "troxel.io": {
    "em9286.troxel.io_0": "sendgrid_link",
    "s1._domainkey.troxel.io_0": "sendgrid_dkim_s1",
    "s2._domainkey.troxel.io_0": "sendgrid_dkim_s2",
    "proton_mx_1": "proton_mx_1",
    "proton_mx_2": "proton_mx_2",
    "google_verification": "google_verification",
    "protonmail_verification": "protonmail_verification",
    "google_dkim": "google_dkim",
    "protonmail_spf": "protonmail_spf",
    "protonmail_dkim": "protonmail_dkim",
    "protonmail_dkim2": "protonmail_dkim2",
    "protonmail_dkim3": "protonmail_dkim3",
    "protonmail_dmarc": "protonmail_dmarc"
  },
  "trxl.io": {
    "url2608.trxl.io_0": "sendgrid_link",
    "33286739.trxl.io_0": "sendgrid_link_id",
    "em3322.trxl.io_0": "sendgrid_em",
    "s1._domainkey.trxl.io_0": "sendgrid_dkim_s1",
    "s2._domainkey.trxl.io_0": "sendgrid_dkim_s2",
    "_dmarc.trxl.io_0": "dmarc",
    "send_0": "send_mx",
    "send_1": "send_spf",
    "resend._domainkey.trxl.io_0": "resend_dkim"
  }
};

# The records that stay in terraform-record: rtrox.io's host records, by
# terraform-record's for_each key. Nothing else may be skipped.
def staying: [
  "rtrox.io/mini_0", "rtrox.io/mini_1", "rtrox.io/mini_2",
  "rtrox.io/nas.rtrox.io_0", "rtrox.io/pve.rtrox.io_0", "rtrox.io/backup.rtrox.io_0",
  "rtrox.io/ns1.rtrox.io_0", "rtrox.io/ns2.rtrox.io_0", "rtrox.io/avahi.rtrox.io_0",
  "rtrox.io/unifi.rtrox.io_0", "rtrox.io/ztnet.rtrox.io_0"
];

def hex32: test("^[0-9a-f]{32}$");

# [{zone, type, key, id}] for every managed object in the moving modules.
[ .resources[]
  | select(.mode == "managed" and ((.module // "") as $m | zones | has($m)))
  | zones[.module] as $zone
  | .type as $type
  | .instances[]
  | { zone: $zone, type: $type, old_key: .index_key, id: .attributes.id }
] as $all

| [ $all[] | select(.type == "cloudflare_zone") | {key: .zone, id} ] as $z
| [ $all[] | select(.type == "cloudflare_ruleset") | {key: .zone, id} ] as $r
| [ $all[] | select(.type == "cloudflare_dns_record")
    | . as $o
    | (records[$o.zone] // {})[$o.old_key] as $new
    | select($new != null)
    | {key: "\($o.zone)/\($new)", id: $o.id} ] as $d

# The records skipped above must be exactly rtrox.io's host records.
| [ $all[] | select(.type == "cloudflare_dns_record")
    | select(((records[.zone] // {})[.old_key]) == null)
    | "\(.zone)/\(.old_key)" ] as $skipped

| ([zones[]] | length) as $nzones
| ([records[] | keys[]] | length) as $nrecords
| if ($skipped | sort) != (staying | sort) then
    error("expected the \(staying | length) rtrox.io host records to be skipped, skipped \($skipped | length) (\([$skipped[] | select(. as $s | staying | index($s) | not)] | length) unexpected)")
  elif ($z | length) != $nzones or ($z | map(.key) | unique | length) != $nzones then
    error("expected \($nzones) zones, found \($z | length)")
  elif ($r | length) != $nzones or ($r | map(.key) | unique | length) != $nzones then
    error("expected \($nzones) rulesets, found \($r | length)")
  elif ($d | length) != $nrecords or ($d | map(.key) | unique | length) != $nrecords then
    error("expected \($nrecords) records, found \($d | length)")
  elif ([$z[], $r[], $d[] | .id | hex32] | all | not) then
    error("an ID is not 32 hex characters")
  else
    def block($name; $rows):
      "  \($name) = {\n"
      + ([$rows | sort_by(.key)[] | "    \(.key | @json) = \(.id | @json)"] | join("\n"))
      + "\n  }\n";
    "# From terraform-record cloudflare's state: zones=\($z | length) rulesets=\($r | length) records=\($d | length)\n"
    + "locals {\n"
    + block("imported_zone_ids"; $z)
    + block("imported_ruleset_ids"; $r)
    + block("imported_record_ids"; $d)
    + "}"
  end
