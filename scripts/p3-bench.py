#!/usr/bin/env python3
"""P3-Abnahmetests A3, A4, A14 gegen llama-server (127.0.0.1:8080).

Aufruf: p3-bench.py [a3|a4|a14|all]
Misst per Streaming die Zeit bis zum ersten Denk-/Antwort-Token, die Gesamtzeit
und liest Token/s, Prefill-Tempo und MTP-Annahmequote aus den Server-Timings.
Parallel wird die GPU (Leistung, Temperatur, VRAM) per nvidia-smi abgetastet.
Es werden nur synthetische Testtexte verwendet, keine Büro-Daten.
"""
import json
import subprocess
import sys
import threading
import time
import urllib.request
import uuid

URL = "http://127.0.0.1:8080/v1/chat/completions"
SAMPLING = {"temperature": 1.0, "top_p": 0.95, "top_k": 20, "min_p": 0.0,
            "presence_penalty": 0.0, "repeat_penalty": 1.0}

EMAIL_PROMPT = (
    "Schreibe eine ausführliche, höfliche Geschäfts-E-Mail mit etwa 500 Wörtern an einen "
    "Kunden. Anlass: Die Lieferung von 40 Bürostühlen verzögert sich wegen eines "
    "Lieferengpasses beim Hersteller um drei Wochen. Erkläre die Ursache, biete als "
    "Ausgleich 5 % Rabatt und eine kostenlose Montage an, nenne den neuen Liefertermin "
    "und einen Ansprechpartner. Sie-Form, sachlicher Ton."
)


class GpuSampler(threading.Thread):
    def __init__(self):
        super().__init__(daemon=True)
        self.samples = []
        self.stop = threading.Event()

    def run(self):
        while not self.stop.is_set():
            out = subprocess.run(
                ["nvidia-smi", "--query-gpu=power.draw,temperature.gpu,memory.used,power.limit",
                 "--format=csv,noheader,nounits"], capture_output=True, text=True).stdout
            try:
                p, t, m, lim = (float(x) for x in out.strip().split(","))
                self.samples.append((p, t, m, lim))
            except ValueError:
                pass
            time.sleep(0.5)

    def summary(self):
        if not self.samples:
            return {}
        return {
            "power_limit_w": self.samples[-1][3],
            "power_max_w": round(max(s[0] for s in self.samples), 1),
            "power_avg_w": round(sum(s[0] for s in self.samples) / len(self.samples), 1),
            "temp_max_c": max(s[1] for s in self.samples),
            "vram_max_mib": max(s[2] for s in self.samples),
        }


def chat(prompt, max_tokens=4096, label=""):
    body = {"model": "qwen3.8-27b", "stream": True, "max_tokens": max_tokens,
            "messages": [{"role": "user", "content": f"Test-ID {uuid.uuid4()}\n\n{prompt}"}], **SAMPLING}
    req = urllib.request.Request(URL, data=json.dumps(body).encode(),
                                 headers={"Content-Type": "application/json"})
    t0 = time.time()
    first_reason = first_content = None
    content_chars = reason_chars = 0
    timings = {}
    with urllib.request.urlopen(req, timeout=1800) as resp:
        for raw in resp:
            line = raw.decode().strip()
            if not line.startswith("data: ") or line == "data: [DONE]":
                continue
            chunk = json.loads(line[6:])
            if chunk.get("timings"):
                timings = chunk["timings"]
            for ch in chunk.get("choices", []):
                d = ch.get("delta", {})
                if d.get("reasoning_content"):
                    first_reason = first_reason or time.time() - t0
                    reason_chars += len(d["reasoning_content"])
                if d.get("content"):
                    first_content = first_content or time.time() - t0
                    content_chars += len(d["content"])
    total = time.time() - t0
    res = {
        "label": label,
        "start_s": round(t0, 2),
        "first_think_s": round(first_reason, 2) if first_reason else None,
        "first_answer_s": round(first_content, 2) if first_content else None,
        "total_s": round(total, 2),
        "prompt_tokens": timings.get("prompt_n"),
        "prefill_tok_s": round(timings.get("prompt_per_second", 0), 1),
        "gen_tokens": timings.get("predicted_n"),
        "gen_tok_s": round(timings.get("predicted_per_second", 0), 1),
        "draft_n": timings.get("draft_n"),
        "draft_accepted": timings.get("draft_n_accepted"),
        "answer_words": None,
        "think_chars": reason_chars,
    }
    if res["draft_n"]:
        res["draft_accept_rate"] = round(res["draft_accepted"] / res["draft_n"], 2)
    res["answer_words"] = round(content_chars / 6.5)  # grobe Schätzung
    return res


def run(tests_fn):
    g = GpuSampler()
    g.start()
    try:
        results = tests_fn()
    finally:
        g.stop.set()
        g.join()
    return {"requests": results, "gpu": g.summary()}


def a3():
    return [chat(EMAIL_PROMPT, label="A3-einzeln")]


def a4():
    out = [None] * 3

    def worker(i, delay):
        time.sleep(delay)
        out[i] = chat(EMAIL_PROMPT, label=f"A4-{i + 1}")

    ts = [threading.Thread(target=worker, args=(i, d)) for i, d in enumerate([0, 0, 1])]
    for t in ts:
        t.start()
    for t in ts:
        t.join()
    return out


def a14():
    # Synthetischer langer Kontext (~54k Tokens, Slot fasst 65.536) je Slot, beide Slots gleichzeitig.
    para = ("Im Abschnitt {n} des Testprotokolls wird beschrieben, wie die Lagerverwaltung "
            "Wareneingänge erfasst, Lieferscheine prüft und Abweichungen an den Einkauf "
            "meldet. Kennzahl {n}: Durchlaufzeit {m} Minuten, Fehlerquote {k} Promille. ")
    text = "".join(para.format(n=i, m=(i * 7) % 90 + 10, k=(i * 13) % 40) for i in range(850))
    prompt = text + "\n\nFasse das Protokoll in fünf Sätzen zusammen und nenne die höchste Fehlerquote."
    out = [None] * 2

    def worker(i):
        out[i] = chat(prompt, max_tokens=2048, label=f"A14-slot{i + 1}")

    ts = [threading.Thread(target=worker, args=(i,)) for i in range(2)]
    for t in ts:
        t.start()
    for t in ts:
        t.join()
    return out


if __name__ == "__main__":
    which = sys.argv[1] if len(sys.argv) > 1 else "all"
    tests = {"a3": a3, "a4": a4, "a14": a14}
    sel = tests if which == "all" else {which: tests[which]}
    report = {name: run(fn) for name, fn in sel.items()}
    print(json.dumps(report, indent=1, ensure_ascii=False))
