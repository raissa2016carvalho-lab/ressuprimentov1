# -*- coding: utf-8 -*-
"""
sync_itens_bloqueio.py — Bloqueio dos produtos (SB1: B1_MSBLQL = '1') para a tabela itens_bloqueio do Supabase.
Usado pelo formulário "Abrir SC" (abrir-sc.html) para mostrar se o item está bloqueado ou ativo.

Salvar em: C:\\painel-protheus\\sync_itens_bloqueio.py
Rodar:     cd /d C:\\painel-protheus && py sync_itens_bloqueio.py
A configuração é copiada sozinha do sync_descontos_epi.py da mesma pasta (ou cole as linhas no lugar dos XXXX).
"""
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


def config_dos_outros_scripts():
    """Se a configuração acima ainda está com XXXX, copia as linhas de outro sync da mesma pasta."""
    import ast, os
    g = globals()
    if all(str(g.get(n)) != "XXXX" for n in ("SERVIDOR", "USUARIO", "SENHA", "RESSUP_URL", "RESSUP_KEY")):
        return
    pasta = os.path.dirname(os.path.abspath(__file__))
    for nome in ("sync_descontos_epi.py", "sync_faturamento.py", "sync_movimentos_entrada.py", "upload_compras.py"):
        arq = os.path.join(pasta, nome)
        if not os.path.exists(arq):
            continue
        try:
            arvore = ast.parse(open(arq, encoding="utf-8", errors="ignore").read())
        except Exception:
            continue
        achou = {}
        for no in arvore.body:
            if isinstance(no, ast.Assign) and len(no.targets) == 1 and isinstance(no.targets[0], ast.Name) \
                    and isinstance(no.value, ast.Constant) and isinstance(no.value.value, str) and no.value.value != "XXXX":
                achou[no.targets[0].id] = no.value.value
        if not all(k in achou for k in ("SERVIDOR", "USUARIO", "SENHA")):
            continue
        for k, v in achou.items():
            if k in ("SERVIDOR", "PORTA", "BANCO", "USUARIO", "SENHA") or "URL" in k or "KEY" in k:
                if str(g.get(k, "XXXX")) == "XXXX":
                    g[k] = v
        print(f"  (configuração copiada de {nome})")
        return


def main():
    config_dos_outros_scripts()
    g = globals()
    url = next((g[n] for n in ("RESSUP_URL", "SUPABASE_URL", "SB_URL", "URL") if n in g and str(g[n]) != "XXXX"), None)
    key = next((g[n] for n in ("RESSUP_KEY", "SUPABASE_KEY", "SUPABASE_SERVICE_KEY", "SERVICE_KEY", "SB_KEY", "KEY") if n in g and str(g[n]) != "XXXX"), None)
    if not url or not key:
        print("❌ Não achei o endereço/chave do Supabase. Cole suas linhas de configuração no lugar dos XXXX.")
        return
    sb = create_client(url, key)

    print(f"\n🔄 Bloqueio de produtos (SB1) — {datetime.now():%d/%m/%Y %H:%M}")
    conn = pyodbc.connect(f"DRIVER={{SQL Server}};SERVER={SERVIDOR},{PORTA};DATABASE={BANCO};UID={USUARIO};PWD={SENHA}")
    # acha a tabela do cadastro de produtos (LWHSB1010, LWHSB1001...) que tem a coluna B1_MSBLQL
    tabs = pd.read_sql("SELECT TABLE_NAME FROM BEQ_LWH.INFORMATION_SCHEMA.COLUMNS "
                       "WHERE COLUMN_NAME = 'B1_MSBLQL' AND TABLE_NAME LIKE '%SB1%' ORDER BY TABLE_NAME", conn)
    if tabs.empty:
        print("❌ Não achei a tabela de produtos (SB1) com a coluna B1_MSBLQL.")
        return
    tabela = txt(tabs["TABLE_NAME"].iloc[0])
    cols = set(c.strip().upper() for c in pd.read_sql(
        "SELECT COLUMN_NAME FROM BEQ_LWH.INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = ?", conn, params=[tabela])["COLUMN_NAME"])
    dele = " WHERE D_E_L_E_T_ = ' '" if "D_E_L_E_T_" in cols else ""
    df = pd.read_sql(f"SELECT RTRIM(B1_COD) codigo, RTRIM(B1_MSBLQL) blq FROM BEQ_LWH.dbo.{tabela}{dele}", conn)
    conn.close()
    print(f"  {len(df)} produtos lidos de {tabela}.")

    agora = datetime.now().isoformat()
    regs = {}
    for _, r in df.iterrows():
        cod = txt(r["codigo"])
        if not cod:
            continue
        bloq = txt(r["blq"]) == "1"
        # o mesmo código em mais de uma filial do cadastro: bloqueado só se estiver bloqueado em todas
        regs[cod] = {"codigo": cod, "bloqueado": bloq and regs.get(cod, {"bloqueado": True})["bloqueado"], "atualizado_em": agora}
    lista = list(regs.values())
    LOTE = 1000
    for i in range(0, len(lista), LOTE):
        sb.table("itens_bloqueio").upsert(lista[i:i + LOTE], on_conflict="codigo").execute()
        print(f"  {min(i + LOTE, len(lista))}/{len(lista)} enviados...")
    print(f"✅ {len(lista)} produtos ({sum(1 for x in lista if x['bloqueado'])} bloqueados).\n")


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        print(f"❌ Erro: {e}")
        traceback.print_exc()
    input("Pressione Enter para fechar...")
