# lyb.app is no longer renewed (owner, Nov 23), so Terraform lets go of its
# zone and ruleset without destroying them; the owner deletes the zone in the
# dashboard. `removed` can't name one for_each instance, so the instance moves
# to an address with no configuration first, and that address is forgotten.
# Delete this file once applied.
moved {
  from = module.zone["lyb.app"]
  to   = module.zone_lyb_app_retired
}

removed {
  from = module.zone_lyb_app_retired

  lifecycle {
    destroy = false
  }
}
