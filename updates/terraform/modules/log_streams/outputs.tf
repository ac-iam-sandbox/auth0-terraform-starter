output "stream_map" {
  value = { for k, v in auth0_log_stream.this : k => v.id }
}
