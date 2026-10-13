using System;
using System.Diagnostics;
using System.IO;

namespace AntigravityRemote
{
    class Program
    {
        static int Main(string[] args)
        {
            try
            {
                string appDir = AppDomain.CurrentDomain.BaseDirectory;
                string scriptPath = Path.Combine(appDir, "daemon-bundle.cjs");

                if (!File.Exists(scriptPath))
                {
                    // Fallback to source directory if running in repo
                    string repoScript = Path.Combine(appDir, "..", "daemon", "dist", "daemon-bundle.cjs");
                    if (File.Exists(repoScript))
                    {
                        scriptPath = Path.GetFullPath(repoScript);
                    }
                }

                if (!File.Exists(scriptPath))
                {
                    Console.ForegroundColor = ConsoleColor.Red;
                    Console.WriteLine("[Error] daemon-bundle.cjs not found in " + appDir);
                    Console.ResetColor();
                    return 1;
                }

                string nodeExe = FindNode();
                if (string.IsNullOrEmpty(nodeExe))
                {
                    Console.ForegroundColor = ConsoleColor.Red;
                    Console.WriteLine("[Error] Node.js is required. Please install Node.js (v20+) from https://nodejs.org");
                    Console.ResetColor();
                    return 1;
                }

                ProcessStartInfo psi = new ProcessStartInfo();
                psi.FileName = nodeExe;
                
                string escapedArgs = "\"" + scriptPath + "\"";
                foreach (string arg in args)
                {
                    escapedArgs += " \"" + arg.Replace("\"", "\\\"") + "\"";
                }

                psi.Arguments = escapedArgs;
                psi.UseShellExecute = false;
                psi.WorkingDirectory = appDir;

                Process proc = Process.Start(psi);
                proc.WaitForExit();
                return proc.ExitCode;
            }
            catch (Exception ex)
            {
                Console.ForegroundColor = ConsoleColor.Red;
                Console.WriteLine("[Fatal Error] " + ex.Message);
                Console.ResetColor();
                return 1;
            }
        }

        static string FindNode()
        {
            string[] paths = {
                @"C:\Program Files\nodejs\node.exe",
                @"C:\Program Files (x86)\nodejs\node.exe",
                Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), @"Programs\node\node.exe")
            };

            foreach (string p in paths)
            {
                if (File.Exists(p)) return p;
            }

            // Search PATH
            string pathEnv = Environment.GetEnvironmentVariable("PATH") ?? "";
            foreach (string dir in pathEnv.Split(';'))
            {
                string candidate = Path.Combine(dir.Trim(), "node.exe");
                if (File.Exists(candidate)) return candidate;
            }

            return null;
        }
    }
}
