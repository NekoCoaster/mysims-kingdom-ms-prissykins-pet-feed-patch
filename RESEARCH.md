# Investigation notes

## Findings

The reproduced problem had two independent gates:

1. The Lua Pet/Feed availability tests require `bHerded` or `bPetWhenNotHerded`.
2. Before those tests, native nearby-object selection searches the island's `Interactable` filter.

The inspected completed-quest save already had `bHerded = true`. Adding `bPetWhenNotHerded = true` did not solve that player's missing prompt. Ms. Prissykins was absent from the native interaction list; pigs were present. Her hover tooltip uses another path, so seeing her name did not prove interaction registration.

Appending the cat's existing object handle to that list immediately exposed both actions. The player manually confirmed both animations finished and subsequently confirmed that audio works.

## Rejected script-only attempt

An `AnimalLoad.lua` attempt used `Luattrib:WriteAttribute` to append to `SearchFilters`. It did not enable interactions after restarting and was restored to the original file.

Native inspection showed that `SearchFilters` is an inherited, read-only, fixed array of collection keys. Its Lua values are reference tables, not bare key userdata, and the whole-array writer attempts to resize the array through an API that rejects fixed arrays. Correcting only the Lua value format would therefore not make that attempt work.

The original external helper performs the successful data-only live registration and requires rerunning after the island is recreated. Version 0.2.0 moves that logic into an automatically loaded WinMM proxy DLL, which checks for registration throughout the game session. Neither approach changes schema flags or save contents.

## Supported executable layout

All addresses below are relative to the verified executable's loaded module base. ASLR is handled by obtaining that base from the running process.

| Item | RVA / offset |
| --- | --- |
| Object table pointer | `0xae9798` |
| Object table count (uint16) | `0xae97a0` |
| Interaction filter key | `0xae9908` |
| Object handle | object + `0x08` |
| Object class / collection | object + `0x28` / `0x30` |
| World transform component | object + `0x50` |
| World filter map begin/end | transform + `0x88` / `0x90` |

Object-table slots may contain free-list metadata rather than pointers. The helper ignores unreadable slots, then requires a unique exact class/collection match. The cat's handle must also match its table slot and already belong to the island's herdables list.

The filter map has 16-byte entries: uint32 key at +0, vector pointer at +8. A candidate vector stores begin/end/capacity pointers and uint32 object handles. The helper writes only into existing spare capacity and then advances the end pointer by four bytes. It performs no allocation, code injection, hook, or executable patch.

Keys use lowercase FNV-1:

| Meaning | Key |
| --- | --- |
| herdables | `2c2e0959` |
| cat_animal_01 | `977da888` |
| world | `9b8e862f` |
| animal_01 | `4036ce55` |
| Interactable | `ee4d5fe7` |

The layout must be revalidated for each new executable hash. Passing the current hash gate is necessary but does not establish compatibility with arbitrary mods that change object creation or native layout.

## Validation notes

Automatic interaction registration, the original animations, and sound variation work after the tower quest. The README includes a petting demonstration.

Supported executable SHA-256: `F7AD84B5D5DAC73EE4E777590324D99E5A6E1F2B0C0CFDA69C448E50B9495B2A` (Steam build 21152538).

External memory writes are not entirely race-free. The helper checks the target and list state immediately before writing, but should only be run while stationary beside the cat after loading has completed. It refuses registration if the existing interaction vector has no spare capacity.

## Sound variation and automatic loading

Pet (`479c95c0`, bank 253) and Feed (`46c8d125`, bank 250) each have two recordings. The native playback path chooses a non-repeating variant twice, effectively cancelling alternation: `1402cb2d0` updates the last index, then the path through `1403f9b40` / `1403f9360`, `1402cda70`, and `1402cdf90` selects again before `1402ce8f0` posts the event. These addresses use the executable's preferred base, not ASLR addresses.

After observing a matching active voice for 80 ms, the fix changes that group's last index to prepare the alternate recording for the next action. It handles each voice identity once and ignores other sound groups. Manually changing the index changed both recordings in the live test; repeated actions with the helper confirmed variation.

The proxy forwards WinMM calls to the absolute Windows system DLL and starts its worker only inside the hash-verified game. It uses a per-process mutex to avoid competing with the old sound helper, waits for stable object identities before registration, and requires existing vector capacity. It does not install a Windows startup process. See [native/README.md](native/README.md) for build instructions and remaining concurrency limits.

## Follow and Stay

The installer appends `CatFollowStay.lua` to `CatAnimal.lua`. The proxy handles interaction registration and sound variants. The CatAnimal jobs inherit the stock Pet and Feed jobs and wait for a successful result. The player, `animal_01`, exact `cat_animal_01` collection, and completion of `NPC_Renee_ExplainCat` gate the commands.

Feed sets a session mode and a quarter-second timer. The cat starts native reverse steering outside 2.8 units, waits within 1.6 units, and resumes when the player moves away. Pet cancels the timer and holds position with stock idles. The mode suspends while an interaction runs and resumes after cancellation. There is no save field for the mode. Stock saves may still record the cat's location. Castle trigger occupancy updates while commanded, but the completed quest's herd flag stays as it was. The mod clears the command on save reload and does not spawn or move an actor to a different world.

Static native evidence: Lua `StartReverseSteering` (`140373540`) enters `140372960`, which sets steering bits `0x02` and `0x20`. `TurnOffAwareness` (`1403736c0` -> `140372c10`) clears the separate `0x08` awareness flag used by `140372010` to dispatch proximity callbacks. The `140372160` update invokes `140371c50` when steering bit `0x02` is active. That function resolves the target and uses its horizontal direction, reversed toward the target when `0x20` is set. It has no range or time cutoff in that branch. `StopSteering` (`140373600` -> `140372bb0`) clears steering bits and sets requested speed to zero. Stock `cat_animal_01` has `FleeSpeed = 2.0` and `FleeAwarenessDistance = 4.5`. Follow uses this direct steering with the player as target. The cat moves toward the player and remains subject to the game's terrain and collision behavior. Gameplay confirmed Follow, Stay, and normal meow and stretch idles.

## Travelling companion investigation

Buddy and Lyndsay are represented by local character records. In the shipped `attribdb.log`, `animal_buddy` and `animal_linzey` belong to `world:animal_01`, and `cap_buddy` and `cap_linzey` belong to `world:capital_01`. There are also `transition_buddy_animal` and `transition_linzey_animal` records for the boat scene `transition_world_to_renee`. The `Schedule_Animal_*` Lua files register the NPC roles and schedules for that destination. `Boat_Interaction_LeaveIsland.lua` requests the gameplay world change and teleports the player. It does not pass the island actors as passengers. The static evidence supports local instances that represent the same logical characters on different islands.

Ms. Prissykins has a placed herdable on `animal_01`. A comparable implementation would keep one logical companion state, wait for the destination gameplay world to finish loading, and activate exactly one destination cat. It would reuse the placed quest cat at the nature preserve, use a temporary herdable instance elsewhere, and clean it up on departure. The game already spawns a herdable through `Job_SpawnObject` in `Task_Cute_Daniel.lua`, and the credits script spawns `cat_credits` separately. These demonstrate ingredients, not a tested travel implementation. Destination spawn placement, automatic saving of temporary actors, duplicate prevention, interaction registration in non-home worlds, and boat scene behavior still need separate tests. No cross-world changes were made.
