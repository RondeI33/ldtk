# Auto-chain back references

An entity definition can configure a different field for the return link created by
automatic EntityRef chaining. The configuration lives only in the fork sidecar;
the `.ldtk` project and exported level schema stay compatible with stock LDtk and
Unity importers.

For VeinCable, leave **Auto chain ref** enabled on `To` and disabled on `From`.
Use ordinary, non-symmetrical reference fields for this directional cable chain.
In `00_VeinRework.ldtk-fork.json`, add this property to the **existing**
`entities["3873"]` object:

```json
"autoChainBackRefs": [
  { "chainField": "To", "backField": "From" }
]
```

Keep the existing properties, including `appearanceOverrides`. This snippet is an
additional property, not a replacement sidecar or replacement entity object.
Reload the sidecar through the existing fork authoring controls, or reopen the
project, after editing it externally.

The entity key follows the existing sidecar convention: the entity definition
UID, with the existing optional `identifier` fallback. `chainField` and
`backField` are case-sensitive field identifiers. Update the rule if either field
is renamed. The return field is looked up on the target entity, so the two
entities can use different definitions.

A missing configuration keeps the original chaining behavior. Empty or malformed
rules are ignored and logged. If several rules name the same `chainField`, the
first valid rule is used.

## Behavior and history

Placing three cables creates `K1.To = K2`, `K2.From = K1`, `K2.To = K3` and
`K3.From = K2`. Clicking an existing target uses the same logic. The target field
must be an EntityRef and must accept the source entity and its level.

An occupied scalar return field is preserved and the conflict is written to LOG.
An array return field appends the source without deleting earlier values or
adding a duplicate. A full bounded array is preserved and logged. If a return
field enables symmetrical references, its opposite field is checked as well so
that applying symmetry cannot overwrite another existing link.

Both changed entity layers are captured together in one link-history checkpoint
when the entities belong to the same level. Undo/Redo restores both directions;
the existing placement checkpoint is unchanged. Cross-level links keep the
editor's existing rule of not writing a cross-level history checkpoint.

The real-editor regression suite can be run from `app` with
`npm run test:entity-chain`. On a headless Linux machine, use
`xvfb-run -a -s "-screen 0 1600x1000x24" npm run test:entity-chain`.
