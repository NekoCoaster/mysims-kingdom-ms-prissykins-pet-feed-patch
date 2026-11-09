#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <bcrypt.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <vector>
#include <array>
#include <algorithm>
#include "exports.inc"

extern "C" { void* g_targets[ExportCount] = {}; }
static INIT_ONCE forwardOnce = INIT_ONCE_STATIC_INIT;
static HMODULE selfModule;
static volatile LONG workerStarted = 0;
static HANDLE logFile = INVALID_HANDLE_VALUE;
static uintptr_t base;
static bool gameVerified = false;
static bool travelBound = false;

static void log(const char* message) {
    if (logFile == INVALID_HANDLE_VALUE) return;
    char line[256];
    int n = snprintf(line, sizeof(line), "[%llu] %s\r\n", (unsigned long long)GetTickCount64(), message);
    DWORD written;
    if (n > 0) WriteFile(logFile, line, (DWORD)(std::min)(n, 255), &written, nullptr);
    FlushFileBuffers(logFile);
}
static bool read(uintptr_t p, void* out, size_t n) {
    if (!n) return true;
    if (p < 0x10000 || p > 0x7fffffffffffULL || n > 1048576) return false;
    SIZE_T got = 0;
    return ReadProcessMemory(GetCurrentProcess(), (void*)p, out, n, &got) && got == n;
}
template<class T> static bool get(uintptr_t p, T& out) { return read(p, &out, sizeof(out)); }
template<class T> static T value(uintptr_t p) { T result{}; get(p, result); return result; }
static bool write(uintptr_t p, const void* in, size_t n) {
    SIZE_T done = 0;
    return WriteProcessMemory(GetCurrentProcess(), (void*)p, in, n, &done) && done == n;
}
static bool gamePath(wchar_t* path) {
    DWORD n = GetModuleFileNameW(nullptr, path, MAX_PATH);
    if (!n || n >= MAX_PATH) return false;
    const wchar_t* name = wcsrchr(path, L'\\');
    return name && _wcsicmp(name + 1, L"MySimsKingdom.exe") == 0;
}
static bool supported(const wchar_t* path) {
    static const unsigned char expected[32] = {
        0xf7,0xad,0x84,0xb5,0xd5,0xda,0xc7,0x3e,0xe4,0xe7,0x77,0x59,0x03,0x24,0xd9,0x9e,
        0x5a,0x6e,0x1f,0x2b,0x0c,0x0c,0xfd,0xa6,0x9c,0x44,0x8e,0x50,0xb9,0x49,0x5b,0x2a};
    HANDLE file = CreateFileW(path, GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
                              nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (file == INVALID_HANDLE_VALUE) return false;
    BCRYPT_ALG_HANDLE alg = nullptr; BCRYPT_HASH_HANDLE hash = nullptr;
    unsigned char digest[32], buffer[65536]; DWORD got = 0;
    bool ok = BCryptOpenAlgorithmProvider(&alg, BCRYPT_SHA256_ALGORITHM, nullptr, 0) >= 0;
    if (ok) ok = BCryptCreateHash(alg, &hash, nullptr, 0, nullptr, 0, 0) >= 0;
    while (ok) {
        if (!ReadFile(file, buffer, sizeof(buffer), &got, nullptr)) { ok = false; break; }
        if (!got) break;
        ok = BCryptHashData(hash, buffer, got, 0) >= 0;
    }
    if (ok) ok = BCryptFinishHash(hash, digest, sizeof(digest), 0) >= 0 && memcmp(digest, expected, 32) == 0;
    if (hash) BCryptDestroyHash(hash);
    if (alg) BCryptCloseAlgorithmProvider(alg, 0);
    CloseHandle(file); return ok;
}
struct Vector { uintptr_t first, end, limit; };
static bool vectorAt(uintptr_t p, Vector& v) {
    return get(p, v) && v.first >= 0x10000 && v.first <= v.end && v.end <= v.limit &&
           v.limit - v.first <= 262144 && ((v.first | v.end | v.limit) & 3) == 0;
}
static bool contains(const Vector& v, uint32_t handle) {
    std::vector<uint32_t> entries((v.end - v.first) / 4);
    return read(v.first, entries.data(), entries.size() * 4) &&
           std::find(entries.begin(), entries.end(), handle) != entries.end();
}
struct Target {
    uintptr_t cat{}, world{}, transform{}, vector{};
    uint32_t handle{};
    bool operator==(const Target& b) const {
        return cat == b.cat && world == b.world && transform == b.transform && vector == b.vector && handle == b.handle;
    }
};
static bool findTarget(Target& t) {
    if (value<uint32_t>(base + 0xae9908) != 0xee4d5fe7) return false;
    uintptr_t table = value<uintptr_t>(base + 0xae9798);
    uint16_t count = value<uint16_t>(base + 0xae97a0);
    if (!count || count > 32768) return false;
    std::vector<uintptr_t> objects(count);
    if (!read(table, objects.data(), objects.size() * 8)) return false;
    for (unsigned i = 0; i < count; ++i) {
        uintptr_t p = objects[i];
        if (!p || p == UINTPTR_MAX || (p & 0x10001) == 0x10001) continue;
        unsigned char data[0x38];
        if (!read(p, data, sizeof(data))) continue;
        uint32_t kind, key, handle;
        memcpy(&kind, data + 0x28, 4); memcpy(&key, data + 0x30, 4); memcpy(&handle, data + 8, 4);
        if (kind == 0x2c2e0959 && key == 0x977da888) {
            if (t.cat || (handle & 0xffff) != i) return false;
            t.cat = p; t.handle = handle;
        }
        if (kind == 0x9b8e862f && key == 0x4036ce55) {
            if (t.world) return false;
            t.world = p;
        }
    }
    if (!t.cat || !t.world) return false;
    t.transform = value<uintptr_t>(t.world + 0x50);
    uintptr_t bounds[2];
    if (!read(t.transform + 0x88, bounds, sizeof(bounds)) || bounds[0] > bounds[1] ||
        bounds[1] - bounds[0] > 65536 || (bounds[1] - bounds[0]) % 16) return false;
    struct Entry { uint32_t key, padding; uintptr_t vector; };
    std::vector<Entry> map((bounds[1] - bounds[0]) / 16);
    if (!read(bounds[0], map.data(), map.size() * 16)) return false;
    uintptr_t herd = 0;
    for (const auto& entry : map) {
        if (entry.key == 0xee4d5fe7) t.vector = entry.vector;
        if (entry.key == 0x2c2e0959) herd = entry.vector;
    }
    Vector h;
    return t.vector && herd && vectorAt(herd, h) && contains(h, t.handle);
}
static bool registerTarget(const Target& t) {
    Vector before, check;
    if (!vectorAt(t.vector, before)) return false;
    if (contains(before, t.handle)) return true;
    if (before.end + 4 > before.limit) return false;
    Target again;
    if (!findTarget(again) || !(again == t) || !get(t.vector, check) || memcmp(&before, &check, sizeof(before))) return false;
    uintptr_t end = before.end + 4;
    if (!write(before.end, &t.handle, 4) || !write(t.vector + 8, &end, 8)) return false;
    if (value<uintptr_t>(t.vector + 8) != end || value<uint32_t>(before.end) != t.handle) return false;
    log("Pet and Feed registered for Ms. Prissykins."); return true;
}

static constexpr uint32_t herdablesKey = 0x2c2e0959;
static constexpr uint32_t homeCatKey = 0x977da888;
static constexpr uint32_t travelCatKey = 0x3279c724; // prissykins_travel_test
static constexpr uint32_t worldKey = 0x9b8e862f;
static constexpr uint32_t homeWorldKey = 0x4036ce55;
static constexpr uint16_t serializableCollection = 0x01;
static constexpr uint16_t readOnlyCollection = 0x04;
static constexpr uint16_t cloneableCollection = 0x20;
static constexpr uint16_t runtimeCollection = 0x800;

struct RefSpec { uint32_t kind, kindCache, collection, collectionCache; };
using CloneCollection = RefSpec*(*)(RefSpec*, RefSpec*, const char*);

static bool cloneTravelCollection(uintptr_t sourceRecord, CloneCollection clone, RefSpec& created) {
    uint16_t flags;
    const uintptr_t flagsAddress = sourceRecord + 0x10;
    if (!sourceRecord || value<uint32_t>(sourceRecord) != homeCatKey ||
        value<uint32_t>(sourceRecord + 8) != herdablesKey || !get(flagsAddress, flags) ||
        (flags & (serializableCollection | readOnlyCollection | cloneableCollection | runtimeCollection))
            != serializableCollection) {
        log("Travel skipped: the original cat collection did not match.");
        return false;
    }

    // The native clone routine needs a cloneable ancestor. For this one call,
    // make the placed cat its own clone template on the Lua game thread.
    const uint16_t temporary = flags | cloneableCollection;
    {
        struct RestoreFlags {
            uintptr_t address;
            uint16_t original;
            ~RestoreFlags() { write(address, &original, sizeof(original)); }
        } restore{flagsAddress, flags};
        if (!write(flagsAddress, &temporary, sizeof(temporary))) {
            log("Travel skipped: could not set the temporary clone flag.");
            return false;
        }
        RefSpec source{herdablesKey, UINT32_MAX, homeCatKey, UINT32_MAX};
        clone(&created, &source, "prissykins_travel_test");
    }
    if (value<uint16_t>(flagsAddress) != flags) {
        log("Travel skipped: could not restore the original cat collection flags.");
        return false;
    }
    if (created.kind != herdablesKey || created.collection != travelCatKey) {
        log("Travel skipped: the game did not create the named cat clone.");
        return false;
    }
    return true;
}

static bool prepareTravelCollection() {
    RefSpec ref{herdablesKey, UINT32_MAX, travelCatKey, UINT32_MAX};
    const uintptr_t db = value<uintptr_t>(base + 0xaee208);
    if (!db) return false;
    const auto resolveClass = reinterpret_cast<uintptr_t(*)(uintptr_t, RefSpec*)>(base + 0x3302f0);
    const auto resolveCollection = reinterpret_cast<uintptr_t(*)(uintptr_t, uintptr_t, uint32_t*)>(base + 0x41c780);
    const uintptr_t kind = resolveClass(db, &ref);
    if (!kind) return false;
    uintptr_t collection = resolveCollection(db, kind, &ref.collection);
    RefSpec created{};
    if (!collection) {
        uint32_t sourceKey[2]{homeCatKey, UINT32_MAX};
        const uintptr_t sourceRecord = resolveCollection(db, kind, sourceKey);
        const auto clone = reinterpret_cast<CloneCollection>(base + 0x41c220);
        if (cloneTravelCollection(sourceRecord, clone, created)) {
            collection = resolveCollection(db, kind, &created.collection);
        }
    }
    uint16_t flags;
    // Only touch our named runtime clone. Keep SpawnObject from cloning it again,
    // and exclude its record from world and save-vault serialization.
    if (collection && value<uint32_t>(collection) == travelCatKey &&
        value<uint32_t>(collection + 8) == herdablesKey &&
        value<uint32_t>(collection + 0xc) == homeCatKey && get(collection + 0x10, flags) &&
        (flags & runtimeCollection) && !(flags & (cloneableCollection | readOnlyCollection))) {
        const uint16_t transient = flags & ~serializableCollection;
        if ((flags == transient || write(collection + 0x10, &transient, sizeof(transient))) &&
            value<uint16_t>(collection + 0x10) == transient) {
            log("Travelling collection ready; serialization disabled.");
            return true;
        }
    }
    if (created.kind == herdablesKey && created.collection == travelCatKey) {
        const auto release = reinterpret_cast<void(*)(RefSpec*)>(base + 0x41ecb0);
        release(&created);
    }
    log("Travel skipped: could not verify a transient cat collection.");
    return false;
}

static bool setTravelInteractable(uintptr_t cat, uintptr_t world, bool add) {
    if (!cat || !world || value<uint32_t>(cat + 0x28) != herdablesKey ||
        value<uint32_t>(cat + 0x30) != travelCatKey || value<uint32_t>(world + 0x28) != worldKey ||
        value<uint32_t>(world + 0x30) == homeWorldKey) return false;
    const auto parent = reinterpret_cast<uintptr_t(*)(uintptr_t)>(base + 0x33ad50);
    if (parent(cat) != world) return false;
    const uintptr_t transform = value<uintptr_t>(world + 0x50);
    const uintptr_t table = value<uintptr_t>(base + 0xae9798);
    uint32_t handle = value<uint32_t>(cat + 8);
    const auto slot = static_cast<uint16_t>(handle);
    if (!transform || !slot || !(handle >> 16) || slot >= value<uint16_t>(base + 0xae97a0) ||
        value<uintptr_t>(table + slot * sizeof(uintptr_t)) != cat) return false;
    uint64_t key = value<uint64_t>(base + 0xae9908);
    if (static_cast<uint32_t>(key) != 0xee4d5fe7) return false;

    // Stock helpers maintain sorted handles and allocate a missing filter on
    // demand. Lua invokes them on the game thread, outside the proxy worker.
    const auto edit = reinterpret_cast<void(*)(uintptr_t, uint32_t*, uint64_t*)>(
        base + (add ? 0x33ca80 : 0x33cf60));
    edit(transform + 0x88, &handle, &key);
    if (add) log("Pet and Feed registered for the travelling Ms. Prissykins.");
    return true;
}

static constexpr uintptr_t collectionExistsRva = 0x496da0;

// Retail initializes its own Lua libraries and omits package.loadlib. Reserve
// a private request on the Luattrib broker and forward every stock query.
static int travelBinding(void* lua) {
    const auto getTop = reinterpret_cast<int(*)(void*)>(base + 0x27b060);
    const auto type = reinterpret_cast<int(*)(void*, int)>(base + 0x27c670);
    const auto stringAt = reinterpret_cast<const char*(*)(void*, int, size_t*)>(base + 0x27c420);
    const auto original = reinterpret_cast<int(*)(void*)>(base + collectionExistsRva);
    const int argc = getTop(lua);
    if (argc < 3 || type(lua, 2) != 4 || type(lua, 3) != 4) return original(lua);
    size_t kindLength, keyLength;
    const char* kind = stringAt(lua, 2, &kindLength);
    const char* key = stringAt(lua, 3, &keyLength);
    static constexpr char bridgeKey[] = "prissykins_native_bridge";
    if (kindLength != sizeof("herdables") - 1 || memcmp(kind, "herdables", kindLength) ||
        keyLength != sizeof(bridgeKey) - 1 || memcmp(key, bridgeKey, keyLength)) return original(lua);

    bool ok = false;
    if (argc == 3) {
        ok = prepareTravelCollection();
    } else if (argc == 4 && type(lua, 4) == 4) {
        size_t length;
        const char* stage = stringAt(lua, 4, &length);
        char message[160];
        snprintf(message, sizeof(message), "Travel: %.*s", (int)(std::min)(length, size_t{128}), stage);
        log(message);
        ok = true;
    } else if (argc == 5 || argc == 6) {
        const auto getObject = reinterpret_cast<uintptr_t(*)(void*, int)>(base + 0x3c6e00);
        const uintptr_t cat = getObject(lua, 4);
        const uintptr_t world = getObject(lua, 5);
        ok = setTravelInteractable(cat, world, argc == 5);
        if (!ok) log("Travel: interaction filter rejected the cat or world.");
    }
    if (!ok) return 0;
    const auto pushInteger = reinterpret_cast<void(*)(void*, intptr_t)>(base + 0x27b7e0);
    pushInteger(lua, 1);
    return 1;
}

static bool installTravelBinding() {
    const uintptr_t slot = base + 0xac98a8;
    const uintptr_t original = base + collectionExistsRva;
    if (value<uintptr_t>(slot - sizeof(uintptr_t)) != base + 0x927560 ||
        value<uintptr_t>(slot) != original) return false;
    DWORD oldProtection;
    if (!VirtualProtect((void*)slot, sizeof(uintptr_t), PAGE_READWRITE, &oldProtection)) return false;
    const auto replaced = InterlockedCompareExchangePointer(
        (void* volatile*)slot, (void*)&travelBinding, (void*)original);
    DWORD ignored;
    VirtualProtect((void*)slot, sizeof(uintptr_t), oldProtection, &ignored);
    return replaced == (void*)original;
}
struct SoundRow { uint32_t key, bank, count; int32_t last; };
struct Voice { uint32_t playing, pad; uintptr_t sound; uint64_t owner, identity; };
struct Seen { uint64_t identity{}, since{}; bool handled{}; };
class Sounds {
    uintptr_t manager{}, names{}, settings{};
    uintptr_t rows[2]{};
    uint32_t keys[2]{0x479c95c0, 0x46c8d125}, banks[2]{253,250};
    std::array<Seen,256> seen{};
    size_t next{};
public:
    void tick(uint64_t now) {
        uintptr_t m = value<uintptr_t>(base + 0xae97a8);
        if (!m || value<uintptr_t>(m) != base + 0x910820 || value<uint32_t>(m + 0x50) != 5837 || value<uint32_t>(m + 0x60) != 5837) return;
        uintptr_t n = value<uintptr_t>(m + 0x48), s = value<uintptr_t>(m + 0x58);
        if (m != manager || n != names || s != settings) {
            std::vector<SoundRow> table(5837);
            if (!read(n, table.data(), table.size() * 16)) return;
            uintptr_t found[2]{};
            for (size_t i = 0; i < table.size(); ++i)
                for (int k = 0; k < 2; ++k) if (table[i].key == keys[k]) {
                    if (found[k] || table[i].bank != banks[k] || table[i].count != 2) return;
                    found[k] = n + i * 16;
                }
            if (!found[0] || !found[1]) return;
            manager=m; names=n; settings=s; rows[0]=found[0]; rows[1]=found[1]; seen={}; next=0;
            log("Cat sound variation ready.");
        }
        unsigned char slots[48 * 0x70];
        if (!read(manager + 0x68, slots, sizeof(slots))) return;
        for (unsigned slot = 0; slot < 48; ++slot) {
            Voice voice; memcpy(&voice, slots + slot * 0x70, sizeof(voice));
            if (!voice.playing || voice.playing == UINT32_MAX || !voice.identity) continue;
            for (int k = 0; k < 2; ++k) {
                if (voice.sound != settings + banks[k] * 56ULL) continue;
                Seen* entry=nullptr;
                for (auto& old : seen) if (old.identity == voice.identity) { entry=&old; break; }
                if (!entry) { seen[next] = {voice.identity,now,false}; next=(next+1)%seen.size(); continue; }
                if (entry->handled || now - entry->since < 80) continue;
                uintptr_t address=manager+0x68+slot*0x70;
                Voice live; SoundRow row, check;
                if (!get(address,live) || memcmp(&live,&voice,sizeof(voice)) || !get(rows[k],row)) continue;
                if (row.key != keys[k] || row.bank != banks[k] || row.count != 2 || row.last < 0 || row.last > 1) continue;
                if (!get(address,live) || memcmp(&live,&voice,sizeof(voice)) || !get(rows[k],check) || memcmp(&row,&check,sizeof(row))) continue;
                int32_t alternate=1-row.last;
                if (write(rows[k]+12,&alternate,4)) {
                    entry->handled=true;
                    log(k == 0 ? "Pet: alternate recording prepared." : "Feed: alternate recording prepared.");
                }
            }
        }
    }
};

static DWORD WINAPI worker(void*) {
    wchar_t path[MAX_PATH];
    if (!gamePath(path)) return 0;
    wchar_t logPath[MAX_PATH]; wcscpy(logPath,path);
    wchar_t* tail=wcsrchr(logPath,L'\\');
    if (!tail || tail-logPath + 22 >= MAX_PATH) return 0;
    wcscpy(tail+1,L"PrissykinsProxy.log");
    logFile=CreateFileW(logPath,GENERIC_WRITE,FILE_SHARE_READ|FILE_SHARE_WRITE,nullptr,CREATE_ALWAYS,FILE_ATTRIBUTE_NORMAL,nullptr);
    log("Proxy loaded.");
    if (!gameVerified) { log("Unsupported executable: mod disabled; system WinMM forwarding remains active."); if(logFile!=INVALID_HANDLE_VALUE)CloseHandle(logFile); logFile=INVALID_HANDLE_VALUE; return 0; }
    // Static game imports normally retain this DLL. Pin it explicitly so a loader
    // cannot unload worker code while it is in use. It dies with the game process.
    HMODULE pinned;
    if (!GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS|GET_MODULE_HANDLE_EX_FLAG_PIN,(LPCWSTR)&worker,&pinned)) return 0;
    log(travelBound ? "Travel broker bound." : "Travel disabled: the broker entry did not match.");
    wchar_t mutexName[96]; swprintf(mutexName,96,L"Local\\PrissykinsSoundVariation-%lu",GetCurrentProcessId());
    HANDLE mutex=CreateMutexW(nullptr,TRUE,mutexName);
    bool ownSounds=mutex && GetLastError()!=ERROR_ALREADY_EXISTS;
    log(ownSounds ? "Supported build. Automatic registration and sound variation enabled." : "Supported build. Automatic registration enabled; another sound helper is active.");
    try {
        Target pending{}; uint64_t stableSince=0, nextSearch=0;
        Sounds sounds;
        for (;;) {
            uint64_t now=GetTickCount64();
            if (now>=nextSearch) {
                nextSearch=now+500;
                Target current{};
                if (!findTarget(current)) { pending={}; stableSince=0; }
                else if (!(current==pending)) { pending=current; stableSince=now; }
                else if (now-stableSince>=1000) registerTarget(current);
            }
            if (ownSounds) sounds.tick(now);
            Sleep(20);
        }
    } catch (...) { log("Mod worker stopped after an internal error. Game forwarding remains active."); }
    if (ownSounds) ReleaseMutex(mutex);
    if (mutex) CloseHandle(mutex);
    if(logFile!=INVALID_HANDLE_VALUE)CloseHandle(logFile); logFile=INVALID_HANDLE_VALUE;
    return 0;
}

static BOOL CALLBACK loadOriginal(PINIT_ONCE, PVOID, PVOID*) {
    wchar_t path[MAX_PATH]; UINT n=GetSystemDirectoryW(path,MAX_PATH);
    if (!n || n+11>=MAX_PATH) return FALSE;
    wcscat(path,L"\\winmm.dll");
    HMODULE original=LoadLibraryExW(path,nullptr,LOAD_LIBRARY_SEARCH_SYSTEM32);
    if (!original || original==selfModule) return FALSE;
    if (gamePath(path)) {
        base = (uintptr_t)GetModuleHandleW(nullptr);
        gameVerified = supported(path);
        if (gameVerified) travelBound = installTravelBinding();
    }
    for(unsigned i=0;i<ExportCount;++i) {
        FARPROC p=GetProcAddress(original,ExportNames[i] ? ExportNames[i] : MAKEINTRESOURCEA(ExportOrdinals[i]));
        InterlockedExchangePointer((void* volatile*)&g_targets[i],(void*)p);
    }
    return TRUE;
}
extern "C" void* resolveWinmm(unsigned index) {
    if (index>=ExportCount || !InitOnceExecuteOnce(&forwardOnce,loadOriginal,nullptr,nullptr) || !g_targets[index]) {
        SetLastError(ERROR_PROC_NOT_FOUND); RaiseFailFastException(nullptr,nullptr,0); return nullptr;
    }
    if (InterlockedCompareExchange(&workerStarted,1,0)==0) {
        wchar_t path[MAX_PATH];
        if (gamePath(path)) { HANDLE thread=CreateThread(nullptr,0,worker,nullptr,0,nullptr); if(thread)CloseHandle(thread); }
    }
    return g_targets[index];
}
BOOL WINAPI DllMain(HINSTANCE instance,DWORD reason,LPVOID) {
    if(reason==DLL_PROCESS_ATTACH) { selfModule=instance; DisableThreadLibraryCalls(instance); }
    return TRUE;
}
