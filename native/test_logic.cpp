// Synthetic process-local fixtures. Never attaches to or launches the game.
#include "proxy.cpp"
#include <stdexcept>
static void require(bool ok, const char* why) { if(!ok)throw std::runtime_error(why); }
template<class T> static void put(uintptr_t p,T v) { memcpy((void*)p,&v,sizeof(v)); }
int main() {
    base=(uintptr_t)VirtualAlloc(nullptr,0xaf0000,MEM_RESERVE|MEM_COMMIT,PAGE_READWRITE);
    require(base!=0,"fixture allocation");
    std::array<unsigned char,0x180> cat{},world{},transform{};
    uintptr_t cp=(uintptr_t)cat.data(),wp=(uintptr_t)world.data(),tp=(uintptr_t)transform.data();
    uint32_t handle=0x12340002;
    std::array<uintptr_t,8> objects{};objects[2]=cp;objects[3]=wp;
    put(base+0xae9798,(uintptr_t)objects.data());put<uint16_t>(base+0xae97a0,8);put<uint32_t>(base+0xae9908,0xee4d5fe7);
    put(cp+8,handle);put<uint32_t>(cp+0x28,0x2c2e0959);put<uint32_t>(cp+0x30,0x977da888);
    put<uint32_t>(wp+0x28,0x9b8e862f);put<uint32_t>(wp+0x30,0x4036ce55);put(wp+0x50,tp);
    std::array<uint32_t,4> interaction{123,0,0,0}; uint32_t herdHandle=handle;
    Vector iv{(uintptr_t)interaction.data(),(uintptr_t)interaction.data()+4,(uintptr_t)interaction.data()+16};
    Vector hv{(uintptr_t)&herdHandle,(uintptr_t)&herdHandle+4,(uintptr_t)&herdHandle+4};
    struct E{uint32_t key,pad;uintptr_t v;};
    E map[2]={{0x2c2e0959,0,(uintptr_t)&hv},{0xee4d5fe7,0,(uintptr_t)&iv}};
    put(tp+0x88,(uintptr_t)map);put(tp+0x90,(uintptr_t)map+sizeof(map));
    Target t{};require(findTarget(t),"find exact cat");require(registerTarget(t),"register");
    require(iv.end-iv.first==8&&interaction[1]==handle,"one handle appended");
    require(registerTarget(t)&&iv.end-iv.first==8,"idempotent registration");
    iv.end=iv.first+4;iv.limit=iv.end;
    require(!registerTarget(t)&&iv.end-iv.first==4,"full list rejected");
    iv.limit=iv.first+16;put<uint32_t>(cp+8,0x12340007);t={};
    require(!findTarget(t),"mismatched identity rejected");put(cp+8,handle);
    herdHandle=0;t={};require(!findTarget(t),"wrong island membership rejected");herdHandle=handle;
    std::array<uint32_t,4> fresh{};iv={(uintptr_t)fresh.data(),(uintptr_t)fresh.data(),(uintptr_t)fresh.data()+16};
    t={};require(findTarget(t)&&registerTarget(t)&&fresh[0]==handle,"new island vector registered");

    std::vector<unsigned char> manager(0x1900),settings(5837*56);
    std::vector<SoundRow> rows(5837);
    rows[250]={0x46c8d125,250,2,0};rows[253]={0x479c95c0,253,2,0};
    uintptr_t mp=(uintptr_t)manager.data(),sp=(uintptr_t)settings.data();
    put(base+0xae97a8,mp);put(mp,base+0x910820);put(mp+0x48,(uintptr_t)rows.data());
    put<uint32_t>(mp+0x50,5837);put(mp+0x58,sp);put<uint32_t>(mp+0x60,5837);
    Voice voice{12,0,sp+253*56,0,42};put(mp+0x68,voice);
    Sounds sounds;sounds.tick(100);sounds.tick(179);require(rows[253].last==0,"settling time");
    sounds.tick(180);require(rows[253].last==1,"prepare alternate pet");
    sounds.tick(999);require(rows[253].last==1,"same voice not repeated");
    voice.playing=13;voice.identity=43;put(mp+0x68,voice);
    sounds.tick(1000);sounds.tick(1080);require(rows[253].last==0,"next pet alternates");
    voice.playing=14;voice.identity=44;voice.sound=sp+250*56;put(mp+0x68,voice);
    sounds.tick(1100);sounds.tick(1180);require(rows[250].last==1,"feed alternates independently");
    voice.playing=15;voice.identity=45;voice.sound=sp+251*56;put(mp+0x68,voice);
    sounds.tick(1200);sounds.tick(1400);require(rows[250].last==1&&rows[253].last==0,"other sounds untouched");
    VirtualFree((void*)base,0,MEM_RELEASE);
    puts("PASS: registration, duplicate prevention, capacity/identity/island guards, reload registration, sound settling and alternation, unrelated sounds.");
    return 0;
}
