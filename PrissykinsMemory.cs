using System;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Security.Cryptography;

// Build-specific, data-only registration. No injected code and no save access.
public static class PrissykinsMemory
{
    public const string SupportedSha256 = "F7AD84B5D5DAC73EE4E777590324D99E5A6E1F2B0C0CFDA69C448E50B9495B2A";
    const uint CatClass = 0x2c2e0959, CatKey = 0x977da888;
    const uint WorldClass = 0x9b8e862f, WorldKey = 0x4036ce55;
    const uint Interactable = 0xee4d5fe7;
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern IntPtr OpenProcess(uint access, bool inherit, int pid);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool CloseHandle(IntPtr handle);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool ReadProcessMemory(IntPtr handle, IntPtr address, byte[] buffer, UIntPtr size, out UIntPtr read);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool WriteProcessMemory(IntPtr handle, IntPtr address, byte[] buffer, UIntPtr size, out UIntPtr written);

    sealed class Memory : IDisposable
    {
        readonly IntPtr handle;
        public Memory(int pid, bool checkOnly)
        {
            handle = OpenProcess(checkOnly ? 0x10u : 0x38u, false, pid);
            if (handle == IntPtr.Zero) throw new Exception("Cannot access the game. Run the helper with the same privileges as the game.");
        }
        public byte[] Read(ulong address, int length)
        {
            byte[] data = TryRead(address, length);
            if (data == null) throw new Exception("Cannot read the game state. Wait until the island has finished loading.");
            return data;
        }
        public byte[] TryRead(ulong address, int length)
        {
            if (address < 0x10000 || address > 0x00007fffffffffff || length < 0 || length > 1048576)
                return null;
            byte[] data = new byte[length];
            if (length == 0) return data;
            UIntPtr actual;
            if (!ReadProcessMemory(handle, new IntPtr((long)address), data, (UIntPtr)length, out actual) || actual.ToUInt64() != (ulong)length)
                return null;
            return data;
        }
        public uint U32(ulong address) { return BitConverter.ToUInt32(Read(address, 4), 0); }
        public ulong U64(ulong address) { return BitConverter.ToUInt64(Read(address, 8), 0); }
        public void Write(ulong address, byte[] data)
        {
            UIntPtr actual;
            if (!WriteProcessMemory(handle, new IntPtr((long)address), data, (UIntPtr)data.Length, out actual) || actual.ToUInt64() != (ulong)data.Length)
                throw new Exception("The game memory write failed. Fully restart the game before trying again.");
        }
        public void Dispose() { CloseHandle(handle); }
    }

    static bool Same(byte[] a, byte[] b)
    {
        if (a.Length != b.Length) return false;
        for (int i = 0; i < a.Length; i++) if (a[i] != b[i]) return false;
        return true;
    }
    static byte[] VectorHeader(Memory m, ulong address)
    {
        byte[] header = m.Read(address, 24);
        ulong first = BitConverter.ToUInt64(header, 0), last = BitConverter.ToUInt64(header, 8), limit = BitConverter.ToUInt64(header, 16);
        if (first < 0x10000 || first > last || last > limit || limit - first > 262144 || (first | last | limit) % 4 != 0)
            throw new Exception("Unexpected interaction list; no registration was attempted.");
        return header;
    }
    static bool Contains(Memory m, byte[] header, uint target)
    {
        ulong first = BitConverter.ToUInt64(header, 0), last = BitConverter.ToUInt64(header, 8);
        byte[] list = m.Read(first, checked((int)(last - first)));
        for (int i = 0; i < list.Length; i += 4) if (BitConverter.ToUInt32(list, i) == target) return true;
        return false;
    }

    public static string Run(int pid, bool checkOnly)
    {
        if (IntPtr.Size != 8) throw new Exception("Use 64-bit Windows PowerShell.");
        using (Process process = Process.GetProcessById(pid))
        {
            string executable = process.MainModule.FileName;
            using (SHA256 sha = SHA256.Create())
            using (FileStream file = File.OpenRead(executable))
                if (BitConverter.ToString(sha.ComputeHash(file)).Replace("-", "") != SupportedSha256)
                    throw new Exception("Unsupported game executable. This release supports Steam build 21152538 only. No memory was changed.");
            ulong module = (ulong)process.MainModule.BaseAddress.ToInt64();
            using (Memory m = new Memory(pid, checkOnly))
            {
                if (m.U32(module + 0xae9908) != Interactable) throw new Exception("Unexpected game layout.");
                ulong table = m.U64(module + 0xae9798);
                int count = BitConverter.ToUInt16(m.Read(module + 0xae97a0, 2), 0);
                if (count < 1 || count > 32768) throw new Exception("Unexpected object table.");
                byte[] pointers = m.Read(table, count * 8);
                ulong cat = 0, world = 0;
                uint catHandle = 0;
                for (int i = 0; i < count; i++)
                {
                    ulong obj = BitConverter.ToUInt64(pointers, i * 8);
                    if (obj == 0 || obj == UInt64.MaxValue) continue;
                    // Unused slots contain free-list metadata, not object pointers.
                    byte[] fields = m.TryRead(obj, 0x38);
                    if (fields == null) continue;
                    uint kind = BitConverter.ToUInt32(fields, 0x28), key = BitConverter.ToUInt32(fields, 0x30);
                    if (kind == CatClass && key == CatKey)
                    {
                        if (cat != 0) throw new Exception("More than one matching cat was found.");
                        cat = obj;
                        catHandle = BitConverter.ToUInt32(fields, 8);
                        if ((catHandle & 0xffff) != i) throw new Exception("Cat identity did not match its object slot.");
                    }
                    if (kind == WorldClass && key == WorldKey)
                    {
                        if (world != 0) throw new Exception("More than one matching island was found.");
                        world = obj;
                    }
                }
                if (cat == 0 || world == 0) throw new Exception("Load the island and stand beside Ms. Prissykins, then run this again.");
                ulong transform = m.U64(world + 0x50);
                byte[] mapHeader = m.Read(transform + 0x88, 16);
                ulong mapStart = BitConverter.ToUInt64(mapHeader, 0), mapEnd = BitConverter.ToUInt64(mapHeader, 8);
                if (mapStart > mapEnd || mapEnd - mapStart > 65536 || (mapEnd - mapStart) % 16 != 0)
                    throw new Exception("Unexpected island search list.");
                byte[] map = m.Read(mapStart, (int)(mapEnd - mapStart));
                ulong interactionVector = 0, herdVector = 0;
                for (int i = 0; i < map.Length; i += 16)
                {
                    uint key = BitConverter.ToUInt32(map, i);
                    if (key == Interactable) interactionVector = BitConverter.ToUInt64(map, i + 8);
                    if (key == CatClass) herdVector = BitConverter.ToUInt64(map, i + 8);
                }
                if (interactionVector == 0 || herdVector == 0 || !Contains(m, VectorHeader(m, herdVector), catHandle))
                    throw new Exception("The cat is not registered in this island. Wait for loading to finish.");
                byte[] before = VectorHeader(m, interactionVector);
                if (Contains(m, before, catHandle)) return "Ms. Prissykins is already registered. Pet and Feed should be available beside her.";
                if (checkOnly) return "Ms. Prissykins is present but is not registered for Pet and Feed. No changes made.";
                ulong end = BitConverter.ToUInt64(before, 8), capacity = BitConverter.ToUInt64(before, 16);
                if (end + 4 > capacity) throw new Exception("The interaction list has no spare slot. Nothing was changed.");
                // Recheck immediately before the two small data writes. Run only while idle,
                // beside the cat; never during a load, island transition, or shutdown.
                if (m.U32(cat + 8) != catHandle || m.U32(cat + 0x28) != CatClass || m.U32(cat + 0x30) != CatKey ||
                    !Same(before, m.Read(interactionVector, 24)) || !Same(mapHeader, m.Read(transform + 0x88, 16)))
                    throw new Exception("The island state changed during inspection. Wait until stationary and try again.");
                m.Write(end, BitConverter.GetBytes(catHandle));
                m.Write(interactionVector + 8, BitConverter.GetBytes(end + 4));
                if (m.U64(interactionVector + 8) != end + 4 || m.U32(end) != catHandle)
                    throw new Exception("Registration could not be verified. Fully restart the game before trying again.");
                return "Pet and Feed enabled for Ms. Prissykins in this loaded island. You can close this window.";
            }
        }
    }
}
