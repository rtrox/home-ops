# A marker, written by the apply that re-encrypted this state from the laptop
# passphrase to the shared one (README.md, "In CI"): that apply needed a change
# to save the state with the new key. Nothing depends on it.
resource "terraform_data" "state_encryption" {
  input = "shared passphrase (TOFU_STATE_PASSPHRASE), since the move to CI"
}
