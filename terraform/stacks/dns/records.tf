# Zone-level records: mail (MX, SPF, DKIM, DMARC) and verification. A host's
# or cluster's own records (A records, tunnel CNAMEs) live in that host's or
# cluster's stack instead, and external-dns manages the HTTPRoute records.
# The exception is host_records.tf: five host records parked here until the
# network stack exists (phase 6).
#
# Every record here is DNS-only (not proxied), with automatic TTL. Names are
# fully qualified. Keys are "<zone>/<name>"; priority is for MX only.
locals {
  dns_records = merge(
    { for k, r in local.records_qol_ink : "qol.ink/${k}" => merge(r, { zone = "qol.ink" }) },
    { for k, r in local.records_rmt_dev : "rmt.dev/${k}" => merge(r, { zone = "rmt.dev" }) },
    { for k, r in local.records_rtrox_com : "rtrox.com/${k}" => merge(r, { zone = "rtrox.com" }) },
    { for k, r in local.records_rtrox_dev : "rtrox.dev/${k}" => merge(r, { zone = "rtrox.dev" }) },
    { for k, r in local.records_rtrox_io : "rtrox.io/${k}" => merge(r, { zone = "rtrox.io" }) },
    { for k, r in local.records_rvl_ink : "rvl.ink/${k}" => merge(r, { zone = "rvl.ink" }) },
    { for k, r in local.records_sxl_ink : "sxl.ink/${k}" => merge(r, { zone = "sxl.ink" }) },
    { for k, r in local.records_troxel_io : "troxel.io/${k}" => merge(r, { zone = "troxel.io" }) },
    { for k, r in local.records_trx_fm : "trx.fm/${k}" => merge(r, { zone = "trx.fm" }) },
    { for k, r in local.records_trxl_ink : "trxl.ink/${k}" => merge(r, { zone = "trxl.ink" }) },
    { for k, r in local.records_trxl_io : "trxl.io/${k}" => merge(r, { zone = "trxl.io" }) },
  )

  # qol.ink is unused and sends and receives no mail; same records as rmt.dev.
  records_qol_ink = {
    null_mx = {
      comment  = "Null MX: this domain accepts no mail (RFC 7505)"
      name     = "qol.ink"
      type     = "MX"
      content  = "."
      priority = 0
    }
    spf_none = {
      comment = "SPF: no server may send as this domain"
      name    = "qol.ink"
      type    = "TXT"
      content = "v=spf1 -all"
    }
    dmarc_reject = {
      comment = "DMARC: reject mail failing SPF/DKIM"
      name    = "_dmarc.qol.ink"
      type    = "TXT"
      content = "v=DMARC1; p=reject"
    }
  }

  # rmt.dev is a curt short domain and sends and receives no mail; same records
  # as rtrox.com's, for the same reason.
  records_rmt_dev = {
    null_mx = {
      comment  = "Null MX: this domain accepts no mail (RFC 7505)"
      name     = "rmt.dev"
      type     = "MX"
      content  = "."
      priority = 0
    }
    spf_none = {
      comment = "SPF: no server may send as this domain"
      name    = "rmt.dev"
      type    = "TXT"
      content = "v=spf1 -all"
    }
    dmarc_reject = {
      comment = "DMARC: reject mail failing SPF/DKIM"
      name    = "_dmarc.rmt.dev"
      type    = "TXT"
      content = "v=DMARC1; p=reject"
    }
  }

  # rtrox.com sends and receives no mail. These records say so, so receivers
  # reject mail spoofing it. To use it for mail, replace all three in one
  # change (real MX, SPF with the provider include, DKIM, DMARC at p=none
  # first).
  records_rtrox_com = {
    null_mx = {
      comment  = "Null MX: this domain accepts no mail (RFC 7505)"
      name     = "rtrox.com"
      type     = "MX"
      content  = "."
      priority = 0
    }
    spf_none = {
      comment = "SPF: no server may send as this domain"
      name    = "rtrox.com"
      type    = "TXT"
      content = "v=spf1 -all"
    }
    dmarc_reject = {
      comment = "DMARC: reject mail failing SPF/DKIM"
      name    = "_dmarc.rtrox.com"
      type    = "TXT"
      content = "v=DMARC1; p=reject"
    }
  }

  # SimpleLogin.
  records_rtrox_dev = {
    simplelogin_verification = {
      comment = "SimpleLogin Verification"
      name    = "rtrox.dev"
      type    = "TXT"
      content = "sl-verification=mlxnsbmfwnkwoxvmtjtgrtsbnmvamg"
    }
    simplelogin_mx_10 = {
      comment  = "SimpleLogin MX record"
      name     = "rtrox.dev"
      type     = "MX"
      content  = "mx1.simplelogin.co"
      priority = 10
    }
    simplelogin_mx_20 = {
      comment  = "SimpleLogin MX record"
      name     = "rtrox.dev"
      type     = "MX"
      content  = "mx2.simplelogin.co"
      priority = 20
    }
    simplelogin_spf = {
      comment = "SimpleLogin SPF record"
      name    = "rtrox.dev"
      type    = "TXT"
      content = "v=spf1 include:simplelogin.co ~all"
    }
    simplelogin_dkim = {
      comment = "SimpleLogin DKIM record"
      name    = "dkim._domainkey.rtrox.dev"
      type    = "CNAME"
      content = "dkim._domainkey.simplelogin.co"
    }
    simplelogin_dkim_2 = {
      comment = "SimpleLogin DKIM record"
      name    = "dkim02._domainkey.rtrox.dev"
      type    = "CNAME"
      content = "dkim02._domainkey.simplelogin.co"
    }
    simplelogin_dkim_3 = {
      comment = "SimpleLogin DKIM record"
      name    = "dkim03._domainkey.rtrox.dev"
      type    = "CNAME"
      content = "dkim03._domainkey.simplelogin.co"
    }
    simplelogin_dmarc = {
      comment = "SimpleLogin DMARC record"
      name    = "_dmarc.rtrox.dev"
      type    = "TXT"
      content = "v=DMARC1; p=quarantine; pct=100; adkim=s; aspf=s"
    }
  }

  # Proton Mail, Resend (send.rtrox.io) and Bluesky handles.
  records_rtrox_io = {
    bluesky_atproto = {
      comment = "Bluesky Verification"
      name    = "_atproto.rtrox.io"
      type    = "TXT"
      content = "did=did:plc:lzu4jx4xi6gh5zdyynbqpdza"
    }
    protonmail_verification = {
      comment = "Protonmail Verification"
      name    = "rtrox.io"
      type    = "TXT"
      content = "protonmail-verification=1d3b5918493d4a6b8fd1811f0a1c73738791a11e"
    }
    protonmail_mx_10 = {
      comment  = "Protonmail MX"
      name     = "rtrox.io"
      type     = "MX"
      content  = "mail.protonmail.ch"
      priority = 10
    }
    protonmail_mx_20 = {
      comment  = "Protonmail MX"
      name     = "rtrox.io"
      type     = "MX"
      content  = "mailsec.protonmail.ch"
      priority = 20
    }
    protonmail_spf = {
      comment = "Protonmail SPF"
      name    = "rtrox.io"
      type    = "TXT"
      content = "v=spf1 include:_spf.protonmail.ch ~all"
    }
    protonmail_dkim = {
      comment = "Protonmail DKIM"
      name    = "protonmail._domainkey.rtrox.io"
      type    = "CNAME"
      content = "protonmail.domainkey.dli5ot74cntgwkqd7tyhnlt5zlndyicykn27pmyzs4gmz2fxhsa4q.domains.proton.ch"
    }
    protonmail_dkim_2 = {
      comment = "Protonmail DKIM"
      name    = "protonmail2._domainkey.rtrox.io"
      type    = "CNAME"
      content = "protonmail2.domainkey.dli5ot74cntgwkqd7tyhnlt5zlndyicykn27pmyzs4gmz2fxhsa4q.domains.proton.ch"
    }
    protonmail_dkim_3 = {
      comment = "Protonmail DKIM"
      name    = "protonmail3._domainkey.rtrox.io"
      type    = "CNAME"
      content = "protonmail3.domainkey.dli5ot74cntgwkqd7tyhnlt5zlndyicykn27pmyzs4gmz2fxhsa4q.domains.proton.ch"
    }
    protonmail_dmarc = {
      comment = "Protonmail DMARC"
      name    = "_dmarc.rtrox.io"
      type    = "TXT"
      content = "v=DMARC1; p=none"
    }
    resend_mx = {
      comment  = "Resend MX"
      name     = "send.rtrox.io"
      type     = "MX"
      content  = "feedback-smtp.us-east-1.amazonses.com"
      priority = 10
    }
    resend_spf = {
      comment = "Resend SPF"
      name    = "send.rtrox.io"
      type    = "TXT"
      content = "v=spf1 include:amazonses.com ~all"
    }
    resend_dkim = {
      comment = "Resend DKIM"
      name    = "resend._domainkey.rtrox.io"
      type    = "TXT"
      content = "p=MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQDC4Ouykt+YcFO7MMtWryHcwI/DWlMqduE4VVPmoc2D2r5+iFPNZK1zvtirm3Wf5a3XbWJeBRfo1Xw+2m5nX1AWUgbCTKlXTsV+HqpEQ5U+lAj+O73ci3K9iSU+v8192FLgnhc7ejYlhZnQZW3PBCLf6Pbio7XJmNp4rtCEHUVeGwIDAQAB"
    }
  }

  # rvl.ink is unused and sends and receives no mail; same records as rmt.dev.
  records_rvl_ink = {
    null_mx = {
      comment  = "Null MX: this domain accepts no mail (RFC 7505)"
      name     = "rvl.ink"
      type     = "MX"
      content  = "."
      priority = 0
    }
    spf_none = {
      comment = "SPF: no server may send as this domain"
      name    = "rvl.ink"
      type    = "TXT"
      content = "v=spf1 -all"
    }
    dmarc_reject = {
      comment = "DMARC: reject mail failing SPF/DKIM"
      name    = "_dmarc.rvl.ink"
      type    = "TXT"
      content = "v=DMARC1; p=reject"
    }
  }

  # sxl.ink is unused and sends and receives no mail; same records as rmt.dev.
  records_sxl_ink = {
    null_mx = {
      comment  = "Null MX: this domain accepts no mail (RFC 7505)"
      name     = "sxl.ink"
      type     = "MX"
      content  = "."
      priority = 0
    }
    spf_none = {
      comment = "SPF: no server may send as this domain"
      name    = "sxl.ink"
      type    = "TXT"
      content = "v=spf1 -all"
    }
    dmarc_reject = {
      comment = "DMARC: reject mail failing SPF/DKIM"
      name    = "_dmarc.sxl.ink"
      type    = "TXT"
      content = "v=DMARC1; p=reject"
    }
  }

  # SendGrid, Proton Mail and Google.
  records_troxel_io = {
    sendgrid_link = {
      comment = "Sendgrid URL verification"
      name    = "em9286.troxel.io"
      type    = "CNAME"
      content = "u33286739.wl240.sendgrid.net"
    }
    sendgrid_dkim_s1 = {
      comment = "Sendgrid DKIM verification"
      name    = "s1._domainkey.troxel.io"
      type    = "CNAME"
      content = "s1.domainkey.u33286739.wl240.sendgrid.net"
    }
    sendgrid_dkim_s2 = {
      comment = "Sendgrid DKIM verification"
      name    = "s2._domainkey.troxel.io"
      type    = "CNAME"
      content = "s2.domainkey.u33286739.wl240.sendgrid.net"
    }
    proton_mx_1 = {
      comment  = "Protonmail MX record"
      name     = "troxel.io"
      type     = "MX"
      content  = "mail.protonmail.ch"
      priority = 10
    }
    proton_mx_2 = {
      comment  = "Protonmail MX record"
      name     = "troxel.io"
      type     = "MX"
      content  = "mailsec.protonmail.ch"
      priority = 20
    }
    google_verification = {
      comment = "Google site verification"
      name    = "troxel.io"
      type    = "TXT"
      content = "google-site-verification=g9jQh36IhyFLdVsX5Dp2ljSg06TaEhUTcqNitjWH-zs"
    }
    protonmail_verification = {
      comment = "Protonmail verification"
      name    = "troxel.io"
      type    = "TXT"
      content = "protonmail-verification=3a3e18764c54af858aa9013519d6f9a8ef87a632"
    }
    google_dkim = {
      comment = "Google DKIM verification"
      name    = "google._domainkey.troxel.io"
      type    = "TXT"
      content = "v=DKIM1; k=rsa; p=MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAroapMnNgBTCIoAJ6hY0TAAklFqcLg2ZanigoAq60JTi/fjprnj2erUY7OX1oRJ0DsdEVirNaQTJ4YpwmRXgwMjV3LWrefAD3RJuCU+IqoTmPJmmEZWotVmKdzs1akx81ufPkxEGcd5wD9pZBosyfW52em0waC8PBH/CRMksO+ufrGQQGlKdglCjxagnmnvGImjxB80rT28GAIghzkydMgK763GYmGfnkZEVYBO/anXT3jsMDvF7yeXFoD4LPFK+0ty54uUlOfKG/2woEZ+8meTdDJqLANFANZ+/HicY1GNp9kOg8mfmbtaBfaZkCKf45lOGTkss5usd89MZdZOkU8QIDAQAB"
    }
    protonmail_spf = {
      comment = "Protonmail SPF record"
      name    = "troxel.io"
      type    = "TXT"
      content = "v=spf1 include:_spf.protonmail.ch include:_spf.google.com ~all"
    }
    protonmail_dkim = {
      comment = "Protonmail DKIM record"
      name    = "protonmail._domainkey.troxel.io"
      type    = "CNAME"
      content = "protonmail.domainkey.dgjndy7w6nslvxhxvqeevmi5rxmzbvwlwsoo73qdef2s7fbjrtm5q.domains.proton.ch"
    }
    protonmail_dkim2 = {
      comment = "Protonmail DKIM record"
      name    = "protonmail2._domainkey.troxel.io"
      type    = "CNAME"
      content = "protonmail2.domainkey.dgjndy7w6nslvxhxvqeevmi5rxmzbvwlwsoo73qdef2s7fbjrtm5q.domains.proton.ch"
    }
    protonmail_dkim3 = {
      comment = "Protonmail DKIM record"
      name    = "protonmail3._domainkey.troxel.io"
      type    = "CNAME"
      content = "protonmail3.domainkey.dgjndy7w6nslvxhxvqeevmi5rxmzbvwlwsoo73qdef2s7fbjrtm5q.domains.proton.ch"
    }
    protonmail_dmarc = {
      comment = "Protonmail DMARC record"
      name    = "_dmarc.troxel.io"
      type    = "TXT"
      content = "v=DMARC1; p=quarantine"
    }
  }

  # trx.fm is for short links and sends and receives no mail; same records as
  # rmt.dev. Its web records come with the short-link service.
  records_trx_fm = {
    null_mx = {
      comment  = "Null MX: this domain accepts no mail (RFC 7505)"
      name     = "trx.fm"
      type     = "MX"
      content  = "."
      priority = 0
    }
    spf_none = {
      comment = "SPF: no server may send as this domain"
      name    = "trx.fm"
      type    = "TXT"
      content = "v=spf1 -all"
    }
    dmarc_reject = {
      comment = "DMARC: reject mail failing SPF/DKIM"
      name    = "_dmarc.trx.fm"
      type    = "TXT"
      content = "v=DMARC1; p=reject"
    }
  }

  # trxl.ink is a curt short domain and sends and receives no mail.
  records_trxl_ink = {
    null_mx = {
      comment  = "Null MX: this domain accepts no mail (RFC 7505)"
      name     = "trxl.ink"
      type     = "MX"
      content  = "."
      priority = 0
    }
    spf_none = {
      comment = "SPF: no server may send as this domain"
      name    = "trxl.ink"
      type    = "TXT"
      content = "v=spf1 -all"
    }
    dmarc_reject = {
      comment = "DMARC: reject mail failing SPF/DKIM"
      name    = "_dmarc.trxl.ink"
      type    = "TXT"
      content = "v=DMARC1; p=reject"
    }
  }

  # SendGrid and Resend (send.trxl.io, on Amazon SES).
  records_trxl_io = {
    sendgrid_link = {
      comment = "Sendgrid URL verification"
      name    = "url2608.trxl.io"
      type    = "CNAME"
      content = "sendgrid.net"
    }
    sendgrid_link_id = {
      comment = "Sendgrid URL verification"
      name    = "33286739.trxl.io"
      type    = "CNAME"
      content = "sendgrid.net"
    }
    sendgrid_em = {
      comment = "Sendgrid URL verification"
      name    = "em3322.trxl.io"
      type    = "CNAME"
      content = "u33286739.wl240.sendgrid.net"
    }
    sendgrid_dkim_s1 = {
      comment = "Sendgrid DKIM verification"
      name    = "s1._domainkey.trxl.io"
      type    = "CNAME"
      content = "s1.domainkey.u33286739.wl240.sendgrid.net"
    }
    sendgrid_dkim_s2 = {
      comment = "Sendgrid DKIM verification"
      name    = "s2._domainkey.trxl.io"
      type    = "CNAME"
      content = "s2.domainkey.u33286739.wl240.sendgrid.net"
    }
    dmarc = {
      comment = "DMARC record for trxl.io"
      name    = "_dmarc.trxl.io"
      type    = "TXT"
      content = "v=DMARC1; p=none;"
    }
    send_mx = {
      comment  = "Amazon SES MX record"
      name     = "send.trxl.io"
      type     = "MX"
      content  = "feedback-smtp.us-east-1.amazonses.com"
      priority = 10
    }
    # The live comment says MX, though it's the SPF record; kept as it is so
    # the import changes nothing.
    send_spf = {
      comment = "Amazon SES MX record"
      name    = "send.trxl.io"
      type    = "TXT"
      content = "v=spf1 include:amazonses.com ~all"
    }
    resend_dkim = {
      comment = "Amazon SES DKIM verification"
      name    = "resend._domainkey.trxl.io"
      type    = "TXT"
      content = "p=MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQDwrpq2KHwq9PhNC4B1wSfHfkXeww8aBnvVECBwVbsIVpd97No5z8xCjKAfBLBKEJ5luVFzOdJw6HR7OZTX3v41BgYUDxfMJLIdK/dRD7ir70KxM64ZfeIKUMSrtNiBjeyrTS9DBftU4Yon+38Nn7CF8geQzhiAb2jPwCeIm3mBAQIDAQAB"
    }
  }
}

resource "cloudflare_dns_record" "this" {
  for_each = local.dns_records

  zone_id  = module.zone[each.value.zone].zone_id
  name     = each.value.name
  type     = each.value.type
  content  = each.value.content
  comment  = each.value.comment
  priority = try(each.value.priority, null)
  proxied  = false
  ttl      = 1
}
