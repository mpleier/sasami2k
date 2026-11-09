// Single-file launcher for the portable SASAMI2k build.
//
// The build appends a ZIP payload to this stub followed by a 24-byte footer:
//   [0..8)   magic "S2KSFX01"
//   [8..16)  int64 payload offset (from the start of the file)
//   [16..24) int64 payload length
//
// On first run the payload is unpacked next to the executable into
// "SASAMI2k.data" (or %LOCALAPPDATA%\SASAMI2k.data when that folder is not
// writable), a stamp records which payload was unpacked, and the normal
// portable launcher is invoked with the caller's arguments.

using System;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Text;

internal static class Program
{
    private const string Magic = "S2KSFX01";
    private const int FooterSize = 24;
    private const string DataFolderName = "SASAMI2k.data";
    private const string StampName = ".payload-stamp";

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int MessageBoxW(IntPtr hWnd, string text, string caption, uint type);

    private static int Main(string[] args)
    {
        try
        {
            return Run(args);
        }
        catch (Exception ex)
        {
            MessageBoxW(IntPtr.Zero, ex.Message, "SASAMI2k portable", 0x10);
            return 1;
        }
    }

    private static int Run(string[] args)
    {
        string self = Process.GetCurrentProcess().MainModule.FileName;
        long offset, length;
        ReadFooter(self, out offset, out length);

        bool extractOnly = false;
        string targetOverride = null;
        var pass = new System.Collections.Generic.List<string>();

        for (int i = 0; i < args.Length; i++)
        {
            if (string.Equals(args[i], "--s2k-extract-only", StringComparison.OrdinalIgnoreCase))
            {
                extractOnly = true;
            }
            else if (string.Equals(args[i], "--s2k-target", StringComparison.OrdinalIgnoreCase) && i + 1 < args.Length)
            {
                targetOverride = args[++i];
            }
            else
            {
                pass.Add(args[i]);
            }
        }

        string target = targetOverride ?? ChooseTarget(self);
        Directory.CreateDirectory(target);

        string stamp = Path.Combine(target, StampName);
        string want = self.Length + ":" + offset + ":" + length;
        bool upToDate = File.Exists(stamp) && File.ReadAllText(stamp).Trim() == want;

        if (!upToDate)
        {
            Extract(self, offset, length, target);
            File.WriteAllText(stamp, want);
        }

        if (extractOnly)
        {
            return 0;
        }

        return LaunchLauncher(target, pass);
    }

    private static void ReadFooter(string self, out long offset, out long length)
    {
        using (var fs = new FileStream(self, FileMode.Open, FileAccess.Read, FileShare.Read))
        {
            if (fs.Length < FooterSize)
            {
                throw new InvalidDataException("This file is truncated: no embedded payload.");
            }
            fs.Seek(-FooterSize, SeekOrigin.End);
            var footer = new byte[FooterSize];
            ReadExactly(fs, footer, 0, FooterSize);
            string magic = Encoding.ASCII.GetString(footer, 0, 8);
            if (magic != Magic)
            {
                throw new InvalidDataException("No embedded payload found in this executable.");
            }
            offset = BitConverter.ToInt64(footer, 8);
            length = BitConverter.ToInt64(footer, 16);
            if (offset <= 0 || length <= 0 || offset + length > fs.Length)
            {
                throw new InvalidDataException("Embedded payload is corrupt.");
            }
        }
    }

    private static string ChooseTarget(string self)
    {
        string baseDir = Path.GetDirectoryName(self);
        if (!string.IsNullOrEmpty(baseDir) && IsWritable(baseDir))
        {
            return Path.Combine(baseDir, DataFolderName);
        }
        string local = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        return Path.Combine(local, DataFolderName);
    }

    private static bool IsWritable(string dir)
    {
        try
        {
            string probe = Path.Combine(dir, ".s2k-write-probe");
            using (var fs = new FileStream(probe, FileMode.Create, FileAccess.Write, FileShare.None))
            {
                fs.WriteByte(0);
            }
            File.Delete(probe);
            return true;
        }
        catch
        {
            return false;
        }
    }

    private static void Extract(string self, long offset, long length, string target)
    {
        using (var fs = new FileStream(self, FileMode.Open, FileAccess.Read, FileShare.Read))
        {
            var buffer = new byte[length];
            fs.Seek(offset, SeekOrigin.Begin);
            ReadExactly(fs, buffer, 0, (int)length);

            using (var ms = new MemoryStream(buffer, false))
            using (var zip = new ZipArchive(ms, ZipArchiveMode.Read))
            {
                string root = Path.GetFullPath(target + Path.DirectorySeparatorChar);
                foreach (ZipArchiveEntry entry in zip.Entries)
                {
                    string rel = entry.FullName.Replace('/', Path.DirectorySeparatorChar);
                    string dest = Path.GetFullPath(Path.Combine(target, rel));
                    if (!dest.StartsWith(root, StringComparison.OrdinalIgnoreCase))
                    {
                        throw new InvalidDataException("Payload entry escapes the target folder: " + entry.FullName);
                    }
                    if (entry.Name.Length == 0)
                    {
                        Directory.CreateDirectory(dest);
                        continue;
                    }
                    Directory.CreateDirectory(Path.GetDirectoryName(dest));
                    using (Stream src = entry.Open())
                    using (var dst = new FileStream(dest, FileMode.Create, FileAccess.Write, FileShare.None))
                    {
                        src.CopyTo(dst);
                    }
                    try
                    {
                        File.SetLastWriteTimeUtc(dest, entry.LastWriteTime.UtcDateTime);
                    }
                    catch
                    {
                        // timestamps are cosmetic; ignore filesystems that refuse
                    }
                }
            }
        }
    }

    private static int LaunchLauncher(string target, System.Collections.Generic.List<string> playerArgs)
    {
        string powershell = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.System),
            @"WindowsPowerShell\v1.0\powershell.exe");
        string script = Path.Combine(target, @"tools\portable.ps1");
        if (!File.Exists(script))
        {
            throw new FileNotFoundException("The portable launcher is missing from the extracted copy.", script);
        }

        var sb = new StringBuilder();
        sb.Append("-NoProfile -ExecutionPolicy Bypass -File ");
        sb.Append(Quote(script));
        sb.Append(" launch");
        foreach (string a in playerArgs)
        {
            sb.Append(' ');
            sb.Append(Quote(a));
        }

        var psi = new ProcessStartInfo(powershell, sb.ToString())
        {
            WorkingDirectory = target,
            UseShellExecute = false,
            CreateNoWindow = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true
        };

        string logPath = Path.Combine(target, "launch.log");
        using (Process p = Process.Start(psi))
        {
            // Drain both pipes before waiting: the launcher writes only a few lines,
            // but a full pipe would deadlock the child.
            string stdout = p.StandardOutput.ReadToEnd();
            string stderr = p.StandardError.ReadToEnd();
            p.WaitForExit();

            var log = new StringBuilder();
            log.AppendLine("--- " + DateTime.Now.ToString("s")
                           + "  exit=" + p.ExitCode + " ---");
            log.AppendLine("cmd: " + sb);
            if (stdout.Length > 0) { log.AppendLine(stdout); }
            if (stderr.Length > 0) { log.AppendLine("stderr: " + stderr); }
            try { File.AppendAllText(logPath, log.ToString()); } catch { }
            return p.ExitCode;
        }
    }

    private static string Quote(string value)
    {
        return "\"" + value.Replace("\"", "\\\"") + "\"";
    }

    private static void ReadExactly(Stream s, byte[] buffer, int offset, int count)
    {
        int read = 0;
        while (read < count)
        {
            int n = s.Read(buffer, offset + read, count - read);
            if (n <= 0)
            {
                throw new EndOfStreamException("Unexpected end of file.");
            }
            read += n;
        }
    }
}
