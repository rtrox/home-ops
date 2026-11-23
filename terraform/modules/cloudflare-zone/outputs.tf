output "zone_id" {
  value = cloudflare_zone.this.id
}

output "name" {
  value = cloudflare_zone.this.name
}

output "name_servers" {
  # Sorted: Cloudflare doesn't guarantee an order.
  value = sort(cloudflare_zone.this.name_servers)
}
