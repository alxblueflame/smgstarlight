param(
    [int] $RunSeconds = 45
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

public static class CrashCatcher
{
    [StructLayout(LayoutKind.Sequential)]
    struct STARTUPINFO { public int cb; public IntPtr r1, r2, r3; public int dwX, dwY, dwXSize, dwYSize, dwXCount, dwYCount, dwFill; public int dwFlags; public short wShow, cbR2; public IntPtr lpR2, hIn, hOut, hErr; }
    [StructLayout(LayoutKind.Sequential)]
    struct PROCESS_INFORMATION { public IntPtr hProcess, hThread; public int dwProcessId, dwThreadId; }
    [StructLayout(LayoutKind.Sequential)]
    struct EXCEPTION_RECORD64 { public uint ExceptionCode, ExceptionFlags; public ulong ExceptionRecord, ExceptionAddress; public uint NumberParameters, pad; [MarshalAs(UnmanagedType.ByValArray, SizeConst = 15)] public ulong[] ExceptionInformation; }
    [StructLayout(LayoutKind.Sequential)]
    struct EXCEPTION_DEBUG_INFO { public EXCEPTION_RECORD64 ExceptionRecord; public uint dwFirstChance; }
    [StructLayout(LayoutKind.Sequential)]
    struct DEBUG_EVENT { public uint dwDebugEventCode, dwProcessId, dwThreadId; public EXCEPTION_DEBUG_INFO Exception; [MarshalAs(UnmanagedType.ByValArray, SizeConst = 128)] public byte[] pad; }

    [StructLayout(LayoutKind.Sequential, Pack = 16)]
    struct CONTEXT64
    {
        public ulong P1Home, P2Home, P3Home, P4Home, P5Home, P6Home;
        public uint ContextFlags, MxCsr;
        public ushort SegCs, SegDs, SegEs, SegFs, SegGs, SegSs;
        public uint EFlags;
        public ulong Dr0, Dr1, Dr2, Dr3, Dr6, Dr7;
        public ulong Rax, Rcx, Rdx, Rbx, Rsp, Rbp, Rsi, Rdi, R8, R9, R10, R11, R12, R13, R14, R15, Rip;
        [MarshalAs(UnmanagedType.ByValArray, SizeConst = 122)] public ulong[] rest;
    }

    [DllImport("kernel32.dll", SetLastError = true)] static extern bool CreateProcess(string app, string cmd, IntPtr pa, IntPtr ta, bool inherit, uint flags, IntPtr env, string cwd, ref STARTUPINFO si, out PROCESS_INFORMATION pi);
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool WaitForDebugEvent(ref DEBUG_EVENT ev, uint ms);
    [DllImport("kernel32.dll")] static extern bool ContinueDebugEvent(uint pid, uint tid, uint status);
    [DllImport("kernel32.dll")] static extern bool TerminateProcess(IntPtr h, uint code);
    [DllImport("kernel32.dll")] static extern IntPtr OpenThread(uint access, bool inherit, uint tid);
    [DllImport("kernel32.dll")] static extern bool GetThreadContext(IntPtr h, ref CONTEXT64 ctx);
    [DllImport("kernel32.dll")] static extern bool ReadProcessMemory(IntPtr h, ulong addr, byte[] buf, int size, out IntPtr read);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
    [DllImport("psapi.dll")] static extern bool EnumProcessModulesEx(IntPtr h, [Out] IntPtr[] mods, int cb, out int needed, uint filter);
    [DllImport("psapi.dll", CharSet = CharSet.Unicode)] static extern uint GetModuleFileNameEx(IntPtr h, IntPtr mod, StringBuilder name, int size);
    [DllImport("psapi.dll")] static extern bool GetModuleInformation(IntPtr h, IntPtr mod, out MODULEINFO info, int cb);
    [StructLayout(LayoutKind.Sequential)] struct MODULEINFO { public IntPtr lpBaseOfDll; public uint SizeOfImage; public IntPtr EntryPoint; }

    const uint DEBUG_ONLY_THIS_PROCESS = 0x00000002;
    const uint EXCEPTION_DEBUG_EVENT = 1, EXIT_PROCESS_DEBUG_EVENT = 5;
    const uint DBG_CONTINUE = 0x00010002, DBG_EXCEPTION_NOT_HANDLED = 0x80010001;
    const uint CONTEXT_FULL64 = 0x10000B;

    public static void Run(string exe, string args, string cwd, int timeoutSeconds)
    {
        var si = new STARTUPINFO(); si.cb = Marshal.SizeOf(typeof(STARTUPINFO));
        PROCESS_INFORMATION pi;
        if (!CreateProcess(exe, "\"" + exe + "\" " + args, IntPtr.Zero, IntPtr.Zero, false, DEBUG_ONLY_THIS_PROCESS, IntPtr.Zero, cwd, ref si, out pi))
            throw new Exception("CreateProcess failed: " + Marshal.GetLastWin32Error());
        Console.WriteLine("debuggee pid=" + pi.dwProcessId);
        var deadline = DateTime.UtcNow.AddSeconds(timeoutSeconds + 30);
        long firstChanceCount = 0;
        var firstChanceCodes = new Dictionary<uint, long>();
        while (DateTime.UtcNow < deadline)
        {
            var ev = new DEBUG_EVENT();
            if (!WaitForDebugEvent(ref ev, 2000))
                continue;
            uint status = DBG_CONTINUE;
            if (ev.dwDebugEventCode == EXIT_PROCESS_DEBUG_EVENT)
            {
                Console.WriteLine("process exited normally");
                ContinueDebugEvent(ev.dwProcessId, ev.dwThreadId, DBG_CONTINUE);
                break;
            }
            if (ev.dwDebugEventCode == EXCEPTION_DEBUG_EVENT)
            {
                var rec = ev.Exception.ExceptionRecord;
                if (ev.Exception.dwFirstChance != 0)
                {
                    firstChanceCount++;
                    long n; firstChanceCodes.TryGetValue(rec.ExceptionCode, out n); firstChanceCodes[rec.ExceptionCode] = n + 1;
                    status = DBG_EXCEPTION_NOT_HANDLED;  // let the app's VEH (fastmem backpatch) handle it
                }
                else
                {
                    Console.WriteLine("=== FATAL second-chance exception ===");
                    Console.WriteLine(string.Format("code=0x{0:X8} address=0x{1:X16} thread={2}", rec.ExceptionCode, rec.ExceptionAddress, ev.dwThreadId));
                    if (rec.NumberParameters >= 2 && rec.ExceptionInformation != null)
                        Console.WriteLine(string.Format("access: {0} at 0x{1:X16}", rec.ExceptionInformation[0] == 1 ? "write" : rec.ExceptionInformation[0] == 0 ? "read" : "exec", rec.ExceptionInformation[1]));
                    var th = OpenThread(0x1F03FF, false, ev.dwThreadId);
                    var ctx = new CONTEXT64(); ctx.rest = new ulong[122]; ctx.ContextFlags = CONTEXT_FULL64;
                    if (GetThreadContext(th, ref ctx))
                    {
                        Console.WriteLine(string.Format("RIP=0x{0:X16} RSP=0x{1:X16} RBP=0x{2:X16}", ctx.Rip, ctx.Rsp, ctx.Rbp));
                        Console.WriteLine(string.Format("RAX={0:X16} RBX={1:X16} RCX={2:X16} RDX={3:X16}", ctx.Rax, ctx.Rbx, ctx.Rcx, ctx.Rdx));
                        Console.WriteLine(string.Format("RSI={0:X16} RDI={1:X16} R8 ={2:X16} R9 ={3:X16}", ctx.Rsi, ctx.Rdi, ctx.R8, ctx.R9));
                        Console.WriteLine(string.Format("R10={0:X16} R11={1:X16} R12={2:X16} R13={3:X16}", ctx.R10, ctx.R11, ctx.R12, ctx.R13));
                        Console.WriteLine(string.Format("R14={0:X16} R15={1:X16}", ctx.R14, ctx.R15));
                        var code = new byte[48]; IntPtr got;
                        if (ReadProcessMemory(pi.hProcess, ctx.Rip - 16, code, code.Length, out got))
                            Console.WriteLine("code[RIP-16..+32]: " + BitConverter.ToString(code).Replace("-", " "));
                        // Map modules, then scan the stack for return addresses inside modules.
                        var mods = new IntPtr[1024]; int needed;
                        var ranges = new List<Tuple<ulong, ulong, string>>();
                        if (EnumProcessModulesEx(pi.hProcess, mods, mods.Length * IntPtr.Size, out needed, 3))
                        {
                            int count = needed / IntPtr.Size;
                            for (int i = 0; i < count; i++)
                            {
                                MODULEINFO mi;
                                if (GetModuleInformation(pi.hProcess, mods[i], out mi, Marshal.SizeOf(typeof(MODULEINFO))))
                                {
                                    var sb = new StringBuilder(512); GetModuleFileNameEx(pi.hProcess, mods[i], sb, sb.Capacity);
                                    ranges.Add(Tuple.Create((ulong)mi.lpBaseOfDll.ToInt64(), (ulong)mi.lpBaseOfDll.ToInt64() + mi.SizeOfImage, System.IO.Path.GetFileName(sb.ToString())));
                                }
                            }
                        }
                        Func<ulong, string> locate = addr => {
                            foreach (var r in ranges) if (addr >= r.Item1 && addr < r.Item2) return r.Item3 + "+0x" + (addr - r.Item1).ToString("X");
                            return null;
                        };
                        var rip_loc = locate(ctx.Rip);
                        Console.WriteLine("RIP in: " + (rip_loc ?? "<dynamic/JIT memory>"));
                        var stack = new byte[8 * 256];
                        if (ReadProcessMemory(pi.hProcess, ctx.Rsp, stack, stack.Length, out got))
                        {
                            Console.WriteLine("stack module frames:");
                            int printed = 0;
                            for (int i = 0; i < stack.Length / 8 && printed < 24; i++)
                            {
                                ulong v = BitConverter.ToUInt64(stack, i * 8);
                                var loc = locate(v);
                                if (loc != null) { Console.WriteLine(string.Format("  [rsp+0x{0:X4}] 0x{1:X16} {2}", i * 8, v, loc)); printed++; }
                            }
                        }
                    }
                    CloseHandle(th);
                    Console.WriteLine(string.Format("first-chance exceptions before fatal: {0}", firstChanceCount));
                    foreach (var kv in firstChanceCodes)
                        Console.WriteLine(string.Format("  code 0x{0:X8}: {1}", kv.Key, kv.Value));
                    TerminateProcess(pi.hProcess, 0xDEAD);
                    ContinueDebugEvent(ev.dwProcessId, ev.dwThreadId, DBG_CONTINUE);
                    break;
                }
            }
            ContinueDebugEvent(ev.dwProcessId, ev.dwThreadId, status);
        }
        CloseHandle(pi.hProcess); CloseHandle(pi.hThread);
    }
}
'@

$module = (Get-Content C:\SMGRecomp\modules\RMGE01\active-module.txt -Raw).Trim()
$argsLine = "--game C:\SMGRecomp\data\RMGE01 --module `"$module`" --user-dir C:\SMGRecomp\user\RMGE01 --graphics Null --cpu-core static --headless --stop-after-ms $($RunSeconds * 1000)"
[CrashCatcher]::Run('C:\SMGRecomp\build\upstream\moderngekko\moderngekko-run.exe', $argsLine, 'C:\SMGRecomp', $RunSeconds)
