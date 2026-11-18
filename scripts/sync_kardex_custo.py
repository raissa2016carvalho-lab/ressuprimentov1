# -*- coding: utf-8 -*-
"""
sync_kardex_custo.py — Movimentos de estoque COM CUSTO para validar o custo médio.

Traz do Protheus para o Supabase:
  kardex_mov    SD1 (entradas: D1_CUSTO), SD2 (saídas: D2_CUSTO1) e SD3 (internos: D3_CUSTO1, D3_TM, D3_CF),
                só os que movimentam estoque (TES com F4_ESTOQUE = 'S'), com armazém, data e D_NUMSEQ
  kardex_sb9    saldos iniciais dos fechamentos (B9_QINI, B9_VINI1, B9_CM1)
  kardex_sb2    saldo atual (B2_QATU, B2_VATU1, B2_CM1)
  kardex_param  parâmetros do custo (MV_CUSMED, MV_CUSFIL, MV_ULMES ...), se a tabela SX6 estiver no banco

Salvar em: C:\\painel-protheus\\sync_kardex_custo.py
Rodar:     cd /d C:\\painel-protheus && py sync_kardex_custo.py                 (desde 01/01/2026)
           cd /d C:\\painel-protheus && py sync_kardex_custo.py --desde 20250101
A configuração é copiada sozinha do sync_descontos_epi.py da mesma pasta (ou cole as linhas no lugar dos XXXX).
As tabelas do Protheus (SD1, SD2, SD3, SB9, SB2, SF4, SX6) são achadas pelo nome das colunas.
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
DESDE_PADRAO = "20260101"


def txt(v):
    if v is None or (isinstance(v, float) and math.isnan(v)):
        return ""
    s = str(v).strip()
    return "" if s in ("nan", "None", "NaT") else s


def num(v):
    try:
        f = float(v)
        return 0.0 if math.isnan(f) or math.isinf(f) else round(f, 6)
    except Exception:
        return 0.0


def data_iso(v):
    s = txt(v)
    return f"{s[:4]}-{s[4:6]}-{s[6:8]}" if len(s) >= 8 and s[:8].isdigit() else None


def config_dos_outros_scripts():
    """Se a configuração acima ainda está com XXXX, copia as linhas de outro sync da mesma pasta."""
    import ast, os
    g = globals()
    if all(str(g.get(n)) != "XXXX" for n in ("SERVIDOR", "USUARIO", "SENHA", "RESSUP_URL", "RESSUP_KEY")):
        return
    pasta = os.path.dirname(os.path.abspath(__file__))
    for nome in ("sync_descontos_epi.py", "sync_funcionarios.py", "sync_faturamento.py", "sync_movimentos_entrada.py", "upload_compras.py"):
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


def tabela_com(conn, coluna, prefixo):
    """Acha a tabela do Protheus que tem a coluna (ex.: D3_NUMSEQ) e cujo nome contém o prefixo (ex.: SD3)."""
    df = pd.read_sql("SELECT TABLE_NAME, COUNT(*) n FROM BEQ_LWH.INFORMATION_SCHEMA.COLUMNS "
                     "WHERE COLUMN_NAME = ? AND TABLE_NAME LIKE ? GROUP BY TABLE_NAME ORDER BY TABLE_NAME",
                     conn, params=[coluna, f"%{prefixo}%"])
    if df.empty:
        return None, set()
    # prefere a tabela da empresa 01 (…010) quando houver mais de uma
    nomes = [txt(x) for x in df["TABLE_NAME"]]
    nome = next((n for n in nomes if n.upper().endswith("010")), nomes[0])
    cols = set(c.strip().upper() for c in pd.read_sql(
        "SELECT COLUMN_NAME FROM BEQ_LWH.INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = ?", conn, params=[nome])["COLUMN_NAME"])
    return nome, cols


def enviar(sb, tabela, regs, conflito, lote=1000):
    for i in range(0, len(regs), lote):
        for tent in range(4):
            try:
                sb.table(tabela).upsert(regs[i:i + lote], on_conflict=conflito).execute()
                break
            except Exception as e:
                if tent == 3:
                    raise
                print(f"    (erro ao enviar, tentando de novo: {e})")
        if (i // lote) % 10 == 0 or i + lote >= len(regs):
            print(f"    {min(i + lote, len(regs))}/{len(regs)}")


def main():
    config_dos_outros_scripts()
    g = globals()
    url = next((g[n] for n in ("RESSUP_URL", "SUPABASE_URL", "SB_URL", "URL") if n in g and str(g[n]) != "XXXX"), None)
    key = next((g[n] for n in ("RESSUP_KEY", "SUPABASE_KEY", "SUPABASE_SERVICE_KEY", "SERVICE_KEY", "SB_KEY", "KEY") if n in g and str(g[n]) != "XXXX"), None)
    if not url or not key:
        print("❌ Não achei o endereço/chave do Supabase. Cole suas linhas de configuração no lugar dos XXXX.")
        return
    sb = create_client(url, key)
    desde = sys.argv[sys.argv.index("--desde") + 1] if "--desde" in sys.argv else DESDE_PADRAO
    print(f"\n🔄 Kardex com custo desde {desde[6:8]}/{desde[4:6]}/{desde[:4]} — {datetime.now():%d/%m/%Y %H:%M}")
    conn = pyodbc.connect(f"DRIVER={{SQL Server}};SERVER={SERVIDOR},{PORTA};DATABASE={BANCO};UID={USUARIO};PWD={SENHA}")
    agora = datetime.now().isoformat()

    t_sd1, c_sd1 = tabela_com(conn, "D1_NUMSEQ", "SD1")
    t_sd2, c_sd2 = tabela_com(conn, "D2_NUMSEQ", "SD2")
    t_sd3, c_sd3 = tabela_com(conn, "D3_NUMSEQ", "SD3")
    t_sb9, c_sb9 = tabela_com(conn, "B9_VINI1", "SB9")
    t_sb2, c_sb2 = tabela_com(conn, "B2_VATU1", "SB2")
    t_sf4, c_sf4 = tabela_com(conn, "F4_ESTOQUE", "SF4")
    print(f"  Tabelas: SD1={t_sd1} SD2={t_sd2} SD3={t_sd3} SB9={t_sb9} SB2={t_sb2} SF4={t_sf4}")
    if not (t_sd1 and t_sd3):
        print("❌ Não achei a SD1 ou a SD3.")
        return
    dl = lambda cols, a="": f" AND {a}D_E_L_E_T_ = ' '" if "D_E_L_E_T_" in cols else ""

    # TES que movimentam estoque (F4_ESTOQUE = 'S')
    tes_est = {}
    if t_sf4:
        df = pd.read_sql(f"SELECT RTRIM(F4_FILIAL) fil, RTRIM(F4_CODIGO) cod, RTRIM(F4_ESTOQUE) est FROM BEQ_LWH.dbo.{t_sf4} WHERE 1=1{dl(c_sf4)}", conn)
        for _, r in df.iterrows():
            tes_est[(txt(r["fil"]), txt(r["cod"]))] = txt(r["est"]) == "S"
    def mexe(fil, tes):
        if not tes_est:
            return True
        for k in ((fil, tes), (fil[:2], tes), ("", tes)):
            if k in tes_est:
                return tes_est[k]
        return next((v for (f, t), v in tes_est.items() if t == tes), True)

    regs = []
    # SD1 — entradas (devolução de venda também entra; D1_TIPO = 'D')
    df = pd.read_sql(f"""
SELECT R_E_C_N_O_ rec, RTRIM(D1_FILIAL) fil, RTRIM(D1_COD) prod, RTRIM(D1_LOCAL) arm, D1_DTDIGIT dt, RTRIM(D1_NUMSEQ) seq,
       RTRIM(D1_TES) tes, RTRIM(D1_TIPO) tipo, D1_QUANT qt, D1_CUSTO custo, D1_TOTAL tot, RTRIM(D1_DOC) doc
FROM BEQ_LWH.dbo.{t_sd1} WHERE D1_DTDIGIT >= ?{dl(c_sd1)}""", conn, params=[desde])
    print(f"  SD1: {len(df)} linhas")
    for _, r in df.iterrows():
        fil, tes = txt(r["fil"]), txt(r["tes"])
        if tes and not mexe(fil, tes):
            continue
        regs.append({"chave": f"SD1|{int(r['rec'])}", "origem": "SD1", "filial": fil, "produto": txt(r["prod"]), "armazem": txt(r["arm"]),
                     "data": data_iso(r["dt"]), "numseq": txt(r["seq"]), "tm": tes, "cf": txt(r["tipo"]), "entrada": True,
                     "quantidade": num(r["qt"]), "custo": num(r["custo"]), "valor_nf": num(r["tot"]), "doc": txt(r["doc"]),
                     "estorno": False, "atualizado_em": agora})
    # SD2 — saídas (devolução de compra: D2_TIPO = 'D'; transferência entre filiais sai por aqui)
    if t_sd2:
        df = pd.read_sql(f"""
SELECT R_E_C_N_O_ rec, RTRIM(D2_FILIAL) fil, RTRIM(D2_COD) prod, RTRIM(D2_LOCAL) arm, D2_EMISSAO dt, RTRIM(D2_NUMSEQ) seq,
       RTRIM(D2_TES) tes, RTRIM(D2_TIPO) tipo, D2_QUANT qt, D2_CUSTO1 custo, D2_TOTAL tot, RTRIM(D2_DOC) doc
FROM BEQ_LWH.dbo.{t_sd2} WHERE D2_EMISSAO >= ?{dl(c_sd2)}""", conn, params=[desde])
        print(f"  SD2: {len(df)} linhas")
        for _, r in df.iterrows():
            fil, tes = txt(r["fil"]), txt(r["tes"])
            if tes and not mexe(fil, tes):
                continue
            regs.append({"chave": f"SD2|{int(r['rec'])}", "origem": "SD2", "filial": fil, "produto": txt(r["prod"]), "armazem": txt(r["arm"]),
                         "data": data_iso(r["dt"]), "numseq": txt(r["seq"]), "tm": tes, "cf": txt(r["tipo"]), "entrada": False,
                         "quantidade": num(r["qt"]), "custo": num(r["custo"]), "valor_nf": num(r["tot"]), "doc": txt(r["doc"]),
                         "estorno": False, "atualizado_em": agora})
    # SD3 — internos: D3_TM até 499 entra (DE), 500 em diante sai (RE)
    est = "RTRIM(D3_ESTORNO)" if "D3_ESTORNO" in c_sd3 else "''"
    df = pd.read_sql(f"""
SELECT R_E_C_N_O_ rec, RTRIM(D3_FILIAL) fil, RTRIM(D3_COD) prod, RTRIM(D3_LOCAL) arm, D3_EMISSAO dt, RTRIM(D3_NUMSEQ) seq,
       RTRIM(D3_TM) tm, RTRIM(D3_CF) cf, D3_QUANT qt, D3_CUSTO1 custo, RTRIM(D3_DOC) doc, {est} estorno
FROM BEQ_LWH.dbo.{t_sd3} WHERE D3_EMISSAO >= ?{dl(c_sd3)}""", conn, params=[desde])
    print(f"  SD3: {len(df)} linhas")
    for _, r in df.iterrows():
        tm, cf = txt(r["tm"]), txt(r["cf"])
        try:
            entra = int(tm) < 500
        except Exception:
            entra = cf.upper().startswith("DE") or cf.upper().startswith("PR")
        regs.append({"chave": f"SD3|{int(r['rec'])}", "origem": "SD3", "filial": txt(r["fil"]), "produto": txt(r["prod"]), "armazem": txt(r["arm"]),
                     "data": data_iso(r["dt"]), "numseq": txt(r["seq"]), "tm": tm, "cf": cf, "entrada": entra,
                     "quantidade": num(r["qt"]), "custo": num(r["custo"]), "valor_nf": None, "doc": txt(r["doc"]),
                     "estorno": txt(r["estorno"]) == "S", "atualizado_em": agora})
    regs = [x for x in regs if x["data"] and x["produto"]]
    print(f"  Limpando o período no Supabase e enviando {len(regs)} movimentos...")
    sb.table("kardex_mov").delete().gte("data", data_iso(desde)).execute()
    enviar(sb, "kardex_mov", regs, "chave")

    # SB9 — fechamentos (saldo inicial de cada período) a partir de 1 ano antes do início
    if t_sb9:
        ini9 = f"{int(desde[:4]) - 1}{desde[4:]}"
        df = pd.read_sql(f"""
SELECT RTRIM(B9_FILIAL) fil, RTRIM(B9_COD) prod, RTRIM(B9_LOCAL) arm, B9_DATA dt, B9_QINI q, B9_VINI1 v, {'B9_CM1' if 'B9_CM1' in c_sb9 else '0'} cm
FROM BEQ_LWH.dbo.{t_sb9} WHERE B9_DATA >= ?{dl(c_sb9)}""", conn, params=[ini9])
        r9 = {}
        for _, r in df.iterrows():
            d = data_iso(r["dt"])
            if not d:
                continue
            k = (txt(r["fil"]), txt(r["prod"]), txt(r["arm"]), d)
            r9[k] = {"filial": k[0], "produto": k[1], "armazem": k[2], "data": d, "qini": num(r["q"]), "vini": num(r["v"]), "cm": num(r["cm"])}
        print(f"  SB9: {len(r9)} saldos iniciais")
        enviar(sb, "kardex_sb9", list(r9.values()), "filial,produto,armazem,data")

    # SB2 — saldo atual
    if t_sb2:
        df = pd.read_sql(f"""
SELECT RTRIM(B2_FILIAL) fil, RTRIM(B2_COD) prod, RTRIM(B2_LOCAL) arm, B2_QATU q, B2_VATU1 v, B2_CM1 cm
FROM BEQ_LWH.dbo.{t_sb2} WHERE 1=1{dl(c_sb2)}""", conn)
        r2 = {}
        for _, r in df.iterrows():
            k = (txt(r["fil"]), txt(r["prod"]), txt(r["arm"]))
            r2[k] = {"filial": k[0], "produto": k[1], "armazem": k[2], "qatu": num(r["q"]), "vatu": num(r["v"]), "cm": num(r["cm"]), "atualizado_em": agora}
        print(f"  SB2: {len(r2)} saldos")
        enviar(sb, "kardex_sb2", list(r2.values()), "filial,produto,armazem")

    # SX6 — parâmetros do custo (se existir no banco)
    try:
        t_sx6, c_sx6 = tabela_com(conn, "X6_VAR", "SX6")
        if t_sx6:
            nomes = ("MV_CUSMED", "MV_CUSFIL", "MV_CUSZERO", "MV_ULMES", "MV_DBLQMOV", "MV_330ATCM", "MV_SEQ300", "MV_MOEDACM", "MV_CMPEDES", "MV_NEGESTR")
            lista = ",".join(f"'{n}'" for n in nomes)
            df = pd.read_sql(f"SELECT RTRIM(X6_FIL) fil, RTRIM(X6_VAR) nome, RTRIM(X6_CONTEUD) val FROM BEQ_LWH.dbo.{t_sx6} WHERE RTRIM(X6_VAR) IN ({lista}){dl(c_sx6)}", conn)
            pr = {(txt(r["fil"]), txt(r["nome"])): {"filial": txt(r["fil"]), "nome": txt(r["nome"]), "valor": txt(r["val"])} for _, r in df.iterrows()}
            print(f"  SX6: {len(pr)} parâmetros ({t_sx6})")
            if pr:
                enviar(sb, "kardex_param", list(pr.values()), "filial,nome")
        else:
            print("  (SX6 não está no banco; parâmetros ficam de fora)")
    except Exception as e:
        print("  (não consegui ler os parâmetros:", e, ")")
    conn.close()
    print("✅ Kardex com custo sincronizado.\n")


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        print(f"❌ Erro: {e}")
        traceback.print_exc()
    input("Pressione Enter para fechar...")
