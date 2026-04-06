output "client_ids" {
  description = "Map of client key to Auth0 client ID"
  value       = module.clients.client_map
}

output "client_grant_ids" {
  description = "Map of grant key to Auth0 client grant ID"
  value       = module.client_grants.grant_map
}

output "log_stream_ids" {
  description = "Map of log stream key to Auth0 log stream ID"
  value       = module.log_streams.stream_map
}

output "region" {
  description = "The region this state applies to"
  value       = var.region
}

output "environment" {
  description = "The environment this state applies to"
  value       = var.environment
}
