# -*- coding: utf-8 -*-
"""
sync_funcionarios.py — Cadastro de funcionários (LWHSRA001: filial, matrícula, nome, CC, função, situação)
para a tabela funcionarios do Supabase. Usado pelo formulário "Abrir SC" (abrir-sc.html): digitou a
matrícula, aparece o nome e o centro de custo.

Salvar em: C:\\painel-protheus\\sync_funcionarios.py
Rodar:     py sync_funcionarios.py        (carga completa; pode rodar todo dia)
"""
TABELA_SRA = "LWHSRA001"

import sys
import math
import traceback
from datetime import datetime

try:
    import warnings
    warnings.filterwarnings("ignore", category=UserWarning)
    import pyodbc
    import pandas as pd
    from supabase import create_client
except Exception as e:
    print(f"❌ Falta biblioteca do Python: {e}")
    input("Pressione Enter para fechar...")
    sys.exit(1)

# ── CONFIGURAÇÃO (cole aqui as suas linhas, como nos outros scripts) ──────────
SERVIDOR = "XXXX"
PORTA = "1433"
BANCO = "BEQ_LWH"
USUARIO = "XXXX"
SENHA = "XXXX"
RESSUP_URL = "XXXX"
RESSUP_KEY = "XXXX"
# ─────────────────────────────────────────────────────────────────────────────


def txt(v):
    if v is None or (isinstance(v, float) and math.isnan(v)):
        return ""
    s = str(v).strip()
    return "" if s in ("nan", "None", "NaT") else s


def main():
    g = globals()
    url = next((g[n] for n in ("RESSUP_URL", "SUPABASE_URL", "SB_URL", "URL") if n in g and str(g[n]) != "XXXX"), None)
    key = next((g[n] for n in ("RESSUP_KEY", "SUPABASE_KEY", "SUPABASE_SERVICE_KEY", "SERVICE_KEY", "SB_KEY", "KEY") if n in g and str(g[n]) != "XXXX"), None)
    if not url or not key:
        print("❌ Não achei o endereço/chave do Supabase. Cole suas linhas de configuração no lugar dos XXXX.")
        return
    sb = create_client(url, key)

    print(f"\n🔄 Funcionários ({TABELA_SRA}) — {datetime.now():%d/%m/%Y %H:%M}")
    conn = pyodbc.connect(f"DRIVER={{SQL Server}};SERVER={SERVIDOR},{PORTA};DATABASE={BANCO};UID={USUARIO};PWD={SENHA}")
    cols = set(c.strip().upper() for c in pd.read_sql(
        "SELECT COLUMN_NAME FROM BEQ_LWH.INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = ?", conn, params=[TABELA_SRA])["COLUMN_NAME"])
    if not cols:
        print(f"❌ Não achei a tabela {TABELA_SRA}.")
        return
    dele = " WHERE D_E_L_E_T_ = ' '" if "D_E_L_E_T_" in cols else ""
    df = pd.read_sql(f"""
SELECT RTRIM(FILIAL) filial, RTRIM(MATRICULA) matricula, RTRIM(NOME) nome, RTRIM(CCUSTO) cc,
       RTRIM(DESC_CC) desc_cc, RTRIM(DESFUNCAO) funcao, RTRIM(SIT_FOLHA) sit_folha
FROM BEQ_LWH.dbo.{TABELA_SRA}{dele}""", conn)
    conn.close()
    print(f"  {len(df)} funcionários lidos.")

    regs, vistos = [], {}
    agora = datetime.now().isoformat()
    for _, r in df.iterrows():
        fil, mat = txt(r["filial"]), txt(r["matricula"])
        if not fil or not mat:
            continue
        reg = {"filial": fil, "matricula": mat, "nome": txt(r["nome"]) or None, "cc": txt(r["cc"]) or None,
               "desc_cc": txt(r["desc_cc"]) or None, "funcao": txt(r["funcao"]) or None,
               "sit_folha": txt(r["sit_folha"]) or None, "atualizado_em": agora}
        k = (fil, mat)
        # a mesma matrícula repetida na mesma filial: fica a que não está desligada
        if k in vistos and (vistos[k]["sit_folha"] or "") != "D":
            continue
        vistos[k] = reg
    regs = list(vistos.values())

    LOTE = 500
    for i in range(0, len(regs), LOTE):
        sb.table("funcionarios").upsert(regs[i:i + LOTE], on_conflict="filial,matricula").execute()
        print(f"  {min(i + LOTE, len(regs))}/{len(regs)} enviados...")
    print(f"✅ {len(regs)} funcionários sincronizados.\n")


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        print(f"❌ Erro: {e}")
        traceback.print_exc()
    input("Pressione Enter para fechar...")
