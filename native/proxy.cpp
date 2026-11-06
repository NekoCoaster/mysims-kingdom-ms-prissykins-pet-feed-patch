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
    log("Proxy loaded; validating game version.");
    if (!supported(path)) { log("Unsupported executable: mod disabled; system WinMM forwarding remains active."); if(logFile!=INVALID_HANDLE_VALUE)CloseHandle(logFile); logFile=INVALID_HANDLE_VALUE; return 0; }
    // Static game imports normally retain this DLL. Pin it explicitly so a loader
    // cannot unload worker code while it is in use. It dies with the game process.
    HMODULE pinned;
    if (!GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS|GET_MODULE_HANDLE_EX_FLAG_PIN,(LPCWSTR)&worker,&pinned)) return 0;
    base=(uintptr_t)GetModuleHandleW(nullptr);
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
