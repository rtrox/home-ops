output "id" {
  description = "The token's ID (not secret)."
  value       = cloudflare_api_token.this.id
}

output "name" {
  value = cloudflare_api_token.this.name
}

output "value" {
  description = "The token itself."
  value       = cloudflare_api_token.this.value
  sensitive   = true
}

output "expires_on" {
  value = cloudflare_api_token.this.expires_on
}
