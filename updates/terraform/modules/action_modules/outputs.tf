output "module_map" {
  description = "Map of active module key to { id, version_id }"
  value = {
    for k, v in auth0_action_module.this : k => {
      id         = v.id
      version_id = v.version_id
    }
  }
}
