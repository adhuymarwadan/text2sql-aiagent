# agent.py — graph LangGraph: generate_sql -> validate (conditional) -> execute/reject -> summarize.
from typing import TypedDict

from langchain_openai import ChatOpenAI
from langgraph.graph import END, StateGraph

from db import execute_query
from guardrail import validate_sql
from prompts import SQL_SYSTEM_PROMPT, SUMMARY_SYSTEM_PROMPT


class AgentState(TypedDict, total=False):
    question: str
    sql: str            # output mentah LLM
    safe_sql: str       # sql lolos guardrail + LIMIT dipaksa
    reject_reason: str
    result: dict        # output execute_query()
    retried: bool       # self-correction hanya boleh sekali
    answer: str


llm = ChatOpenAI(model="openai/gpt-4o-mini", temperature=0,
                 base_url="https://openrouter.ai/api/v1")


def _strip_fences(text: str) -> str:
    text = text.strip()
    if text.startswith("```"):
        text = text.split("\n", 1)[-1].rsplit("```", 1)[0]
    return text.strip()


def generate_sql(state: AgentState) -> AgentState:
    resp = llm.invoke([("system", SQL_SYSTEM_PROMPT), ("user", state["question"])])
    return {"sql": _strip_fences(resp.content)}


def validate(state: AgentState) -> AgentState:
    ok, result = validate_sql(state["sql"])
    if ok:
        return {"safe_sql": result, "reject_reason": ""}
    return {"reject_reason": result}


def route_validation(state: AgentState) -> str:
    return "execute" if not state["reject_reason"] else "reject"


def execute(state: AgentState) -> AgentState:
    return {"result": execute_query(state["safe_sql"])}


def route_execution(state: AgentState) -> str:
    if state["result"]["ok"] or state.get("retried"):
        return "summarize"
    return "fix_sql"


def fix_sql(state: AgentState) -> AgentState:
    # Self-correction: kirim error DB balik ke LLM, maksimal satu kali,
    # hasilnya tetap melewati guardrail lagi sebelum dieksekusi.
    resp = llm.invoke([
        ("system", SQL_SYSTEM_PROMPT),
        ("user", f"Pertanyaan: {state['question']}\n"
                 f"SQL sebelumnya gagal: {state['safe_sql']}\n"
                 f"Error database: {state['result']['error']}\n"
                 f"Tulis ulang SQL yang benar."),
    ])
    return {"sql": _strip_fences(resp.content), "retried": True}


def reject(state: AgentState) -> AgentState:
    # Jalur tolak aman: query TIDAK PERNAH menyentuh database.
    return {"answer": f"Permintaan ditolak oleh guardrail: {state['reject_reason']}"}


def summarize(state: AgentState) -> AgentState:
    r = state["result"]
    if not r["ok"]:
        return {"answer": f"Query gagal dieksekusi: {r['error']}"}
    data = f"Kolom: {r['columns']}\nBaris ({len(r['rows'])}): {r['rows']}"
    resp = llm.invoke([
        ("system", SUMMARY_SYSTEM_PROMPT),
        ("user", f"Pertanyaan: {state['question']}\nSQL: {state['safe_sql']}\nHasil:\n{data}"),
    ])
    return {"answer": resp.content.strip()}


def build_graph():
    g = StateGraph(AgentState)
    g.add_node("generate_sql", generate_sql)
    g.add_node("validate", validate)
    g.add_node("execute", execute)
    g.add_node("fix_sql", fix_sql)
    g.add_node("reject", reject)
    g.add_node("summarize", summarize)
    g.set_entry_point("generate_sql")
    g.add_edge("generate_sql", "validate")
    g.add_conditional_edges("validate", route_validation, {"execute": "execute", "reject": "reject"})
    g.add_conditional_edges("execute", route_execution, {"summarize": "summarize", "fix_sql": "fix_sql"})
    g.add_edge("fix_sql", "validate")
    g.add_edge("summarize", END)
    g.add_edge("reject", END)
    return g.compile()


graph = build_graph()
