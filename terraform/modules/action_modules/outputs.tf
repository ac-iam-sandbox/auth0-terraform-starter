output "module_map" {
  description = "Map of module key to { id, version_id }. Always uses latest published version."
  value = {
    for k, v in auth0_action_module.this : k => {
      id         = v.id
      version_id = try(data.auth0_action_module_versions.this[k].versions[0].id, v.version_id)
    }
  }
}
