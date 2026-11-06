import Foundation
import WebKit

/// Serves veil://newtab, settings, privacy, history, bookmarks, downloads from memory.
/// A strict CSP keeps these pages from loading anything remote.
final class SchemeHandler: NSObject, WKURLSchemeHandler {
    static let shared = SchemeHandler()

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url, let html = Pages.html(for: url.host ?? "") else {
            task.didFailWithError(URLError(.fileDoesNotExist)); return
        }
        let data = Data(html.utf8)
        let headers = [
            "Content-Type": "text/html; charset=utf-8",
            "Content-Length": "\(data.count)",
            "Cache-Control": "no-store",
            "Content-Security-Policy": "default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; img-src data:; form-action 'none'",
        ]
        let resp = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers)!
        task.didReceive(resp)
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}
}

enum Pages {
    static let names = ["newtab", "settings", "privacy", "history", "bookmarks", "downloads"]

    static func html(for name: String) -> String? {
        guard names.contains(name) else { return nil }
        return """
        <!doctype html><html><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width,initial-scale=1">
        <meta name="color-scheme" content="dark light"><title>Veil</title>
        <style>\(css)</style></head>
        <body data-page="\(name)"><div id="app"></div><script>\(script)</script></body></html>
        """
    }

    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }

    static func sourceHTML(url: String, source: String) -> String {
        """
        <!doctype html><html><head><meta charset="utf-8"><meta name="color-scheme" content="dark light">
        <title>Source of \(escape(url))</title><style>\(css)
        body{padding:20px 28px}pre{white-space:pre-wrap;word-break:break-word;font:12px/1.55 ui-monospace,Menlo,monospace;margin:0}
        .src{color:var(--mute);margin-bottom:14px;font-size:12px;word-break:break-all}</style></head>
        <body data-page="source"><div class="src">Source of \(escape(url)) (as the page is now)</div><pre>\(escape(source))</pre></body></html>
        """
    }

    static func errorHTML(heading: String, detail: String, failingURL: String, insecureURL: String?) -> String {
        var button = ""
        if let u = insecureURL,
           let enc = u.addingPercentEncoding(withAllowedCharacters: CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")) {
            button = "<p><a class=\"btn\" href=\"veil://insecure?u=\(enc)\">Continue over http</a></p>"
        }
        return """
        <!doctype html><html><head><meta charset="utf-8"><meta name="color-scheme" content="dark light">
        <style>\(css)</style></head><body data-page="error"><div id="app"><main class="err">
        <h1>\(escape(heading))</h1><p class="mute">\(escape(detail))</p>
        <p class="mute url">\(escape(failingURL))</p>\(button)</main></div></body></html>
        """
    }

    static let css = #"""
    :root{--bg:#131417;--panel:#1b1d22;--line:#292c33;--text:#e5e6ea;--mute:#868b96;--accent:#8fb3c9;--danger:#d98a8a;color-scheme:dark}
    @media (prefers-color-scheme:light){:root{--bg:#f4f4f1;--panel:#fff;--line:#e2e2dd;--text:#1c1d21;--mute:#6b6f79;--accent:#3d6c8a;--danger:#b24a4a;color-scheme:light}}
    *{box-sizing:border-box}html,body{margin:0;min-height:100%}
    body{background:var(--bg);color:var(--text);font:14px/1.5 -apple-system,BlinkMacSystemFont,"SF Pro Text",system-ui,sans-serif;-webkit-font-smoothing:antialiased}
    a{color:inherit;text-decoration:none}.mute{color:var(--mute)}.url{word-break:break-all;font-size:12px}
    #app{display:flex;min-height:100vh}
    nav{width:200px;padding:28px 14px;position:sticky;top:0;height:100vh;display:flex;flex-direction:column;gap:2px;flex:none}
    nav .brand{font-size:15px;font-weight:600;letter-spacing:.02em;padding:0 12px 18px}
    nav a{padding:7px 12px;border-radius:8px;color:var(--mute);transition:background .15s,color .15s}
    nav a:hover{background:var(--panel);color:var(--text)}nav a.on{background:var(--panel);color:var(--text)}
    main{flex:1;max-width:720px;padding:28px 32px 80px}
    h1{font-size:22px;font-weight:600;margin:0 0 22px}h2{font-size:13px;font-weight:600;color:var(--mute);margin:30px 0 8px}
    .card{background:var(--panel);border:1px solid var(--line);border-radius:12px;overflow:visible}
    .row{display:flex;align-items:center;justify-content:space-between;gap:20px;padding:12px 16px;border-top:1px solid var(--line)}
    .row:first-child{border-top:0}.l{font-weight:500}.hint{color:var(--mute);font-size:12.5px;max-width:460px}
    .sw{position:relative;width:38px;height:22px;flex:none}.sw input{opacity:0;position:absolute;inset:0;margin:0;cursor:pointer;z-index:1}
    .sw span{position:absolute;inset:0;background:var(--line);border-radius:11px;transition:background .2s}
    .sw span:after{content:"";position:absolute;left:2px;top:2px;width:18px;height:18px;border-radius:50%;background:#fff;transition:transform .2s}
    .sw input:checked+span{background:var(--accent)}.sw input:checked+span:after{transform:translateX(16px)}
    select,input[type=text],textarea{background:var(--bg);color:var(--text);border:1px solid var(--line);border-radius:8px;padding:7px 10px;font:inherit;outline:none}
    select:focus,input[type=text]:focus,textarea:focus{border-color:var(--accent)}
    textarea{width:100%;min-height:110px;font:12px/1.5 ui-monospace,Menlo,monospace}
    button,.btn{background:var(--panel);color:var(--text);border:1px solid var(--line);border-radius:8px;padding:7px 14px;font:inherit;cursor:pointer;display:inline-block}
    button:hover,.btn:hover{border-color:var(--accent)}button.danger{color:var(--danger)}
    .themes{display:flex;flex-wrap:wrap;gap:10px;justify-content:flex-end;max-width:440px}
    .tsw{background:none;border:0;padding:0;cursor:pointer;text-align:center;color:var(--mute);font:inherit;font-size:11px}
    .tsw .tbar{width:78px;height:36px;border-radius:9px;border:1px solid var(--line);position:relative;margin-bottom:4px}
    .tsw .tbar i{position:absolute;left:8px;top:9px;width:30px;height:14px;border-radius:5px}
    .tsw.on .tbar{box-shadow:0 0 0 2px var(--panel),0 0 0 4px var(--text)}
    .dd{position:relative;display:inline-block}
    .ddb{display:flex;align-items:center;justify-content:space-between;gap:12px;min-width:150px;background:var(--bg);color:var(--text);border:1px solid var(--line);border-radius:8px;padding:7px 10px;font:inherit;cursor:pointer}
    .ddb:hover,.dd.open .ddb{border-color:var(--accent)}
    .caret{color:var(--mute);font-size:11px}
    .ddl{display:none;position:absolute;right:0;top:calc(100% + 4px);min-width:100%;max-height:320px;overflow:auto;background:var(--panel);border:1px solid var(--line);border-radius:10px;padding:4px;z-index:50;box-shadow:0 10px 28px rgba(0,0,0,.35)}
    .dd.open .ddl{display:block}
    .ddi{padding:7px 10px;border-radius:6px;cursor:pointer;white-space:nowrap}
    .ddi:hover{background:var(--bg)}.ddi.on{color:var(--accent)}
    .stats{display:grid;grid-template-columns:repeat(auto-fit,minmax(130px,1fr));gap:10px;margin-bottom:6px}
    .stat{background:var(--panel);border:1px solid var(--line);border-radius:12px;padding:14px 16px}
    .stat b{display:block;font-size:22px;font-weight:600}.stat span{color:var(--mute);font-size:12.5px}
    .item{display:flex;gap:12px;align-items:center;padding:10px 16px;border-top:1px solid var(--line)}.item:first-child{border-top:0}
    .item .t{flex:1;min-width:0}.item .t div{overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
    .bar{height:3px;background:var(--line);border-radius:2px;margin-top:6px}.bar i{display:block;height:100%;background:var(--accent);border-radius:2px}
    .empty{padding:28px 16px;color:var(--mute);text-align:center}.actions{display:flex;gap:8px;margin-top:12px;align-items:center}
    .err{margin:12vh auto;text-align:center;max-width:520px}
    body[data-page=newtab]{--b1:#3b6cff;--b2:#8b5cf6;--b3:#12b5a6;--base:#0a0e1a;--g:rgba(255,255,255,.07);--gb:rgba(255,255,255,.13);--ink:#f2f4f8;--soft:rgba(242,244,248,.64);background:var(--base);color:var(--ink);overflow:hidden}
    body[data-bg=dusk]{--b1:#ff7a59;--b2:#b14cff;--b3:#ff4f8b;--base:#180d1c}
    body[data-bg=forest]{--b1:#1fa971;--b2:#0c7c8c;--b3:#7bd88f;--base:#07130f}
    body[data-bg=ember]{--b1:#ff5a36;--b2:#ffb454;--b3:#c2255c;--base:#150a07}
    body[data-bg=midnight]{--b1:#2a3566;--b2:#1b2547;--b3:#3a2f66;--base:#06070b}
    body[data-bg=plain]{--base:#101114;--g:rgba(255,255,255,.045);--gb:rgba(255,255,255,.11);--ink:#ececef;--soft:rgba(236,236,239,.56)}
    body[data-bg=grain]{--base:#15130f;--g:rgba(255,248,235,.05);--gb:rgba(255,248,235,.12);--ink:#f1ece2;--soft:rgba(241,236,226,.58)}
    .flat{position:fixed;inset:0;z-index:0;pointer-events:none}
    body[data-bg=grain] .flat{opacity:.07;background-image:url("data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' width='160' height='160'><filter id='n'><feTurbulence type='fractalNoise' baseFrequency='.9' numOctaves='2' stitchTiles='stitch'/></filter><rect width='100%25' height='100%25' filter='url(%23n)'/></svg>")}
    body[data-bg=plain] .hello,body[data-bg=grain] .hello{font-size:12px;letter-spacing:.16em;text-transform:uppercase}
    body[data-bg=plain] .clock,body[data-bg=grain] .clock{font-weight:300;letter-spacing:-.035em}
    body[data-bg=plain] .date,body[data-bg=grain] .date{font-size:14px}
    body[data-bg=plain] .sbox input,body[data-bg=grain] .sbox input{border-radius:12px;-webkit-backdrop-filter:none;backdrop-filter:none;background:var(--g);padding:15px 20px 15px 52px;font-size:16px}
    body[data-bg=plain] .sbox input:focus,body[data-bg=grain] .sbox input:focus{box-shadow:none;border-color:var(--accent)}
    body[data-bg=plain] .tile .m:not(.icon),body[data-bg=grain] .tile .m:not(.icon){background:var(--g)!important;box-shadow:inset 0 0 0 1px var(--gb)!important;color:var(--accent);border-radius:14px;font-weight:500}
    body[data-bg=plain] .tile .m.icon,body[data-bg=grain] .tile .m.icon{border-radius:14px;box-shadow:inset 0 0 0 1px var(--gb)}
    body[data-bg=plain] .tile:hover,body[data-bg=grain] .tile:hover{background:none;transform:none}
    body[data-bg=plain] .tile:hover .m,body[data-bg=grain] .tile:hover .m{box-shadow:inset 0 0 0 1px var(--accent)!important}
    body[data-bg=plain] .fun,body[data-bg=grain] .fun{font-style:normal;font-size:12px;letter-spacing:.02em;opacity:.8}
    body[data-bg=plain] #app,body[data-bg=grain] #app{justify-content:flex-start;padding-left:max(9vw,40px)}
    body[data-bg=plain] .nt{align-items:flex-start;width:min(560px,84vw);margin-top:0;animation:none},body[data-bg=grain] .nt{align-items:flex-start;width:min(560px,84vw);margin-top:0;animation:none}
    body[data-bg=plain] .hello,body[data-bg=grain] .hello,body[data-bg=plain] .fun,body[data-bg=grain] .fun{display:none}
    body[data-bg=plain] .clock{font:400 54px/1 ui-monospace,"SF Mono",Menlo,monospace!important;letter-spacing:-.04em;margin:0},body[data-bg=grain] .clock{font:400 54px/1 ui-monospace,"SF Mono",Menlo,monospace!important;letter-spacing:-.04em;margin:0}
    body[data-bg=plain] .date{font:12px ui-monospace,"SF Mono",Menlo,monospace;color:var(--soft);margin-top:10px;text-transform:lowercase;letter-spacing:0},body[data-bg=grain] .date{font:12px ui-monospace,"SF Mono",Menlo,monospace;color:var(--soft);margin-top:10px;text-transform:lowercase;letter-spacing:0}
    body[data-bg=plain] .sbox{margin-top:38px},body[data-bg=grain] .sbox{margin-top:38px}
    body[data-bg=plain] .sbox svg{left:0},body[data-bg=grain] .sbox svg{left:0}
    body[data-bg=plain] .sbox input{border:0;border-bottom:1px solid var(--gb);border-radius:0;background:none;padding:12px 0 12px 30px;font-size:17px},body[data-bg=grain] .sbox input{border:0;border-bottom:1px solid var(--gb);border-radius:0;background:none;padding:12px 0 12px 30px;font-size:17px}
    body[data-bg=plain] .sbox input:focus{border-bottom-color:var(--accent)},body[data-bg=grain] .sbox input:focus{border-bottom-color:var(--accent)}
    body[data-bg=plain] .tiles{margin-top:34px;flex-direction:column;flex-wrap:nowrap;justify-content:flex-start;gap:0;counter-reset:t},body[data-bg=grain] .tiles{margin-top:34px;flex-direction:column;flex-wrap:nowrap;justify-content:flex-start;gap:0;counter-reset:t}
    body[data-bg=plain] .tile{width:100%;flex-direction:row;align-items:center;gap:14px;padding:11px 0;border-radius:0;border-bottom:1px solid var(--gb)},body[data-bg=grain] .tile{width:100%;flex-direction:row;align-items:center;gap:14px;padding:11px 0;border-radius:0;border-bottom:1px solid var(--gb)}
    body[data-bg=plain] .tile:first-child{border-top:1px solid var(--gb)},body[data-bg=grain] .tile:first-child{border-top:1px solid var(--gb)}
    body[data-bg=plain] .tile:before{counter-increment:t;content:counter(t);font:11px ui-monospace,Menlo,monospace;color:var(--soft);width:14px;text-align:right},body[data-bg=grain] .tile:before{counter-increment:t;content:counter(t);font:11px ui-monospace,Menlo,monospace;color:var(--soft);width:14px;text-align:right}
    body[data-bg=plain] .tile .m{width:24px!important;height:24px!important;font-size:12px!important;border-radius:6px!important},body[data-bg=grain] .tile .m{width:24px!important;height:24px!important;font-size:12px!important;border-radius:6px!important}
    body[data-bg=plain] .tile .n{max-width:none;font-size:15px;color:var(--ink)},body[data-bg=grain] .tile .n{max-width:none;font-size:15px;color:var(--ink)}
    body[data-bg=plain] .tile:hover .n{color:var(--accent)},body[data-bg=grain] .tile:hover .n{color:var(--accent)}
    body[data-bg=plain] .tile .x{position:static;margin-left:auto},body[data-bg=grain] .tile .x{position:static;margin-left:auto}
    body[data-bg=plain] .link{margin-top:20px;font:11px ui-monospace,Menlo,monospace;padding:0},body[data-bg=grain] .link{margin-top:20px;font:11px ui-monospace,Menlo,monospace;padding:0}
    .prod{display:flex;gap:12px;flex-wrap:wrap;margin-top:26px;width:100%}
    .pcard{flex:1 1 170px;background:var(--g);border:1px solid var(--gb);border-radius:14px;padding:12px 14px;display:flex;flex-direction:column;gap:8px;text-align:left;min-width:0}
    .pcard.todos,.pcard.notes{flex:2 1 250px}
    .ptitle{font-size:11px;letter-spacing:.12em;text-transform:uppercase;color:var(--soft);display:flex;justify-content:space-between;align-items:center}
    .ftime{font:600 34px/1 ui-monospace,"SF Mono",Menlo,monospace;color:var(--ink)}
    .fbtn{align-self:flex-start;background:var(--accent);color:#111;border:0;border-radius:8px;padding:6px 16px;font:inherit;font-weight:600;cursor:pointer}
    .tlist{display:flex;flex-direction:column;gap:6px;max-height:150px;overflow:auto}
    .titem{display:flex;align-items:center;gap:8px;font-size:14px;color:var(--ink)}
    .titem span{flex:1;overflow-wrap:anywhere}.titem.done span{text-decoration:line-through;opacity:.5}
    .tdel{opacity:.4;cursor:pointer;font-weight:400}.tdel:hover{opacity:1}
    .tclear{cursor:pointer;text-transform:none;letter-spacing:0;font-weight:400}.tclear:hover{color:var(--ink)}
    .pcard input[type=text]{background:transparent;border:0;border-bottom:1px solid var(--gb);color:var(--ink);font:inherit;font-size:14px;padding:6px 0;outline:none}
    .pcard textarea{background:transparent;border:1px solid var(--gb);border-radius:8px;color:var(--ink);font:inherit;font-size:14px;padding:8px;min-height:96px;resize:none;outline:none}
    body[data-bg=poster] .pcard{background:#0e0f12;border:2px solid #f2efe6;border-radius:12px;box-shadow:3px 3px 0 #f2efe6;color:#f2efe6}
    body[data-bg=poster] .fbtn{background:#f4b942;color:#16171b;border:2px solid #f2efe6}
    body[data-bg=plain] .prod,body[data-bg=grain] .prod{flex-direction:column;margin-top:30px}
    body[data-bg=poster]{--base:#20222a;--ink:#f2efe6;--soft:rgba(242,239,230,.62);--g:rgba(255,255,255,.06);--gb:rgba(255,255,255,.14)}
    .poster{position:fixed;inset:0;overflow:hidden;z-index:0;pointer-events:none}
    .poster i{position:absolute;display:block}
    .poster .p1{width:56vmax;height:56vmax;border-radius:50%;left:-18vmax;top:-26vmax;background:#ff6b4a}
    .poster .p2{width:46vmax;height:46vmax;border-radius:50%;right:-16vmax;bottom:-22vmax;background:#f4b942}
    .poster .p3{width:34vmax;height:13vmax;border-radius:13vmax;right:6vw;top:9vh;transform:rotate(-24deg);background:#2ec4a6}
    .poster .p4{width:10vmax;height:10vmax;border-radius:50%;border:1.3vmax solid #9a86f5;left:10vw;bottom:12vh}
    .poster:after{content:"";position:absolute;inset:0;opacity:.16;background-image:url("data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' width='160' height='160'><filter id='n'><feTurbulence type='fractalNoise' baseFrequency='.9' numOctaves='2' stitchTiles='stitch'/></filter><rect width='100%25' height='100%25' filter='url(%23n)'/></svg>")}
    body[data-bg=poster] .nt{background:#16171b;border:2px solid #f2efe6;border-radius:22px;padding:36px 40px 28px;box-shadow:10px 10px 0 #f2efe6;width:min(640px,90vw);margin-top:0}
    body[data-bg=poster] .hello,body[data-bg=poster] .fun{display:none}
    body[data-bg=poster] .clock{font:600 76px/1 ui-serif,"New York",Georgia,serif;letter-spacing:-.02em;margin-top:0}
    body[data-bg=poster] .cs-small .clock{font-size:50px}body[data-bg=poster] .cs-medium .clock{font-size:64px}
    body[data-bg=poster] .date{font:italic 17px ui-serif,"New York",Georgia,serif;color:var(--soft);margin-top:8px}
    body[data-bg=poster] .sbox{margin-top:30px}
    body[data-bg=poster] .sbox svg{left:16px;stroke:#f2efe6}
    body[data-bg=poster] .sbox input{border:2px solid #f2efe6;border-radius:12px;background:#0e0f12;color:#f2efe6;padding:14px 18px 14px 46px;font-size:16px;-webkit-backdrop-filter:none;backdrop-filter:none;box-shadow:4px 4px 0 #ff6b4a}
    body[data-bg=poster] .sbox input:focus{border-color:#f2efe6;box-shadow:4px 4px 0 #f4b942}
    body[data-bg=poster] .tiles{margin-top:32px;gap:14px 12px}
    body[data-bg=poster] .tile:hover{background:none;transform:none}
    body[data-bg=poster] .tile .m{border-radius:14px;border:2px solid #f2efe6;box-shadow:3px 3px 0 #f2efe6;transition:transform .12s,box-shadow .12s;color:#16171b;font-weight:700}
    body[data-bg=poster] .tile:hover .m{transform:translate(-2px,-2px);box-shadow:5px 5px 0 #f2efe6}
    body[data-bg=poster] .tile .m:not(.icon){background:#ff6b4a!important}
    body[data-bg=poster] .tile:nth-child(5n+2) .m:not(.icon){background:#f4b942!important}
    body[data-bg=poster] .tile:nth-child(5n+3) .m:not(.icon){background:#2ec4a6!important}
    body[data-bg=poster] .tile:nth-child(5n+4) .m:not(.icon){background:#9a86f5!important}
    body[data-bg=poster] .tile:nth-child(5n+5) .m:not(.icon){background:#ff8fb8!important}
    body[data-bg=poster] .tile .m.icon{background:#f2efe6!important}
    body[data-bg=poster] .tile .n{color:#f2efe6;font-size:12.5px;font-weight:500}
    body[data-bg=poster] .link{color:var(--soft);margin-top:22px}
    body[data-bg=ocean]{--b1:#0ea5e9;--b2:#2563eb;--b3:#22d3ee;--base:#04111f}
    body[data-bg=sunset]{--b1:#ff9a3c;--b2:#ff4e6a;--b3:#ffd166;--base:#1a0b10}
    body[data-bg=neon]{--b1:#00f5d4;--b2:#f15bb5;--b3:#9b5de5;--base:#07040f}
    body[data-bg=candy]{--b1:#ff8fd8;--b2:#8fb8ff;--b3:#ffd78f;--base:#1a1024}
    body[data-bg=sakura]{--b1:#ffc2d4;--b2:#ffe0ec;--b3:#e9d5ff;--base:#fdf2f5;--g:rgba(255,255,255,.6);--gb:rgba(0,0,0,.09);--ink:#2a1d24;--soft:rgba(42,29,36,.62)}
    body[data-bg=private]{--b1:#6d3bd2;--b2:#3b2a7a;--b3:#a855f7;--base:#0d0818}
    body[data-bg=paper]{--b1:#ffd0b5;--b2:#cfe3ff;--b3:#e9d5ff;--base:#f4f1ea;--g:rgba(255,255,255,.6);--gb:rgba(0,0,0,.09);--ink:#1d1f24;--soft:rgba(29,31,36,.62)}
    .bg{position:fixed;inset:0;overflow:hidden;z-index:0}
    .blob{position:absolute;width:70vmax;height:70vmax;border-radius:50%;opacity:.55;filter:blur(40px);will-change:transform}
    body[data-bg=paper] .blob{opacity:.85}
    .blob.a{background:radial-gradient(circle,var(--b1),transparent 62%);left:-18vmax;top:-28vmax}
    .blob.b{background:radial-gradient(circle,var(--b2),transparent 62%);right:-26vmax;top:-12vmax}
    .blob.c{background:radial-gradient(circle,var(--b3),transparent 62%);left:18vmax;bottom:-46vmax}
    .anim .a{animation:driftA 38s ease-in-out infinite alternate}.anim .b{animation:driftB 46s ease-in-out infinite alternate}.anim .c{animation:driftC 54s ease-in-out infinite alternate}
    @keyframes driftA{to{transform:translate3d(12vmax,8vmax,0) scale(1.12)}}
    @keyframes driftB{to{transform:translate3d(-14vmax,10vmax,0) scale(.92)}}
    @keyframes driftC{to{transform:translate3d(10vmax,-8vmax,0) scale(1.1)}}
    @keyframes rise{from{opacity:0;transform:translateY(12px)}to{opacity:1;transform:none}}
    [data-page=newtab] #app{position:relative;z-index:1;justify-content:center;align-items:center;min-height:100vh}
    .nt{width:min(700px,92vw);display:flex;flex-direction:column;align-items:center;margin-top:-3vh;animation:rise .6s cubic-bezier(.2,.7,.2,1) both}
    .hello{font-size:15px;color:var(--soft);letter-spacing:.02em}
    .clock{margin-top:6px;font-size:104px;font-weight:200;letter-spacing:-.04em;line-height:1;font-variant-numeric:tabular-nums}
    .date{margin-top:10px;color:var(--soft);font-size:15px}
    .sbox{margin-top:42px;width:100%;position:relative}
    .sbox svg{position:absolute;left:22px;top:50%;margin-top:-9px;width:18px;height:18px;stroke:var(--soft);fill:none;stroke-width:2;stroke-linecap:round;pointer-events:none}
    .sbox input{width:100%;font-size:17px;padding:17px 26px 17px 54px;border-radius:999px;background:var(--g);color:var(--ink);border:1px solid var(--gb);-webkit-backdrop-filter:blur(22px);backdrop-filter:blur(22px);transition:border-color .2s,box-shadow .2s,background .2s}
    .sbox input::placeholder{color:var(--soft)}
    .sbox input:focus{border-color:var(--soft);box-shadow:0 10px 44px rgba(0,0,0,.28)}
    .tiles{margin-top:46px;display:flex;flex-wrap:wrap;justify-content:center;gap:10px 12px;width:100%}
    .tile{position:relative;width:104px;display:flex;flex-direction:column;align-items:center;gap:10px;padding:14px 6px 12px;border-radius:20px;transition:background .18s,transform .18s}
    .tile:hover{background:var(--g);transform:translateY(-3px)}
    .tile .m{width:60px;height:60px;border-radius:19px;display:grid;place-items:center;font-size:25px;font-weight:600;color:#fff;box-shadow:inset 0 0 0 1px rgba(255,255,255,.1),0 6px 18px rgba(0,0,0,.22)}
    .tile .n{font-size:12.5px;color:var(--soft);max-width:92px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
    .tile .x{position:absolute;top:4px;right:12px;color:#ff8a8a;cursor:pointer;font-size:19px;line-height:1}
    .edit{margin-top:18px;display:flex;gap:8px;width:100%}.edit input{padding:9px 14px;font-size:13px;flex:1}
    .link{margin-top:26px;color:var(--soft);font-size:12.5px;cursor:pointer;background:none;border:0}.link:hover{color:var(--ink)}
    .fun{margin-top:30px;font-size:13px;color:var(--soft);font-style:italic;text-align:center}
    .priv{max-width:470px;text-align:center;color:var(--soft);line-height:1.6;margin-top:16px}
    .ptitle{font-size:58px;font-weight:300;letter-spacing:-.03em;line-height:1.05}
    .swatches{display:flex;gap:10px}.swatch{width:26px;height:26px;border-radius:50%;border:0;padding:0;cursor:pointer}
    .swatch.on{box-shadow:0 0 0 2px var(--panel),0 0 0 4px var(--text)}
    .cs-small .clock{font-size:56px}.cs-medium .clock{font-size:80px}
    .ts-circle .m{border-radius:50%}
    .ts-minimal .m{background:none!important;box-shadow:none!important;border-radius:14px}
    .tz-small .tile{width:86px}.tz-small .m{width:46px;height:46px;font-size:19px}
    .tz-large .tile{width:126px}.tz-large .m{width:76px;height:76px;font-size:31px}
    .nolabels .tile .n{display:none}
    .m img{width:62%;height:62%;object-fit:contain;border-radius:8px}
    .tile .m.icon{background:var(--g)!important}
    body.f-rounded{font-family:ui-rounded,"SF Pro Rounded",-apple-system,BlinkMacSystemFont,system-ui,sans-serif}
    body.f-serif{font-family:"New York",Georgia,"Times New Roman",serif}
    .bgimg{position:fixed;inset:0;background-size:cover;background-position:center;z-index:0}
    .dim{position:fixed;inset:0;background:#000;z-index:0;pointer-events:none}
    input[type=range]{width:160px;accent-color:var(--accent);padding:0}
    @media (max-width:640px){nav{display:none}}
    @media (prefers-reduced-motion:reduce){*{transition:none!important;animation:none!important}}
    """#

    static let script = #"""
    const $ = (s, r = document) => r.querySelector(s);
    const h = (tag, props, ...kids) => {
      const e = document.createElement(tag);
      for (const [k, v] of Object.entries(props || {})) {
        if (k === 'class') e.className = v;
        else if (k.startsWith('on')) e.addEventListener(k.slice(2), v);
        else if (k in e) e[k] = v;
        else e.setAttribute(k, v);
      }
      for (const kid of kids.flat()) if (kid != null && kid !== false) e.append(kid.nodeType ? kid : document.createTextNode(kid));
      return e;
    };
    const call = async (cmd, args = {}) => JSON.parse(await window.webkit.messageHandlers.veil.postMessage({ cmd, args }));
    const fmt = ts => new Date(ts * 1000).toLocaleString([], { dateStyle: 'medium', timeStyle: 'short' });
    const root = document.getElementById('app');
    const page = document.body.dataset.page;
    const ACCENTS = { mist: ['#8fb3c9', '#3d6c8a'], coral: ['#f0907d', '#c4503a'], mint: ['#6fd0a8', '#26896a'], violet: ['#ab94f5', '#6f52c9'], amber: ['#e8b058', '#a8700f'], pink: ['#f48fbe', '#be3c78'], sky: ['#64b5f6', '#1976d2'], lime: ['#aad65c', '#628c14'], crimson: ['#e8646e', '#b02838'] };
    const applyAccent = name => {
      const dark = window.matchMedia('(prefers-color-scheme: dark)').matches;
      const a = ACCENTS[name] || ACCENTS.mist;
      document.documentElement.style.setProperty('--accent', dark ? a[0] : a[1]);
    };
    // replaceChildren turns null into the text "null", so always drop empty values first.
    const put = (el, ...kids) => el.replaceChildren(...kids.flat().filter(k => k != null && k !== false));
    const NAV = [['settings', 'Settings'], ['privacy', 'Privacy'], ['history', 'History'], ['bookmarks', 'Bookmarks'], ['downloads', 'Downloads']];

    function shell(title, ...body) {
      document.title = title;
      root.replaceChildren(
        h('nav', {}, h('div', { class: 'brand' }, 'Veil'),
          ...NAV.map(([id, label]) => h('a', { href: 'veil://' + id, class: id === page ? 'on' : '' }, label))),
        h('main', {}, h('h1', {}, title), ...body));
    }
    const empty = msg => h('div', { class: 'empty' }, msg);
    const sw = (checked, onchange) => h('label', { class: 'sw' }, h('input', { type: 'checkbox', checked, onchange: e => onchange(e.target.checked) }), h('span'));
    const row = (label, hint, control) => h('div', { class: 'row' }, h('div', {}, h('div', { class: 'l' }, label), hint ? h('div', { class: 'hint' }, hint) : null), control);

    async function settingsPage() {
      const st = await call('settings.get');
      const s = st.settings;
      const nt = s.newTab;
      const set = (k, v) => { s[k] = v; return call('settings.set', { key: k, value: v }); };
      const saveNT = () => call('settings.set', { key: 'newTab', value: nt });
      const toggle = (key, label, hint) => row(label, hint, sw(s[key], v => set(key, v)));
      const ntToggle = (key, label, hint) => row(label, hint, sw(nt[key], v => { nt[key] = v; saveNT(); }));
      // Veil's own dropdown (instead of the system select box)
      const dropdown = (opts, cur, pick) => {
        const found = opts.find(o => o[0] === cur) || opts[0];
        const label = h('span', {}, found[1]);
        const list = h('div', { class: 'ddl' });
        const box = h('div', { class: 'dd' });
        const away = e => { if (!box.contains(e.target)) close(); };
        const close = () => { box.classList.remove('open'); document.removeEventListener('mousedown', away, true); };
        opts.forEach(([v, l]) => {
          const item = h('div', { class: 'ddi' + (v === found[0] ? ' on' : '') }, l);
          item.addEventListener('click', () => {
            Array.from(list.children).forEach(c => c.classList.toggle('on', c === item));
            label.textContent = l;
            close();
            pick(v);
          });
          list.append(item);
        });
        const btn = h('button', { class: 'ddb', type: 'button' }, label, h('span', { class: 'caret' }, '▾'));
        btn.addEventListener('click', () => {
          if (box.classList.contains('open')) { close(); return; }
          document.querySelectorAll('.dd.open').forEach(d => d.classList.remove('open'));
          box.classList.add('open');
          document.addEventListener('mousedown', away, true);
        });
        box.append(btn, list);
        return box;
      };
      const select = (key, opts) => dropdown(opts, s[key], v => set(key, v));
      const ntSelect = (key, opts) => dropdown(opts, nt[key], v => { nt[key] = v; saveNT(); });
      const status = h('span', { class: 'mute' });
      const picStatus = h('span', { class: 'mute' }, nt.customImage ? 'Picture saved' : '');
      const swatches = h('div', { class: 'swatches' });
      Object.keys(ACCENTS).forEach(name => {
        const b = h('button', { class: 'swatch' + (s.accent === name ? ' on' : ''), title: name, style: 'background:' + ACCENTS[name][0],
          onclick: () => { set('accent', name); applyAccent(name); swatches.querySelectorAll('.swatch').forEach(x => x.classList.toggle('on', x === b)); } });
        swatches.append(b);
      });

      // Browser themes (tab bar, toolbar and address box colours)
      const THEMES = { default: ['Default', null], midnight: ['Midnight', [222, .60]], forest: ['Forest', [140, .45]], rose: ['Rose', [340, .50]],
        sunset: ['Sunset', [18, .62]], grape: ['Grape', [272, .50]], ocean: ['Ocean', [190, .58]], mocha: ['Mocha', [28, .35]],
        mint: ['Mint', [160, .48]], graphite: ['Graphite', [220, 0]] };
      const hsb = (hh, ss, vv) => {
        const f = n => { const k = (n + hh / 60) % 6; return vv - vv * ss * Math.max(0, Math.min(k, 4 - k, 1)); };
        return '#' + [f(5), f(3), f(1)].map(x => Math.round(x * 255).toString(16).padStart(2, '0')).join('');
      };
      const themeGrid = h('div', { class: 'themes' });
      Object.keys(THEMES).forEach(key => {
        const label = THEMES[key][0], hs = THEMES[key][1];
        const bar = hs ? hsb(hs[0], hs[1], .16) : '#131417';
        const chip = hs ? hsb(hs[0], hs[1] * .8, .31) : '#2c2f37';
        const b = h('button', { class: 'tsw' + ((s.browserTheme || 'default') === key ? ' on' : ''), title: label,
          onclick: () => { set('browserTheme', key); themeGrid.querySelectorAll('.tsw').forEach(x => x.classList.toggle('on', x === b)); } },
          h('div', { class: 'tbar', style: 'background:' + bar }, h('i', { style: 'background:' + chip })), h('span', {}, label));
        themeGrid.append(b);
      });

      const picker = h('input', { type: 'file', accept: 'image/*', style: 'display:none', onchange: e => {
        const f = e.target.files[0]; if (!f) return;
        const reader = new FileReader();
        reader.onload = () => {
          const img = new Image();
          img.onload = async () => {
            const k = Math.min(1, 1920 / Math.max(img.width, img.height));
            const c = document.createElement('canvas');
            c.width = Math.max(1, Math.round(img.width * k)); c.height = Math.max(1, Math.round(img.height * k));
            c.getContext('2d').drawImage(img, 0, 0, c.width, c.height);
            const ok = await call('background.set', { data: c.toDataURL('image/jpeg', 0.82) });
            if (ok) { nt.background = 'custom'; nt.customImage = true; saveNT(); picStatus.textContent = 'Picture saved. Background set to My picture.'; }
            else picStatus.textContent = 'That picture could not be saved.';
          };
          img.src = reader.result;
        };
        reader.readAsDataURL(f);
      } });

      const excBox = h('textarea', { id: 'exc', spellcheck: false, placeholder: 'example.com', value: (s.cookieExceptions || []).join('\n') });
      const folderLabel = h('span', { class: 'mute' }, s.downloadFolder || 'Downloads');

      const FUN_DEFAULTS = { windowOpacity: 100, alwaysOnTop: false, pageFilter: 'none', pageFont: 'default', linkStyle: 'default',
        selectionColor: 'default', smoothScroll: false, hideScrollbars: false, roundImages: false, blurImages: false, dimPages: 0,
        reduceMotion: false, forceSelect: false, readableText: false, grayImages: false };
      const PRESETS = {
        'Normal': { theme: 'dark', accent: 'mist' },
        'Cozy night': { theme: 'dark', accent: 'amber', dimPages: 10, smoothScroll: true },
        'Neon arcade': { theme: 'dark', accent: 'pink', pageFilter: 'vivid', pageFont: 'rounded', selectionColor: 'lime' },
        'Paper': { theme: 'light', accent: 'mist', pageFont: 'serif', linkStyle: 'highlight', readableText: true },
        'Hacker': { theme: 'dark', accent: 'lime', pageFilter: 'dark', pageFont: 'mono', selectionColor: 'lime', hideScrollbars: true },
        'Candy': { theme: 'light', accent: 'pink', pageFont: 'rounded', selectionColor: 'pink', roundImages: true }
      };
      const LOCKDOWN = { adBlocking: true, cookieMode: 'third-party', httpsUpgrade: true, fingerprintProtection: true, sendGPC: true,
        clearHistoryOnQuit: true, keepSessionCookies: false, blockPopups: true, stripTracking: true, opsecWebRTC: true, opsecBeacons: true,
        opsecReferrer: true, opsecHardware: true, hideFromCapture: true, denyMedia: true };
      const lockdown = async () => {
        for (const k of Object.keys(LOCKDOWN)) await set(k, LOCKDOWN[k]);
        location.reload();
      };
      const applyPreset = async name => {
        const p = Object.assign({}, FUN_DEFAULTS, PRESETS[name]);
        for (const k of Object.keys(p)) await set(k, p[k]);
        location.reload();
      };

      shell('Settings',
        h('h2', {}, 'Look and fun'),
        h('div', { class: 'card' },
          row('Theme', null, select('theme', [['dark', 'Dark'], ['light', 'Light'], ['system', 'Match system']])),
          row('Accent colour', 'Tints tabs, buttons and these pages.', swatches),
          row('Browser theme', 'Colours the tab bar, toolbar and address bar, like Chrome themes.', themeGrid),
          toggle('verticalTabs', 'Vertical tabs', 'Show tabs in a sidebar instead of a row. Shortcut: ⇧⌘\\'),
          row('Tab width', null, select('tabWidth', [['compact', 'Compact'], ['normal', 'Normal'], ['wide', 'Wide']])),
          toggle('showBookmarksBar', 'Show bookmarks bar', 'Keeps the pages you bookmark (⌘D) at the top of every window.')),

        h('h2', {}, 'Quick looks'),
        h('div', { class: 'card' },
          row('Theme presets', 'One click sets the colours, fonts and page style together.',
            h('div', { class: 'actions', style: 'margin:0;flex-wrap:wrap;justify-content:flex-end' },
              ...Object.keys(PRESETS).map(n => h('button', { onclick: () => applyPreset(n) }, n)))),
          row('Reset fun settings', 'Puts everything in Window fun and Web page fun back to normal.',
            h('button', { class: 'danger', onclick: () => applyPreset('Normal') }, 'Reset'))),

        h('h2', {}, 'Tidy up'),
        h('div', { class: 'card' },
          toggle('newTabNextToCurrent', 'Open new tabs next to the current tab', 'Off = new tabs go to the far end.'),
          toggle('rememberWindow', 'Remember window size and position', null),
          toggle('confirmCloseWindow', 'Ask before closing a window with several tabs', null),
          toggle('hideShieldButton', 'Hide the shield button', 'You can still reach it from the privacy page.'),
          toggle('hideDownloadsButton', 'Hide the downloads button', null),
          toggle('hideBookmarkButton', 'Hide the bookmark star', 'The shortcut ⌘D still works.')),

        h('h2', {}, 'Window fun'),
        h('div', { class: 'card' },
          row('See-through window', 'Lower = more see-through. Applies right away.', h('input', { type: 'range', min: 60, max: 100, value: s.windowOpacity, onchange: e => set('windowOpacity', Number(e.target.value)) })),
          toggle('alwaysOnTop', 'Keep window on top', 'Veil floats above your other apps.'),
          toggle('dockTabCount', 'Show tab count on the Dock icon', null),
          toggle('confirmQuit', 'Ask before quitting with several tabs open', null),
          toggle('downloadSound', 'Play a sound when a download finishes', null)),

        h('h2', {}, 'Web page fun'),
        h('div', { class: 'card' },
          row('Page style', 'Changes how every website looks. Applies to pages you open or reload.',
            select('pageFilter', [['none', 'Normal'], ['dark', 'Dark mode for every site'], ['grayscale', 'Black and white'], ['sepia', 'Old photo'], ['contrast', 'High contrast'], ['vivid', 'Extra colourful'], ['cool', 'Alien blue']])),
          row('Page font', 'Swap the font on websites.', select('pageFont', [['default', 'Normal'], ['comic', 'Comic'], ['rounded', 'Rounded'], ['serif', 'Serif'], ['mono', 'Typewriter'], ['hand', 'Handwriting']])),
          row('Text highlight colour', 'The colour when you select text.', select('selectionColor', [['default', 'Normal'], ['pink', 'Pink'], ['lime', 'Lime'], ['yellow', 'Yellow'], ['sky', 'Sky blue'], ['violet', 'Violet']])),
          row('Link style', null, select('linkStyle', [['default', 'Normal'], ['wavy', 'Wavy underline'], ['highlight', 'Highlighter'], ['underline', 'Always underlined'], ['plain', 'No underline']])),
          toggle('roundImages', 'Round image corners', null),
          toggle('blurImages', 'Blur images until you point at them', 'Handy when someone is looking over your shoulder.'),
          toggle('smoothScroll', 'Smooth scrolling', null),
          toggle('hideScrollbars', 'Hide scrollbars', null),
          toggle('reduceMotion', 'Calm animations', 'Stops most movement and fades on websites.'),
          toggle('forceSelect', 'Always allow selecting text', 'Works on sites that try to stop you copying.'),
          toggle('readableText', 'Easier-to-read text', 'More space between lines and shorter paragraphs.'),
          toggle('grayImages', 'Black and white images', null),
          row('Dim pages', 'Makes bright websites darker.', h('input', { type: 'range', min: 0, max: 60, value: s.dimPages, onchange: e => set('dimPages', Number(e.target.value)) }))),

        h('h2', {}, 'Start page'),
        h('div', { class: 'card' },
          row('Background', null, ntSelect('background', [['aurora', 'Aurora'], ['poster', 'Poster'], ['plain', 'Plain'], ['grain', 'Soft grain'], ['dusk', 'Dusk'], ['forest', 'Forest'], ['ember', 'Ember'], ['midnight', 'Midnight'], ['paper', 'Paper'], ['ocean', 'Ocean'], ['sunset', 'Sunset'], ['neon', 'Neon'], ['candy', 'Candy'], ['sakura', 'Sakura'], ['custom', 'My picture']])),
          row('My picture', 'Choose any image. It is shrunk and stored only on this Mac.', h('div', { class: 'actions', style: 'margin:0' },
            h('button', { onclick: () => picker.click() }, 'Choose…'),
            h('button', { onclick: async () => { await call('background.clear'); nt.customImage = false; if (nt.background === 'custom') nt.background = 'aurora'; saveNT(); picStatus.textContent = 'Picture removed.'; } }, 'Remove'), picker)),
          row('', null, picStatus),
          row('Darken background', 'Makes text easier to read over bright pictures.', h('input', { type: 'range', min: 0, max: 70, value: nt.dim, onchange: e => { nt.dim = Number(e.target.value); saveNT(); } })),
          row('Font', null, ntSelect('font', [['modern', 'Modern'], ['rounded', 'Rounded'], ['serif', 'Serif']])),
          row('Clock size', null, ntSelect('clockSize', [['small', 'Small'], ['medium', 'Medium'], ['large', 'Large']])),
          row('Shortcut style', null, ntSelect('tileStyle', [['rounded', 'Rounded squares'], ['circle', 'Circles'], ['minimal', 'Minimal']])),
          row('Shortcut size', null, ntSelect('tileSize', [['small', 'Small'], ['medium', 'Medium'], ['large', 'Large']])),
          ntToggle('showLabels', 'Show shortcut names', null),
          row('Your name', 'Used in the greeting.', h('input', { type: 'text', value: nt.name, placeholder: 'Name', onchange: e => { nt.name = e.target.value.trim(); saveNT(); } })),
          ntToggle('showClock', 'Show clock', null),
          ntToggle('use24Hour', '24-hour clock', null),
          ntToggle('showSearch', 'Show search box', null),
          ntToggle('animated', 'Animated background', 'A slow, gentle drift. Turn off to save a little power.'),
          ntToggle('funLines', 'Daily one-liner', 'A small line under your shortcuts that changes each day.')),

        h('h2', {}, 'Productivity'),
        h('div', { class: 'card' },
          ntToggle('showFocus', 'Focus timer on the start page', 'A simple countdown for working in focused bursts.'),
          row('Focus length', null, ntSelect('focusMinutes', [[15, '15 minutes'], [25, '25 minutes'], [45, '45 minutes'], [50, '50 minutes'], [90, '90 minutes']])),
          ntToggle('showTodos', 'To-do list on the start page', 'Saved on this Mac only.'),
          ntToggle('showNotes', 'Quick notes on the start page', 'A scratchpad that saves as you type.')),

        h('h2', {}, 'Search'),
        h('div', { class: 'card' }, row('Search engine', 'Used when you type something that isn’t an address.', select('searchEngine', st.engines.map(e => [e.id, e.name])))),

        h('h2', {}, 'Browsing'),
        h('div', { class: 'card' },
          toggle('mouseNavButtons', 'Mouse back and forward buttons', 'The side buttons on your mouse go back and forward.'),
          toggle('blockPopups', 'Block pop-up windows', 'Pop-ups that open without you clicking are blocked. Applies to new tabs.'),
          row('Default page zoom', 'Applies to tabs you open from now on.', select('defaultZoom', [[75, '75%'], [90, '90%'], [100, '100%'], [110, '110%'], [125, '125%'], [150, '150%'], [175, '175%'], [200, '200%']])),
          toggle('developerTools', 'Developer tools', 'Adds Inspect Element to the right-click menu. Applies to tabs you open from now on.'),
          toggle('restoreSession', 'Reopen tabs on launch', 'Tabs load only when you select them, so startup stays light.'),
          toggle('keepSessionCookies', 'Keep me signed in across restarts', 'Saves login cookies that would otherwise be dropped on quit. Stored only on this Mac.'),
          row('Unload idle tabs', 'Frees memory from background tabs. They reload when selected; unsaved form text is lost. Tabs playing audio and private tabs are never unloaded.',
            select('discardIdleTabsMinutes', [[0, 'Never'], [15, 'After 15 min'], [30, 'After 30 min'], [60, 'After 1 hour']]))),

        h('h2', {}, 'Downloads'),
        h('div', { class: 'card' },
          row('Download folder', null, h('div', { class: 'actions', style: 'margin:0' }, folderLabel,
            h('button', { onclick: async () => { folderLabel.textContent = (await call('downloads.chooseFolder')) || 'Downloads'; } }, 'Choose…'))),
          toggle('askDownloadLocation', 'Ask where to save each file', null),
          toggle('openDownloadsOnStart', 'Show the downloads panel when a download starts', null)),

        h('h2', {}, 'Privacy'),
        h('div', { class: 'card' },
          row('Lockdown mode', 'Turns on every protection at once. Some sites and video calls may stop working. Panic key: ⌃⌘H mutes everything and hides Veil.',
            h('button', { onclick: lockdown }, 'Turn on')),
          toggle('adBlocking', 'Block ads and trackers', 'Uses the filter lists below. Turn off per site with the shield button.'),
          row('Cookies', 'Third-party blocking stops trackers while sites keep their own logins. “Block all” is strictest: only the sites listed below can keep cookies.',
            select('cookieMode', [['off', 'Allow all'], ['third-party', 'Block third-party (default)'], ['all', 'Block all except my sites']])),
          toggle('httpsUpgrade', 'Upgrade to HTTPS', 'Tries https:// first and asks before falling back to http.'),
          toggle('fingerprintProtection', 'Fingerprinting protection', 'Adds noise to canvas readback. Can break a few drawing or photo sites.'),
          toggle('sendGPC', 'Send Global Privacy Control', 'Tells sites you don’t want your data sold or shared.'),
          toggle('stripTracking', 'Remove tracking from links', 'Strips things like utm_ and fbclid from addresses before the page loads.'),
          toggle('opsecWebRTC', 'Block WebRTC IP leaks', 'Stops sites from finding your real IP address behind a VPN. Breaks web video calls.'),
          toggle('opsecBeacons', 'Block tracking pings and beacons', null),
          toggle('opsecReferrer', 'Hide where I came from', 'Websites you click through to won’t learn which page you were on. A few sites may complain.'),
          toggle('opsecHardware', 'Hide hardware details', 'Reports generic processor, memory and battery info to websites.'),
          toggle('denyMedia', 'Never allow camera or microphone', null),
          toggle('hideFromCapture', 'Hide Veil from screenshots and screen recording', 'The window shows up blank in captures and screen sharing.'),
          toggle('clearHistoryOnQuit', 'Clear history when quitting', 'Never touches cookies, so you stay signed in.')),
        h('h2', {}, 'Sites that may keep cookies (used by “Block all”)'),
        excBox,
        h('div', { class: 'actions' }, h('button', { onclick: () => set('cookieExceptions', $('#exc').value.split(/\n+/).map(x => x.trim().toLowerCase()).filter(Boolean)) }, 'Save sites')),

        h('h2', {}, 'Filter lists'),
        h('div', { class: 'card' }, ...st.sources.map(src => row(src.name,
          src.blurb + (src.url ? (src.updated ? ' Updated ' + fmt(src.updated) + '.' : ' Not downloaded yet.') : ''),
          sw(src.enabled, v => { src.enabled = v; const m = {}; st.sources.forEach(x => m[x.id] = x.enabled); set('enabledLists', m); })))),
        h('div', { class: 'actions' },
          h('button', { onclick: async () => {
            status.textContent = 'Downloading…';
            const r = await call('lists.update');
            status.textContent = r.failed.length ? 'Could not download: ' + r.failed.join(', ') : 'Lists updated.';
          } }, 'Download and update lists'),
          status),
        h('p', { class: 'hint' }, 'Downloading lists contacts easylist.to and ublockorigin.github.io directly, without cookies. It is the only time Veil talks to a third party. ',
          st.meta.networkRules + ' network rules and ' + st.meta.cosmeticRules + ' hiding rules are active; ' + st.meta.skippedRules + ' unsupported rules were skipped.'),
        h('div', { class: 'card', style: 'margin-top:14px' }, toggle('autoUpdateLists', 'Update lists automatically', 'Checks once a week when Veil starts.')),
        h('h2', {}, 'Custom filters'),
        h('textarea', { id: 'custom', spellcheck: false, placeholder: '||example.com^\nexample.org##.banner', value: s.customRules }),
        h('div', { class: 'actions' }, h('button', { onclick: () => set('customRules', $('#custom').value) }, 'Save filters')));

      // Search box: hides settings that don't match what you type.
      const main = root.querySelector('main');
      const finder = h('input', { type: 'text', placeholder: 'Search settings…', style: 'width:100%;margin:0 0 6px', oninput: e => {
        const t = e.target.value.trim().toLowerCase();
        main.querySelectorAll('.row').forEach(r => { r.style.display = !t || r.textContent.toLowerCase().includes(t) ? '' : 'none'; });
        main.querySelectorAll('.card').forEach(c => {
          const rows = c.querySelectorAll('.row');
          c.style.display = !t || rows.length === 0 || Array.from(rows).some(r => r.style.display !== 'none') ? '' : 'none';
        });
        main.querySelectorAll('h2').forEach(hh => {
          const c = hh.nextElementSibling;
          hh.style.display = !t || !c || !c.classList.contains('card') || c.style.display !== 'none' ? '' : 'none';
        });
      } });
      main.querySelector('h1').after(finder);
    }

    async function privacyPage() {
      const o = await call('privacy.overview');
      const cookies = await call('cookies.list');
      const perms = await call('permissions.list');
      const body = h('div');
      const draw = async () => {
        const allow = await call('allowlist.list');
        const list = h('div', { class: 'card' }, allow.length ? allow.map(host => h('div', { class: 'item' }, h('div', { class: 't' }, host),
          h('button', { onclick: async () => { await call('allowlist.remove', { host }); draw(); } }, 'Resume blocking'))) : empty('Blocking is on everywhere.'));
        const input = h('input', { type: 'text', placeholder: 'example.com' });
        body.replaceChildren(h('h2', {}, 'Blocking is off on these sites'), list,
          h('div', { class: 'actions' }, input, h('button', { onclick: async () => { if (input.value.trim()) { await call('allowlist.add', { host: input.value.trim() }); draw(); } } }, 'Turn off for site')));
      };
      const cookieCard = h('div', { class: 'card' });
      const q = h('input', { type: 'text', placeholder: 'Filter cookies by site', oninput: () => drawCookies() });
      const drawCookies = () => {
        const f = q.value.toLowerCase();
        const rows = cookies.filter(c => c.domain.includes(f)).slice(0, 200);
        cookieCard.replaceChildren(...(rows.length ? rows.map(c => h('div', { class: 'item' }, h('div', { class: 't' }, c.domain), h('span', { class: 'mute' }, c.count),
          h('button', { onclick: async () => { await call('cookies.clearDomain', { domain: c.domain }); c.count = 0; cookies.splice(cookies.indexOf(c), 1); drawCookies(); } }, 'Remove'))) : [empty('No cookies.')]));
      };
      drawCookies();
      shell('Privacy',
        h('div', { class: 'stats' },
          ...[[o.rules, 'rules blocking'], [o.cookieDomains, 'sites with cookies'], [o.history, 'history entries'], [o.bookmarks, 'bookmarks']]
            .map(([n, l]) => h('div', { class: 'stat' }, h('b', {}, n.toLocaleString()), h('span', {}, l)))),
        h('p', { class: 'hint' }, 'Veil has no telemetry, no account and no sync. History, bookmarks, cookies and settings stay in ~/Library/Application Support/Veil and WebKit’s own storage on this Mac. Veil never deletes cookies on its own.'),
        body,
        h('h2', {}, 'Site permissions'),
        h('div', { class: 'card' }, perms.length ? perms.map(p => h('div', { class: 'item' }, h('div', { class: 't' }, p.host + ' · ' + p.kind), h('span', { class: 'mute' }, p.allowed ? 'Allowed' : 'Blocked'),
          h('button', { onclick: async (e) => { await call('permissions.remove', { host: p.host, kind: p.kind }); e.target.closest('.item').remove(); } }, 'Reset'))) : empty('No saved permissions.')),
        h('h2', {}, 'Cookies'), q, h('div', { style: 'height:10px' }), cookieCard,
        h('div', { class: 'actions' },
          h('button', { class: 'danger', onclick: async () => { if (confirm('Remove all cookies? You will be signed out of every site.')) { await call('cookies.clearAll'); location.reload(); } } }, 'Remove all cookies'),
          h('button', { class: 'danger', onclick: async () => { if (confirm('Remove all cookies, local storage, and cached site data? You will be signed out everywhere.')) { await call('siteData.clearAll'); location.reload(); } } }, 'Remove all site data')));
      draw();
    }

    async function historyPage() {
      const list = h('div', { class: 'card' });
      const q = h('input', { type: 'text', placeholder: 'Search history', oninput: () => draw() });
      const draw = async () => {
        const items = await call('history.list', { q: q.value });
        list.replaceChildren(...(items.length ? items.map(i => h('div', { class: 'item' },
          h('div', { class: 't' }, h('div', {}, h('a', { href: i.url }, i.title || i.url)), h('div', { class: 'mute url' }, i.url)),
          h('span', { class: 'mute' }, fmt(i.date)),
          h('button', { onclick: async () => { await call('history.remove', { id: i.id }); draw(); } }, 'Remove'))) : [empty('Nothing here.')]));
      };
      shell('History', q, h('div', { style: 'height:12px' }), list,
        h('div', { class: 'actions' }, h('button', { class: 'danger', onclick: async () => { if (confirm('Clear all history?')) { await call('history.clear'); draw(); } } }, 'Clear history')));
      draw();
    }

    async function bookmarksPage() {
      const list = h('div', { class: 'card' });
      const draw = async () => {
        const items = await call('bookmarks.list');
        list.replaceChildren(...(items.length ? items.map(i => h('div', { class: 'item' },
          h('div', { class: 't' }, h('div', {}, h('a', { href: i.url }, i.title)), h('div', { class: 'mute url' }, i.url)),
          h('button', { onclick: async () => { await call('bookmarks.remove', { url: i.url }); draw(); } }, 'Remove'))) : [empty('Press ⌘D on any page to bookmark it.')]));
      };
      shell('Bookmarks', list); draw();
    }

    async function downloadsPage() {
      const list = h('div', { class: 'card' });
      const draw = async () => {
        const items = await call('downloads.list');
        list.replaceChildren(...(items.length ? items.map(i => h('div', { class: 'item' },
          h('div', { class: 't' }, h('div', {}, i.name), h('div', { class: 'mute url' }, i.source),
            i.state === 'running' ? h('div', { class: 'bar' }, h('i', { style: 'width:' + Math.round((i.progress || 0) * 100) + '%' })) : null),
          h('span', { class: 'mute' }, i.state === 'done' ? 'Done' : i.state === 'failed' ? 'Failed' : Math.round((i.progress || 0) * 100) + '%'),
          i.state === 'done' ? h('button', { onclick: () => call('downloads.open', { id: i.id }) }, 'Open') : null,
          i.state !== 'running' && i.state !== 'failed' ? h('button', { onclick: () => call('downloads.reveal', { id: i.id }) }, 'Show in Finder') : null)) : [empty('No downloads yet.')]));
        return items.some(i => i.state === 'running');
      };
      shell('Downloads', list,
        h('div', { class: 'actions' }, h('button', { onclick: async () => { await call('downloads.clear'); draw(); } }, 'Clear finished')));
      draw();
      setInterval(() => { if (!document.hidden) draw(); }, 1500);
    }

    const LINES = ['Quiet web, loud ideas.', 'Nobody is watching. Browse freely.', 'Small tabs, big thoughts.', 'Today is a good day to close twelve tabs.',
      'Take the scenic route through the internet.', 'Hydrate. Then keep scrolling.', 'Curiosity is the best extension.', 'Fresh tab, fresh start.',
      'Be kind to your RAM.', 'Somewhere, a cat video is waiting for you.', 'Make it a good one.', 'The best tab is the one you meant to open.'];

    function backdrop(bg, animated, nt) {
      if (!bg || bg === 'glow') bg = 'aurora';
      document.body.dataset.bg = bg === 'custom' ? 'midnight' : bg;
      const layers = [];
      if (bg === 'plain' || bg === 'grain') {
        layers.push(h('div', { class: 'flat' }));
      } else if (bg === 'poster') {
        layers.push(h('div', { class: 'poster' }, h('i', { class: 'p1' }), h('i', { class: 'p2' }), h('i', { class: 'p3' }), h('i', { class: 'p4' })));
      } else if (bg === 'custom') {
        layers.push(h('div', { class: 'bgimg', id: 'bgimg' }));
        call('background.get').then(d => { if (d) $('#bgimg').style.backgroundImage = 'url(' + d + ')'; }).catch(() => {});
      } else {
        layers.push(h('div', { class: 'bg' + (animated ? ' anim' : '') }, h('div', { class: 'blob a' }), h('div', { class: 'blob b' }), h('div', { class: 'blob c' })));
      }
      if (nt && nt.dim) layers.push(h('div', { class: 'dim', style: 'opacity:' + (nt.dim / 100) }));
      document.body.prepend(...layers);
    }
    const magnifier = () => { const s = h('span'); s.innerHTML = '<svg viewBox="0 0 24 24"><circle cx="11" cy="11" r="7"/><path d="M20 20l-3.5-3.5"/></svg>'; return s; };
    const searchForm = placeholder => {
      const q = h('input', { type: 'text', placeholder, spellcheck: false });
      return h('form', { class: 'sbox', onsubmit: e => { e.preventDefault(); const v = q.value.trim(); if (v) call('navigate', { text: v }); } }, magnifier(), q);
    };

    function privateTab(nt) {
      document.title = 'Private Tab';
      backdrop('private', nt.animated, null);
      put(root, h('div', { class: 'nt' },
        h('div', { class: 'hello' }, 'Veil'),
        h('div', { class: 'ptitle' }, 'Private tab'),
        h('p', { class: 'priv' }, 'Veil won’t keep history, cookies or site data from private tabs, and wipes them when you close the last one. Ad and tracker blocking stays on.'),
        h('p', { class: 'priv', style: 'margin-top:0' }, 'Websites, your network and your downloads can still see what you do.'),
        searchForm('Search privately or enter address')));
    }

    async function newtabPage() {
      const st = await call('settings.get');
      const nt = st.settings.newTab;
      document.title = 'New Tab';
      if (location.search.indexOf('private') >= 0) return privateTab(nt);
      document.body.classList.add('f-' + (nt.font || 'modern'));
      backdrop(nt.background, nt.animated, nt);
      const icons = await call('newtab.icons').catch(() => ({}));
      let editing = false;
      const save = () => call('settings.set', { key: 'newTab', value: nt });
      const hue = str => { let x = 7; for (const c of str.toLowerCase()) x = (x * 31 + c.charCodeAt(0)) % 360; return x; };
      const hello = h('div', { class: 'hello' }), clock = h('div', { class: 'clock' }), date = h('div', { class: 'date' });
      const greet = d => {
        const hr = d.getHours();
        const part = hr < 5 ? 'Still up' : hr < 12 ? 'Good morning' : hr < 18 ? 'Good afternoon' : 'Good evening';
        return nt.greeting || (part + (nt.name ? ', ' + nt.name : ''));
      };
      const tick = () => {
        if (document.hidden) return;
        const d = new Date();
        hello.textContent = greet(d);
        clock.textContent = d.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', hour12: !nt.use24Hour });
        date.textContent = d.toLocaleDateString([], { weekday: 'long', month: 'long', day: 'numeric' });
      };
      const uid = () => Math.random().toString(36).slice(2, 10);
      const fmtLeft = ms => { const s = Math.max(0, Math.ceil(ms / 1000)); return String(Math.floor(s / 60)).padStart(2, '0') + ':' + String(s % 60).padStart(2, '0'); };
      let focusUpdate = null;
      setInterval(() => { if (focusUpdate && !document.hidden) focusUpdate(); }, 1000);
      const focusBox = () => {
        const time = h('div', { class: 'ftime' });
        const btn = h('button', { class: 'fbtn' });
        const update = () => {
          const left = nt.focusEnd - Date.now();
          if (nt.focusEnd && left > 0) { time.textContent = fmtLeft(left); btn.textContent = 'Stop'; }
          else if (nt.focusEnd) { time.textContent = 'Done!'; btn.textContent = 'Again'; }
          else { time.textContent = String(nt.focusMinutes || 25).padStart(2, '0') + ':00'; btn.textContent = 'Start'; }
        };
        btn.addEventListener('click', () => {
          const running = nt.focusEnd && nt.focusEnd - Date.now() > 0;
          nt.focusEnd = running ? 0 : Date.now() + (nt.focusMinutes || 25) * 60000;
          save(); update();
        });
        focusUpdate = update; update();
        return h('div', { class: 'pcard focus' }, h('div', { class: 'ptitle' }, 'Focus'), time, btn);
      };
      const todoBox = () => {
        const list = h('div', { class: 'tlist' });
        const input = h('input', { type: 'text', placeholder: 'Add a task, press Enter' });
        const clear = h('b', { class: 'tclear' }, 'clear done');
        const render = () => {
          list.textContent = '';
          nt.todos.forEach((t, i) => {
            const box = h('input', { type: 'checkbox', checked: !!t.done });
            box.addEventListener('change', () => { t.done = box.checked; save(); render(); });
            const del = h('b', { class: 'tdel' }, '×');
            del.addEventListener('click', () => { nt.todos.splice(i, 1); save(); render(); });
            list.append(h('div', { class: 'titem' + (t.done ? ' done' : '') }, box, h('span', {}, t.text), del));
          });
        };
        clear.addEventListener('click', () => { nt.todos = nt.todos.filter(t => !t.done); save(); render(); });
        input.addEventListener('keydown', e => {
          if (e.key === 'Enter' && input.value.trim()) { nt.todos.push({ id: uid(), text: input.value.trim(), done: false }); input.value = ''; save(); render(); }
        });
        render();
        return h('div', { class: 'pcard todos' }, h('div', { class: 'ptitle' }, 'To-do', clear), list, input);
      };
      const notesBox = () => {
        const ta = h('textarea', { placeholder: 'Quick notes…', spellcheck: false, value: nt.notes || '' });
        let timer = null;
        ta.addEventListener('input', () => { nt.notes = ta.value; clearTimeout(timer); timer = setTimeout(save, 400); });
        return h('div', { class: 'pcard notes' }, h('div', { class: 'ptitle' }, 'Notes'), ta);
      };
      const productivity = () => (nt.showFocus || nt.showTodos || nt.showNotes)
        ? h('div', { class: 'prod' }, nt.showFocus ? focusBox() : null, nt.showTodos ? todoBox() : null, nt.showNotes ? notesBox() : null)
        : null;
      const form = searchForm('Search or enter address');
      const wrap = h('div', { class: 'nt cs-' + nt.clockSize + ' ts-' + nt.tileStyle + ' tz-' + nt.tileSize + (nt.showLabels ? '' : ' nolabels') });
      const draw = () => {
        const tiles = nt.shortcuts.map((s, i) => h('a', { class: 'tile', href: editing ? '#' : s.url, onclick: e => { if (editing) e.preventDefault(); } },
          icons[s.url]
            ? h('div', { class: 'm icon' }, h('img', { src: icons[s.url] }))
            : h('div', { class: 'm', style: 'background:linear-gradient(145deg,hsl(' + hue(s.title) + ',38%,46%),hsl(' + hue(s.title) + ',34%,28%))' }, (s.title[0] || '•').toUpperCase()),
          h('div', { class: 'n' }, s.title),
          editing ? h('span', { class: 'x', onclick: e => { e.preventDefault(); e.stopPropagation(); nt.shortcuts.splice(i, 1); save(); draw(); } }, '×') : null));
        const t = h('input', { type: 'text', placeholder: 'Name' }), u = h('input', { type: 'text', placeholder: 'example.com' });
        put(wrap,
          nt.showClock ? hello : null, nt.showClock ? clock : null, nt.showClock ? date : null,
          nt.showSearch ? form : null,
          h('div', { class: 'tiles' }, tiles),
          editing ? null : productivity(),
          editing ? h('div', { class: 'edit' }, t, u, h('button', { onclick: () => {
            if (!t.value.trim() || !u.value.trim()) return;
            let url = u.value.trim(); if (!/^[a-z]+:\/\//i.test(url)) url = 'https://' + url;
            nt.shortcuts.push({ title: t.value.trim(), url }); save(); draw();
          } }, 'Add')) : null,
          h('button', { class: 'link', onclick: () => { editing = !editing; draw(); } }, editing ? 'Done' : 'Edit shortcuts'),
          nt.funLines ? h('div', { class: 'fun' }, LINES[Math.floor(Date.now() / 86400000) % LINES.length]) : null);
        tick();
      };
      put(root, wrap); draw();
      setInterval(tick, 20000);
      document.addEventListener('visibilitychange', async () => {
        if (document.hidden || editing) return;
        const tag = (document.activeElement && document.activeElement.tagName) || '';
        if (/INPUT|TEXTAREA/.test(tag)) return;
        try {
          const fresh = (await call('settings.get')).settings.newTab;
          nt.todos = fresh.todos; nt.notes = fresh.notes; nt.focusEnd = fresh.focusEnd;
          draw();
        } catch (e) {}
      });
      // Keyboard: press 1-9 to open a shortcut, / to jump to the search box.
      document.addEventListener('keydown', e => {
        if (editing || e.metaKey || e.ctrlKey || e.altKey) return;
        const tag = (document.activeElement && document.activeElement.tagName) || '';
        if (/INPUT|TEXTAREA/.test(tag)) return;
        if (e.key === '/') { e.preventDefault(); const i = $('.sbox input'); if (i) i.focus(); return; }
        const n = parseInt(e.key, 10);
        if (n >= 1 && n <= nt.shortcuts.length) location.href = nt.shortcuts[n - 1].url;
      });
    }

    call('settings.get').then(st => applyAccent(st.settings.accent)).catch(() => {});
    ({ settings: settingsPage, privacy: privacyPage, history: historyPage, bookmarks: bookmarksPage, downloads: downloadsPage, newtab: newtabPage }[page] || (() => {}))();
    """#
}
