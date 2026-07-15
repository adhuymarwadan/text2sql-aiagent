# main.py — CLI loop: input -> graph -> jawaban.
import sys

sys.stdout.reconfigure(encoding="utf-8")  # console Windows default cp1252, crash di karakter Unicode

from agent import graph

print("Text-to-SQL Agent (ketik 'exit' untuk keluar)")
while True:
    try:
        question = input("\nTanya> ").strip()
    except (EOFError, KeyboardInterrupt):
        break
    if not question:
        continue
    if question.lower() in {"exit", "quit", "keluar"}:
        break
    state = graph.invoke({"question": question})
    if state.get("safe_sql"):
        print(f"[SQL] {state['safe_sql']}")
    print(state["answer"])
