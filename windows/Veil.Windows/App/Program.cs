using System.IO.Pipes;
using System.Windows;

namespace Veil;

public static class Program
{
    const string PipeName = "VeilBrowserPipe";

    [STAThread]
    public static int Main(string[] args)
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
            try { File.AppendAllText(System.IO.Path.Combine(Veil.Core.Paths.DataDir, "error.log"), DateTime.Now + "\n" + e.Exception + "\n\n"); } catch { }
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
