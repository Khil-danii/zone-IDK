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
