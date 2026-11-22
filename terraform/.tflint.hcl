# TFLint for every stack and module under terraform/ (`tflint --recursive`).
# The terraform ruleset is bundled with tflint; provider rulesets get added
# here when a stack starts using that provider.
config {
  call_module_type = "local"
}

plugin "terraform" {
  enabled = true
  preset  = "recommended"
}
