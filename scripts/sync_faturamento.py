# -*- coding: utf-8 -*-
"""
sync_faturamento.py — Traz o faturamento (cabeçalho das notas de saída, SF2 = BEQ_LWH.dbo.LWHSF2001)
para a tabela faturamento_sf2 do Supabase. Usado no Comparativo mês a mês do painel de Compras.

Salvar em: C:\\painel-protheus\\sync_faturamento.py
1ª vez (carga completa):  py sync_faturamento.py --desde 20240101
Depois (dia a dia):       py sync_faturamento.py          → refaz do 1º dia do mês passado até hoje

Antes de rodar a 1ª vez: rodar docs/sql/faturamento.sql no Supabase (cria a tabela).
"""

import sys
import math
import traceback
from datetime import date, datetime

try:
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

TABELA = "LWHSF2001"
sb = None


def conectar():
    return pyodbc.connect(f"DRIVER={{SQL Server}};SERVER={SERVIDOR},{PORTA};DATABASE={BANCO};UID={USUARIO};PWD={SENHA}")


def txt(v):
    if v is None:
        return ""
    if isinstance(v, float) and math.isnan(v):
        return ""
    s = str(v).strip()
    return "" if s in ("nan", "None", "NaT") else s


def num(v):
    try:
        f = float(v)
        return None if math.isnan(f) or math.isinf(f) else round(f, 2)
    except Exception:
        return None


def data_iso(v):
    s = txt(v)
    if len(s) >= 10 and s[4] == "-":          # veio como data (2026-11-09 00:00:00)
        return s[:10]
    return f"{s[:4]}-{s[4:6]}-{s[6:8]}" if len(s) >= 8 and s[:8].isdigit() else None


def colunas(conn):
    df = pd.read_sql("SELECT COLUMN_NAME FROM BEQ_LWH.INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = ?", conn, params=[TABELA])
    return set(c.strip().upper() for c in df["COLUMN_NAME"])


def main():
    global sb
    # aceita os nomes usados nos outros scripts (RESSUP_URL/RESSUP_KEY ou SUPABASE_URL/SUPABASE_KEY...)
    g = globals()
    url = next((g[n] for n in ("RESSUP_URL", "SUPABASE_URL", "SB_URL", "URL") if n in g and str(g[n]) != "XXXX"), None)
    key = next((g[n] for n in ("RESSUP_KEY", "SUPABASE_KEY", "SUPABASE_SERVICE_KEY", "SERVICE_KEY", "SB_KEY", "KEY") if n in g and str(g[n]) != "XXXX"), None)
    if not url or not key:
        print("❌ Não achei o endereço/chave do Supabase. Cole suas linhas de configuração no lugar dos XXXX.")
        return
    sb = create_client(url, key)
    desde = None
    if "--desde" in sys.argv:
        desde = sys.argv[sys.argv.index("--desde") + 1]
    if not desde:
        hoje = date.today()
        ano, mes = (hoje.year, hoje.month - 1) if hoje.month > 1 else (hoje.year - 1, 12)
        desde = f"{ano}{mes:02d}01"
    print(f"\n🔄 Faturamento (SF2) desde {desde[6:8]}/{desde[4:6]}/{desde[:4]} — {datetime.now():%d/%m/%Y %H:%M}")

    conn = conectar()
    cols = colunas(conn)
    if not cols:
        print(f"❌ Não achei a tabela {TABELA} no BEQ_LWH.")
        return
    c = lambda nome, alias: (f"F2.{nome}" if nome in cols else "NULL") + f" AS {alias}"
    sql = ("SELECT RTRIM(F2.F2_FILIAL) AS filial, RTRIM(F2.F2_DOC) AS doc, "
           + ("RTRIM(F2.F2_SERIE)" if "F2_SERIE" in cols else "''") + " AS serie, "
           + ("RTRIM(F2.F2_CLIENTE)" if "F2_CLIENTE" in cols else "''") + " AS cliente, "
           + ("RTRIM(F2.F2_LOJA)" if "F2_LOJA" in cols else "''") + " AS loja, "
           + "F2.F2_EMISSAO AS emissao, "
           + ("RTRIM(F2.F2_TIPO)" if "F2_TIPO" in cols else "NULL") + " AS tipo, "
           + c("F2_VALBRUT", "valbrut") + ", " + c("F2_VALMERC", "valmerc") + ", " + c("F2_VALFAT", "valfat")
           + f" FROM BEQ_LWH.dbo.{TABELA} F2 WHERE F2.F2_EMISSAO >= ?"
           + (" AND F2.D_E_L_E_T_ = ' '" if "D_E_L_E_T_" in cols else ""))
    print("  Colunas: valor bruto " + ("✔" if "F2_VALBRUT" in cols else "✘") + " · mercadorias " + ("✔" if "F2_VALMERC" in cols else "✘")
          + " · faturado " + ("✔" if "F2_VALFAT" in cols else "✘") + " · tipo " + ("✔" if "F2_TIPO" in cols else "✘"))
    df = pd.read_sql(sql, conn, params=[desde])
    conn.close()
    print(f"  {len(df)} notas lidas.")

    regs, vistos = [], set()
    for _, r in df.iterrows():
        chave = (txt(r["filial"]), txt(r["doc"]), txt(r["serie"]), txt(r["cliente"]), txt(r["loja"]))
        if not chave[0] or not chave[1] or chave in vistos:
            continue
        vistos.add(chave)
        regs.append({"filial": chave[0], "doc": chave[1], "serie": chave[2], "cliente": chave[3], "loja": chave[4],
                     "emissao": data_iso(r["emissao"]), "tipo": txt(r["tipo"]) or None,
                     "valbrut": num(r["valbrut"]), "valmerc": num(r["valmerc"]), "valfat": num(r["valfat"]),
                     "atualizado_em": datetime.now().isoformat()})

    # refaz o período: apaga o que existe a partir da data e grava de novo (nota cancelada some)
    print("  🗑️  Limpando o período no Supabase...")
    sb.table("faturamento_sf2").delete().gte("emissao", data_iso(desde)).execute()
    LOTE = 500
    for i in range(0, len(regs), LOTE):
        sb.table("faturamento_sf2").upsert(regs[i:i + LOTE], on_conflict="filial,doc,serie,cliente,loja").execute()
        print(f"  {min(i + LOTE, len(regs))}/{len(regs)} enviadas...")
    print(f"✅ {len(regs)} notas de faturamento sincronizadas.\n")


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        print(f"❌ Erro: {e}")
        traceback.print_exc()
    input("Pressione Enter para fechar...")
