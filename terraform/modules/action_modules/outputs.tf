# version_id is available directly on the resource when publish = true.
# No data source needed — simpler and reliable on first run.
output "module_map" {
  description = "Map of module key to { id, version_id }"
  value = {
    for k, v in auth0_action_module.this : k => {
      id         = v.id
      version_id = v.version_id
    }
  }
}
