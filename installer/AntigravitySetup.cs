using System;
using System.IO;
using System.Reflection;
using System.Diagnostics;
using Microsoft.Win32;
using System.Runtime.InteropServices;

namespace AntigravityInstaller
{
    class SetupProgram
    {
        [DllImport("shell32.dll", CharSet = CharSet.Auto)]
        public static extern void SHChangeNotify(int wEventId, int uFlags, IntPtr dwItem1, IntPtr dwItem2);

        static int Main(string[] args)
        {
            Console.Title = "Antigravity Remote Companion - PC Setup";
            Console.ForegroundColor = ConsoleColor.Cyan;
            Console.WriteLine("==============================================================");
            Console.WriteLine("       ANTIGRAVITY REMOTE COMPANION - PC INSTALLER            ");
            Console.WriteLine("==============================================================");
            Console.ResetColor();

            bool silent = false;
            foreach (string arg in args)
            {
                if (arg.Equals("/S", StringComparison.OrdinalIgnoreCase) || arg.Equals("-s", StringComparison.OrdinalIgnoreCase))
                {
                    silent = true;
                }
            }

            try
            {
                string targetDir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "AntigravityRemote");
                Console.WriteLine("\n[1/5] Installing to: " + targetDir);
                if (!Directory.Exists(targetDir))
                {
                    Directory.CreateDirectory(targetDir);
                }

                // Extract embedded files
                Console.WriteLine("[2/5] Deploying host companion daemon and dependencies...");
                ExtractResource("antigravity-daemon.exe", Path.Combine(targetDir, "antigravity-daemon.exe"));
                ExtractResource("daemon-bundle.cjs", Path.Combine(targetDir, "daemon-bundle.cjs"));

                // Create runner batch helpers
                string pairBat = Path.Combine(targetDir, "Pair-Mobile-Device.bat");
                File.WriteAllText(pairBat, "@echo off\r\n\"" + Path.Combine(targetDir, "antigravity-daemon.exe") + "\" --pair\r\npause\r\n");

                string startBat = Path.Combine(targetDir, "Start-Daemon.bat");
                File.WriteAllText(startBat, "@echo off\r\n\"" + Path.Combine(targetDir, "antigravity-daemon.exe") + "\"\r\npause\r\n");

                // Create Desktop & Start Menu Shortcuts
                Console.WriteLine("[3/5] Creating Desktop and Start Menu shortcuts...");
                string desktopDir = Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory);
                string startMenuDir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.StartMenu), "Programs", "Antigravity Remote");
                if (!Directory.Exists(startMenuDir))
                {
                    Directory.CreateDirectory(startMenuDir);
                }

                CreateShortcut(Path.Combine(desktopDir, "Antigravity Remote (Pair Phone).lnk"), Path.Combine(targetDir, "antigravity-daemon.exe"), "--pair", targetDir);
                CreateShortcut(Path.Combine(startMenuDir, "Antigravity Remote (Daemon).lnk"), Path.Combine(targetDir, "antigravity-daemon.exe"), "", targetDir);
                CreateShortcut(Path.Combine(startMenuDir, "Pair Mobile Client (QR).lnk"), Path.Combine(targetDir, "antigravity-daemon.exe"), "--pair", targetDir);
                CreateShortcut(Path.Combine(startMenuDir, "Uninstall Antigravity Remote.lnk"), Path.Combine(targetDir, "uninstall.bat"), "", targetDir);

                // Uninstaller
                Console.WriteLine("[4/5] Registering Windows Add/Remove Programs entry...");
                string uninstallBat = Path.Combine(targetDir, "uninstall.bat");
                string uninstContent = "@echo off\r\n" +
                    "echo Uninstalling Antigravity Remote Companion...\r\n" +
                    "taskkill /F /IM antigravity-daemon.exe 2>nul\r\n" +
                    "del /Q \"" + Path.Combine(desktopDir, "Antigravity Remote (Pair Phone).lnk") + "\" 2>nul\r\n" +
                    "rmdir /S /Q \"" + startMenuDir + "\" 2>nul\r\n" +
                    "reg delete \"HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\AntigravityRemote\" /f 2>nul\r\n" +
                    "echo Files removed. Cleaning up...\r\n" +
                    "(goto) 2>nul & rmdir /S /Q \"" + targetDir + "\" 2>nul\r\n";
                File.WriteAllText(uninstallBat, uninstContent);

                RegisterUninstallEntry(targetDir, uninstallBat);

                // Refresh Windows shell icons
                SHChangeNotify(0x08000000, 0x0000, IntPtr.Zero, IntPtr.Zero);

                Console.ForegroundColor = ConsoleColor.Green;
                Console.WriteLine("\n[5/5] Installation Completed Successfully!");
                Console.ResetColor();

                if (!silent)
                {
                    Console.WriteLine("\nWould you like to start the daemon and view the Mobile Pairing QR code now? (Y/n): ");
                    ConsoleKeyInfo key = Console.ReadKey();
                    Console.WriteLine();
                    if (key.Key != ConsoleKey.N)
                    {
                        ProcessStartInfo psi = new ProcessStartInfo();
                        psi.FileName = Path.Combine(targetDir, "antigravity-daemon.exe");
                        psi.Arguments = "--pair";
                        psi.WorkingDirectory = targetDir;
                        psi.UseShellExecute = false;
                        Process.Start(psi).WaitForExit();
                    }
                }

                return 0;
            }
            catch (Exception ex)
            {
                Console.ForegroundColor = ConsoleColor.Red;
                Console.WriteLine("\n[Setup Error] " + ex.Message);
                Console.ResetColor();
                if (!silent)
                {
                    Console.WriteLine("Press any key to exit...");
                    Console.ReadKey();
                }
                return 1;
            }
        }

        static void ExtractResource(string resourceName, string targetPath)
        {
            Assembly assembly = Assembly.GetExecutingAssembly();
            // Look for resource ending with resourceName
            string foundName = null;
            foreach (string name in assembly.GetManifestResourceNames())
            {
                if (name.EndsWith(resourceName, StringComparison.OrdinalIgnoreCase))
                {
                    foundName = name;
                    break;
                }
            }

            if (foundName == null)
            {
                // Fallback: check if file is alongside setup exe
                string localFile = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, resourceName);
                if (File.Exists(localFile))
                {
                    File.Copy(localFile, targetPath, true);
                    return;
                }
                throw new Exception("Embedded resource not found: " + resourceName);
            }

            using (Stream stream = assembly.GetManifestResourceStream(foundName))
            {
                using (FileStream fs = new FileStream(targetPath, FileMode.Create, FileAccess.Write))
                {
                    stream.CopyTo(fs);
                }
            }
        }

        static void CreateShortcut(string shortcutPath, string targetPath, string arguments, string workingDir)
        {
            try
            {
                Type shellType = Type.GetTypeFromProgID("WScript.Shell");
                if (shellType != null)
                {
                    dynamic shell = Activator.CreateInstance(shellType);
                    dynamic shortcut = shell.CreateShortcut(shortcutPath);
                    shortcut.TargetPath = targetPath;
                    shortcut.Arguments = arguments;
                    shortcut.WorkingDirectory = workingDir;
                    shortcut.Description = "Antigravity Remote Companion Bridge";
                    shortcut.Save();
                }
            }
            catch {}
        }

        static void RegisterUninstallEntry(string targetDir, string uninstallScript)
        {
            try
            {
                using (RegistryKey key = Registry.CurrentUser.CreateSubKey(@"Software\Microsoft\Windows\CurrentVersion\Uninstall\AntigravityRemote"))
                {
                    if (key != null)
                    {
                        key.SetValue("DisplayName", "Antigravity Remote Companion");
                        key.SetValue("DisplayVersion", "1.0.0");
                        key.SetValue("Publisher", "Antigravity");
                        key.SetValue("InstallLocation", targetDir);
                        key.SetValue("UninstallString", "\"" + uninstallScript + "\"");
                        key.SetValue("NoModify", 1, RegistryValueKind.DWord);
                        key.SetValue("NoRepair", 1, RegistryValueKind.DWord);
                    }
                }
            }
            catch {}
        }
    }
}
