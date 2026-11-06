# Engine regression tests

Requires Python 3 and an installed Factorio 2.1 executable. Tests use separate mod,
settings and save directories; normal player mods and saves are never changed.
Drivers are appended only to disposable test ZIPs, not to the published ZIP.
Logs are retained. `--work-dir` selects their directory; `--source` selects source.

```powershell
python tests/run.py --factorio-exe 'D:\SteamLibrary\steamapps\common\Factorio\bin\x64\factorio.exe'
python tests/run.py --factorio-exe 'D:\SteamLibrary\steamapps\common\Factorio\bin\x64\factorio.exe' --suite building
python tests/run.py --factorio-exe 'D:\SteamLibrary\steamapps\common\Factorio\bin\x64\factorio.exe' --suite groups
```

The default `protection` suite checks creation, disable/enable, deletion, original
false properties, intersections in both removal orders, repeated events, resources
and other entity types, moved/destroyed objects and real saves.

`building` enables the installed official quality/recycler mods. It uses native
blueprint/player build APIs and real flying construction robots. Checks include
exact refunds and quality, full inventories, partial overflow, full robot cargo,
zone activation after pickup, allowed construction, demolition revoked in flight
while humans remain allowed to mine, and permitted demolition without item loss.

`groups` uses real Factorio groups, entities and GUI elements. It checks:

- Editor saves, safe defaults and original entity properties.
- Engine input permissions, already running mining stopped, chest GUI refused.
- Native permitted mining/building, forbidden build refunds, target coordinates.
- Global prohibitions/edits, reassignment, rename and new groups.
- Derived-group creation for a non-admin denied permission-group management.
- Intersection denial, live updates and separate robot policy.
- Native ghost deletion preserving the denied ghost's blueprint recipe.
- Authorization rechecked on save/tool use; stale editor rejected.
- Group deletion, fallback, restoration and derived-group cleanup.
- Real save/load and old storage loaded under the same mod version.

Lua player APIs can bypass native input permissions. The suite inspects the
engine's actual effective permission group alongside native permitted actions;
it does not claim a two-client network test.
