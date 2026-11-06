Run with Python 3 and an installed Factorio 2.1 executable:

```powershell
python tests/run.py --factorio-exe 'D:\SteamLibrary\steamapps\common\Factorio\bin\x64\factorio.exe'
```

The runner creates a separate test mod ZIP, settings, and save directory. It appends
the regression driver only to that disposable ZIP and invokes the real selection
and GUI click handlers with Factorio entities and GUI buttons. The published mod
ZIP does not contain the driver.

Checks cover zone creation, disable/enable, active and inactive deletion, original
false properties, overlapping zones, repeated action events, resources and other
entity types, moved/destroyed entities, and saving/reloading active protections.
Test directories and logs are retained; `--work-dir` chooses their location.

To run the construction/refund checks, add `--suite building`:

```powershell
python tests/run.py --factorio-exe 'D:\SteamLibrary\steamapps\common\Factorio\bin\x64\factorio.exe' --suite building
```

This suite enables the installed official quality/recycler mods. It places a
blueprint and items through Factorio's player APIs, then runs real construction
robots and enables protection after they pick up their materials. It verifies
item counts and quality, and checks that refund overflow is dropped on the ground.
Controlled events with real inventories also cover multiple consumed stacks,
partial insertion and full robot cargo. The default protection suite still checks
the earlier zone lifecycle and save/load regressions without requiring quality.
