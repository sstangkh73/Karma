# Evidence index

Repository: https://github.com/sstangkh73/Karma
Author ORCID: https://orcid.org/0009-0000-2979-1916
Licence: MIT (`LICENSE`)

KARMA won **Grand Champion** at *Thailand Simulation Gen Z on Roblox*, organised
by the Faculty of Information and Communication Technology, Mahidol University,
on 15 August 2026 — first place in a national final of 20 secondary-school teams.
Team: Afterclass.

## Claims and how to check them

| Claim | How to check |
| --- | --- |
| 56 Luau scripts | `git ls-files '*.luau' \| wc -l` |
| ~15,600 lines of Luau | `git ls-files '*.luau' \| xargs cat \| wc -l` |
| Runtime architecture is a module registry with explicit startup ordering | Read `tmp/Roblox/src/server/CoreBootstrap.server.luau` and `tmp/Roblox/src/client/CoreBootstrap.client.luau` |

## The architecture claim, in the code

`CoreBootstrap.server.luau` is 25 lines and does exactly one thing: it hands
control to a registry rather than starting services itself.

```lua
local ModuleLoader = require(Core:WaitForChild("ModuleLoader"))
local SystemHub    = require(Core:WaitForChild("SystemHub"))

SystemHub.initialize("Server")
if not SystemHub.begin("ServerCoreBootstrap", script) then return end

ModuleLoader.startFolder(servicesFolder, { Side = "Server", SystemHub = SystemHub })

SystemHub.ready("ServerCoreBootstrap", script)
SystemHub.completeStartup()
```

`SystemHub` tracks each system through `begin` → `ready` → `completeStartup`,
with a `failed` path and a startup summary, so dependency order is explicit and
a system that never reports ready is visible rather than silently missing.
`ModuleLoader.startFolder` is what registers and starts a folder of services.

## Author's contribution

The runtime architecture — `ModuleLoader`, `SystemHub`, and the bootstrap
sequence above — plus the systems built on it. KARMA was a team entry; this
repository is the code as submitted, and the architecture claim above is the part
attributable to this author. Other team members contributed to the game's
design, art, and content.
