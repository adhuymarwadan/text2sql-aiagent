# app.py — web UI Streamlit, jalankan: streamlit run app.py
import streamlit as st

from agent import graph

st.set_page_config(page_title="Text-to-SQL Agent", page_icon="🛢️")
st.title("🛢️ Text-to-SQL Agent")
st.caption("Monitoring infrastruktur IT — tanya dalam Bahasa Indonesia, "
           "dijawab dari database dengan guardrail berlapis.")

if "history" not in st.session_state:
    st.session_state.history = []

for msg in st.session_state.history:
    with st.chat_message(msg["role"]):
        if msg.get("sql"):
            st.code(msg["sql"], language="sql")
        st.markdown(msg["content"])

question = st.chat_input("contoh: Tampilkan server yang offline di cabang Balikpapan")
if question:
    st.session_state.history.append({"role": "user", "content": question})
    with st.chat_message("user"):
        st.markdown(question)
    with st.chat_message("assistant"):
        with st.spinner("Menulis dan memvalidasi SQL..."):
            state = graph.invoke({"question": question})
        sql = state.get("safe_sql")
        if sql:
            st.code(sql, language="sql")
        st.markdown(state["answer"])
    st.session_state.history.append(
        {"role": "assistant", "sql": sql, "content": state["answer"]}
    )
