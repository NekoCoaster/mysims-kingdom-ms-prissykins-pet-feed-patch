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

The helper avoids changing schema flags, replacing game binaries, or modifying save contents. It performs the successful data-only live registration and requires rerunning after the island is recreated.

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

After a clean restart, the packaged helper successfully added the registration, a second inspection confirmed it was present, and the player confirmed the interaction prompt appeared. Both actions and audio have been confirmed working after the tower quest. The README includes the player's petting recording. Before-quest behavior, island departure/return, and a second machine have not been independently validated.

Supported executable SHA-256: `F7AD84B5D5DAC73EE4E777590324D99E5A6E1F2B0C0CFDA69C448E50B9495B2A` (Steam build 21152538).

External memory writes are not entirely race-free. The helper checks the target and list state immediately before writing, but should only be run while stationary beside the cat after loading has completed. It refuses registration if the existing interaction vector has no spare capacity.
