# Checks a saved plan against the changes it is expected to make. Reads
# `tofu show -json <plan>` on stdin (through `task tf:check-plan`, never a file:
# the JSON holds sensitive values in plain text) and an expectation file as
# $expect[0] (jq --slurpfile expect <file>):
#
#   {
#     "changes": { "<address>": "<kind>", ... },
#     "value_from": { "<address>": { "attribute": "value", "references": ["<ref>", ...] } },
#     "value_unknown": { "<address>": "value" },
#     "update_only": { "<address>": ["value", ...] }
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
# come from something the apply creates). Every change that updates
# ("update", "import+update") must have an update_only list, and fails if any
# other top-level attribute differs between before and after, or is unknown
# after. Prints addresses, kinds and attribute names only, never a value.

def kind:
  (.change.actions | join("+")) as $a
  | if .change.importing != null then (if $a == "no-op" then "import" else "import+" + $a end) else $a end;

# Unknown after the plan: true itself, or a nested object or list holding one.
def unknownish: . == true or ((type == "object" or type == "array") and (tostring | test("true")));

# Top-level attribute names whose value changes (or becomes unknown).
def changed_attrs:
  .change as $c
  | (($c.before // {}) | keys) + (($c.after // {}) | keys) + (($c.after_unknown // {}) | keys)
  | unique
  | map(select(. as $k | (($c.before // {})[$k] != ($c.after // {})[$k]) or (($c.after_unknown // {})[$k] | unknownish)));

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
    + [ $rc[] | select(kind | test("update")) | .address as $addr
      | if ($e.update_only // {})[$addr] == null then "update: \($addr) has no update_only list"
        else (changed_attrs - ($e.update_only[$addr])) as $extra
          | select($extra | length > 0)
          | "update: \($addr) also changes \($extra | join(", ")) (only \($e.update_only[$addr] | join(", ")) may)"
        end ]
  ) as $problems
| ($changed | sort_by(.address) | map("  \(.address) \(.kind)") | join("\n")) as $list
| if ($problems | length) == 0 then
    "Planned changes:\n\($list)\nPASS: \($changed | length) changes, all as expected."
  else
    "Planned changes:\n\($list)\n" + ($problems | map("FAIL: " + .) | join("\n")) + "\n" | halt_error(1)
  end
