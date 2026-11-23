# Checks a saved plan against the changes it is expected to make. Reads
# `tofu show -json <plan>` on stdin (through `task tf:check-plan`, never a file:
# the JSON holds sensitive values in plain text) and an expectation file as
# $expect[0] (jq --slurpfile expect <file>):
#
#   {
#     "changes": { "<address>": "<kind>", ... },
#     "value_from": { "<address>": { "attribute": "value", "references": ["<ref>", ...] } },
#     "value_unknown": { "<address>": "value" }
#   }
#
# kind: "import" (imported, nothing else), "import+update", "create",
# "update", "delete", "forget", ...: the actions joined with "+", prefixed
# with "import+" when the resource is imported.
#
# Fails if any managed resource changes in a way not listed (no-ops are
# ignored), a listed change is missing, anything is deleted that isn't listed
# as such, a value_from attribute isn't built from every listed reference, or
# a value_unknown attribute is already known at plan time (it must
# come from something the apply creates). Prints addresses and kinds only,
# never a value.

def kind:
  (.change.actions | join("+")) as $a
  | if .change.importing != null then (if $a == "no-op" then "import" else "import+" + $a end) else $a end;

. as $plan
| ($expect[0]) as $e
| [ $plan.resource_changes[]? | select(.mode == "managed") ] as $rc
| [ $rc[] | {address, kind: kind} | select(.kind != "no-op") ] as $changed
| ($changed | map(.address)) as $changed_addrs
| (
    [ $changed[] | select(($e.changes[.address] // "no change") != .kind)
      | "unexpected: \(.address) \(.kind) (expected: \($e.changes[.address] // "no change"))" ]
    + [ $e.changes | to_entries[] | select(.key as $k | $changed_addrs | index($k) | not)
      | "missing: \(.key) \(.value)" ]
    + [ ($e.value_from // {}) | to_entries[] | .key as $addr | .value.attribute as $attr | .value.references[] as $ref
      | select([ $plan.configuration.root_module.resources[]? | select(.address == $addr)
                 | .expressions[$attr].references[]? ] | index($ref) | not)
      | "value: \($addr).\($attr) isn't built from \($ref)" ]
    + [ ($e.value_unknown // {}) | to_entries[] | .key as $addr | .value as $attr
      | select([ $rc[] | select(.address == $addr) | .change.after_unknown[$attr] ] | first != true)
      | "value: \($addr).\($attr) is known at plan time, so it isn't built from something new" ]
  ) as $problems
| ($changed | sort_by(.address) | map("  \(.address) \(.kind)") | join("\n")) as $list
| if ($problems | length) == 0 then
    "Planned changes:\n\($list)\nPASS: \($changed | length) changes, all as expected."
  else
    "Planned changes:\n\($list)\n" + ($problems | map("FAIL: " + .) | join("\n")) + "\n" | halt_error(1)
  end
