"""
title: Für Outlook kopieren
description: Kopiert die Antwort als formatierten Text für Outlook, Tabellen nur so breit wie ihr Inhalt
version: 1.0
"""

# Action für das Profil Q3.8 Backoffice (SETUP-LOG P5). Installiert mit scripts/p5-action-outlook.sh.
# Ablauf: Der Server wandelt den Markdown-Text der Antwort in HTML mit festen Inline-Stilen um
# (Outlook übernimmt keine <style>-Blöcke zuverlässig) und schickt per __event_call__ ("execute")
# ein kurzes Skript an den Browser, das HTML und reinen Text in die Zwischenablage schreibt.
# Der Text der Antwort wird nur umgewandelt, nicht gespeichert und nicht protokolliert.

import html
import json
import re

import markdown

# Kleines Symbol (Briefumschlag) für den Knopf unter der Antwort
icon = (
    "data:image/svg+xml;base64,"
    "PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHZpZXdCb3g9IjAgMCAyNCAyNCIgZmlsbD0ibm9uZSIg"
    "c3Ryb2tlPSJjdXJyZW50Q29sb3IiIHN0cm9rZS13aWR0aD0iMS41IiBzdHJva2UtbGluZWNhcD0icm91bmQiIHN0cm9rZS1s"
    "aW5lam9pbj0icm91bmQiPjxyZWN0IHg9IjMiIHk9IjUiIHdpZHRoPSIxOCIgaGVpZ2h0PSIxNCIgcng9IjIiLz48cGF0aCBk"
    "PSJNMyA3bDkgNiA5LTYiLz48L3N2Zz4="
)

STIL_TABELLE = "border-collapse:collapse;width:auto;border:1px solid #dfe2e5;margin:0 0 12px 0"
STIL_ZELLE = "border:1px solid #dfe2e5;padding:4px 8px"
STIL_KOPF = STIL_ZELLE + ";background-color:#f6f8fa;font-weight:bold"
STIL_ABSATZ = "margin:0 0 12px 0"
STIL_LISTE = "margin:0 0 12px 0;padding-left:24px"

LISTE = re.compile(r"^\s*([-*+]|\d+[.)])\s+")
TABELLE = re.compile(r"^\s*\|")


def _vorbereiten(text: str) -> str:
    """Markdown so vorbereiten, dass Python-Markdown es wie der Chat (marked) darstellt."""
    # Denkprozess, Tool-Aufrufe usw. (wie der Kopieren-Knopf von Open WebUI)
    text = re.sub(r"<details\b.*?</details>\s*", "", text, flags=re.S | re.I)
    text = text.strip()
    # Kein HTML aus der Antwort übernehmen, nur Markdown
    text = html.escape(text, quote=False)
    # Vor Listen und Tabellen braucht Python-Markdown eine Leerzeile, marked nicht
    zeilen = []
    for zeile in text.split("\n"):
        if zeilen and zeilen[-1].strip():
            vorher = zeilen[-1]
            neu_liste = LISTE.match(zeile) and not LISTE.match(vorher) and not vorher.startswith(" ")
            neu_tabelle = TABELLE.match(zeile) and not TABELLE.match(vorher)
            if neu_liste or neu_tabelle:
                zeilen.append("")
        zeilen.append(zeile)
    return "\n".join(zeilen)


def _stil(tag: str, stil: str):
    """Inline-Stil an alle Tags eines Typs hängen, vorhandenes style (z. B. text-align) bleibt."""

    def ersetzen(m):
        attrs = m.group(1) or ""
        s = re.search(r'\sstyle="([^"]*)"', attrs)
        if s:
            alt = s.group(1).strip().rstrip(";")
            attrs = attrs.replace(s.group(0), f' style="{stil};{alt}"')
        else:
            attrs += f' style="{stil}"'
        return f"<{tag}{attrs}>"

    return lambda h: re.sub(rf"<{tag}(\s[^>]*)?>", ersetzen, h)


def markdown_zu_html(text: str) -> str:
    h = markdown.markdown(_vorbereiten(text), extensions=["tables", "sane_lists", "nl2br"])
    for tag, stil in (
        ("table", STIL_TABELLE),
        ("th", STIL_KOPF),
        ("td", STIL_ZELLE),
        ("p", STIL_ABSATZ),
        ("ul", STIL_LISTE),
        ("ol", STIL_LISTE),
    ):
        h = _stil(tag, stil)(h)
    # python-markdown schreibt text-align als eigenen Stil, Outlook versteht zusätzlich align=
    h = re.sub(r'<(td|th) style="([^"]*text-align: ?(right|center|left)[^"]*)"', r'<\1 align="\3" style="\2"', h)
    return h


def klartext(text: str) -> str:
    text = re.sub(r"<details\b.*?</details>\s*", "", text, flags=re.S | re.I)
    return text.strip()


JS = """
const html = %s;
const text = %s;
try {
  await navigator.clipboard.write([new ClipboardItem({
    'text/html': new Blob([html], {type: 'text/html'}),
    'text/plain': new Blob([text], {type: 'text/plain'})
  })]);
  return 'ok';
} catch (e1) {
  // Ersatzweg: markierten Inhalt kopieren (ältere Browser, fehlende Berechtigung)
  try {
    const el = document.createElement('div');
    el.contentEditable = 'true';
    el.style.position = 'fixed';
    el.style.left = '-10000px';
    el.innerHTML = html;
    document.body.appendChild(el);
    const r = document.createRange();
    r.selectNodeContents(el);
    const sel = window.getSelection();
    sel.removeAllRanges();
    sel.addRange(r);
    const ok = document.execCommand('copy');
    sel.removeAllRanges();
    el.remove();
    return ok ? 'ok' : 'Fehler: ' + e1;
  } catch (e2) {
    return 'Fehler: ' + e1 + ' / ' + e2;
  }
}
"""


class Action:
    def __init__(self):
        pass

    async def action(self, body: dict, __event_emitter__=None, __event_call__=None):
        nachrichten = body.get("messages") or []
        antwort = next(
            (m for m in nachrichten if m.get("id") == body.get("id")),
            nachrichten[-1] if nachrichten else None,
        )
        inhalt = (antwort or {}).get("content") or ""
        if not inhalt.strip() or __event_call__ is None:
            return None

        code = JS % (json.dumps(markdown_zu_html(inhalt)), json.dumps(klartext(inhalt)))
        try:
            ergebnis = await __event_call__({"type": "execute", "data": {"code": code}})
        except Exception as e:
            ergebnis = f"Fehler: {e}"

        if __event_emitter__:
            if ergebnis == "ok":
                meldung = {"type": "success", "content": "Für Outlook kopiert"}
            else:
                meldung = {
                    "type": "error",
                    "content": "Kopieren hat nicht geklappt. Bitte noch einmal klicken.",
                }
            await __event_emitter__({"type": "notification", "data": meldung})
        return None
