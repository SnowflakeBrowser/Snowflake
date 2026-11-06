using System.IO.Pipes;
using System.Windows;

namespace Veil;

public static class Program
{
    const string PipeName = "VeilBrowserPipe";
    static int shown;

    // Writes the error to %APPDATA%\Veil\error.log and shows it in a message box (first few only).
    static void Report(string where, Exception ex)
    {
        try
        {
            var dir = System.IO.Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "Veil");
            Directory.CreateDirectory(dir);
            File.AppendAllText(System.IO.Path.Combine(dir, "error.log"), DateTime.Now + " [" + where + "]\n" + ex + "\n\n");
        }
        catch { }
        if (Interlocked.Increment(ref shown) <= 3)
        {
            try { MessageBox.Show(where + ":\n\n" + ex, "Veil error"); } catch { }
        }
    }

    [STAThread]
    public static int Main(string[] args)
    {
        AppDomain.CurrentDomain.UnhandledException += (s, e) =>
            Report("Crash", e.ExceptionObject as Exception ?? new Exception(e.ExceptionObject?.ToString()));
        try { return Run(args); }
        catch (Exception ex) { Report("Startup", ex); return 1; }
    }

    static int Run(string[] args)
    {
        var url = args.FirstOrDefault(a => !a.StartsWith("-"));
        using var mutex = new Mutex(true, @"Local\Veil.Browser.SingleInstance", out bool first);
        if (!first)
        {
            // Another Veil is already running: hand it the link and exit.
            try
            {
                using var c = new NamedPipeClientStream(".", PipeName, PipeDirection.Out);
                c.Connect(3000);
                using var w = new StreamWriter(c) { AutoFlush = true };
                w.WriteLine(url ?? "");
            }
            catch { }
            return 0;
        }

        Services.Init();
        var app = new Application { ShutdownMode = ShutdownMode.OnMainWindowClose };
        app.DispatcherUnhandledException += (s, e) =>
        {
            Report("Error", e.Exception);
            e.Handled = true;
        };
        var win = new MainWindow(url);
        StartPipeServer(win);
        return app.Run(win);
    }

    static void StartPipeServer(MainWindow win)
    {
        new Thread(() =>
        {
            while (true)
            {
                try
                {
                    using var s = new NamedPipeServerStream(PipeName, PipeDirection.In);
                    s.WaitForConnection();
                    using var r = new StreamReader(s);
                    var line = r.ReadLine() ?? "";
                    win.Dispatcher.BeginInvoke(new Action(() => win.OpenExternal(line)));
                }
                catch { Thread.Sleep(250); }
            }
        }) { IsBackground = true }.Start();
    }
}
