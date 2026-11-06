using System.Text.Json;
using System.Text.Json.Nodes;

namespace Veil.Core;

public static class Paths
{
    public static readonly string DataDir = Init();
    static string Init()
    {
        var d = System.IO.Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "Veil");
        Directory.CreateDirectory(d);
        return d;
    }
    public static string WebViewDir => System.IO.Path.Combine(DataDir, "WebView2");
    public static string ListsDir
    {
        get { var d = System.IO.Path.Combine(DataDir, "lists"); Directory.CreateDirectory(d); return d; }
    }
    public static string DefaultDownloads =>
        System.IO.Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "Downloads");
}

/// Tiny thread-safe, debounced, atomically written JSON file.
public sealed class JsonStore<T> where T : class
{
    public static readonly JsonSerializerOptions Opt = new() { PropertyNamingPolicy = JsonNamingPolicy.CamelCase };
    readonly string file;
    readonly object gate = new();
    T value;
    Timer timer;

    public JsonStore(string name, Func<T> make)
    {
        file = System.IO.Path.Combine(Paths.DataDir, name + ".json");
        try { if (File.Exists(file)) value = JsonSerializer.Deserialize<T>(File.ReadAllText(file), Opt); } catch { }
        value ??= make();
    }

    public T Value
    {
        get { lock (gate) return value; }
        set { lock (gate) this.value = value; Schedule(); }
    }

    public void Mutate(Action<T> body) { lock (gate) body(value); Schedule(); }

    void Schedule()
    {
        lock (gate) { timer?.Dispose(); timer = new Timer(_ => Flush(), null, 500, Timeout.Infinite); }
    }

    public void Flush()
    {
        string json;
        lock (gate) { timer?.Dispose(); timer = null; json = JsonSerializer.Serialize(value, Opt); }
        try
        {
            var tmp = file + ".tmp";
            File.WriteAllText(tmp, json);
            File.Move(tmp, file, true);
        }
        catch { }
    }
}

/// All settings live in one JSON object seeded from settings-defaults.json, so the settings page
/// (which reads/writes by key) works exactly as it does on macOS.
public sealed class SettingsStore
{
    readonly JsonStore<JsonObject> store;
    readonly object gate = new();

    public SettingsStore()
    {
        var defaults = JsonNode.Parse(Res.Text("settings-defaults.json")).AsObject();
        store = new JsonStore<JsonObject>("settings", () => JsonNode.Parse(defaults.ToJsonString()).AsObject());
        store.Mutate(o =>
        {
            foreach (var kv in defaults)
                if (!o.ContainsKey(kv.Key)) o[kv.Key] = JsonNode.Parse(kv.Value.ToJsonString());
            if (o["newTab"] is JsonObject nt && defaults["newTab"] is JsonObject dnt)
                foreach (var kv in dnt)
                    if (!nt.ContainsKey(kv.Key)) nt[kv.Key] = JsonNode.Parse(kv.Value.ToJsonString());
        });
    }

    JsonNode Get(string k) { lock (gate) return store.Value[k]; }
    public bool Bool(string k) => Get(k) is JsonValue v && v.TryGetValue<bool>(out var b) && b;
    public string Str(string k) => Get(k) is JsonValue v && v.TryGetValue<string>(out var s) ? s : "";
    public int Int(string k)
    {
        if (Get(k) is JsonValue v)
        {
            if (v.TryGetValue<int>(out var i)) return i;
            if (v.TryGetValue<double>(out var d)) return (int)d;
        }
        return 0;
    }
    public List<string> List(string k) =>
        Get(k) is JsonArray a ? a.Select(x => x?.GetValue<string>() ?? "").ToList() : new List<string>();
    public bool ListEnabled(string id, bool defaultOn) =>
        Get("enabledLists") is JsonObject o && o[id] is JsonValue v && v.TryGetValue<bool>(out var b) ? b : defaultOn;
    public string Json() { lock (gate) return store.Value.ToJsonString(); }
    public JsonNode NewTab() => JsonNode.Parse(Get("newTab").ToJsonString());

    static System.Text.Json.JsonValueKind Kind(JsonNode n)
    {
        var k = n.GetValueKind();
        return k == System.Text.Json.JsonValueKind.False ? System.Text.Json.JsonValueKind.True : k;
    }

    public bool Set(string key, JsonNode value)
    {
        lock (gate)
        {
            var o = store.Value;
            if (!o.ContainsKey(key) || o[key] == null || value == null) return false;
            if (Kind(o[key]) != Kind(value)) return false;
        }
        var copy = JsonNode.Parse(value.ToJsonString());
        store.Mutate(o => o[key] = copy);
        return true;
    }

    public void Flush() => store.Flush();
}

public static class Res
{
    public static string Text(string name)
    {
        using var s = typeof(Res).Assembly.GetManifestResourceStream(name)
            ?? throw new InvalidOperationException("Missing resource " + name);
        using var r = new StreamReader(s);
        return r.ReadToEnd();
    }
}
