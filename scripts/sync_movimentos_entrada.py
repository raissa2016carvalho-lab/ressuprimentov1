# -*- coding: utf-8 -*-
"""
sync_movimentos_entrada.py — Sincroniza entradas SD1 do Protheus para movimentos_entrada no Supabase.
Inclui: nota fiscal, fornecedor (código, loja e CNPJ), descrição do item, data de digitação e chave da NF-e.

Salvar em: C:\\painel-protheus\\sync_movimentos_entrada.py
Rodar com: py C:\\painel-protheus\\sync_movimentos_entrada.py

05/11/2026: + D1_LOJA, D1_DTDIGIT (SLA de lançamento), F1_CHVNFE (amarração exata com o NFe Master),
            A2_CGC (CNPJ do fornecedor) e filtro D_E_L_E_T_ (não traz linhas apagadas no Protheus).
            No fim chama atualizar_nfe_sd1() para o painel de Notas ficar em dia.
"""

import pyodbc
import pandas as pd
import schedule
import time
from datetime import datetime
from supabase import create_client

# ── CONFIGURAÇÃO (cole aqui as suas linhas, como no script antigo) ────────────
SERVIDOR = "XXXX"
PORTA = "1433"
BANCO = "BEQ_LWH"
USUARIO = "XXXX"
SENHA = "XXXX"
RESSUP_URL = "XXXX"
RESSUP_KEY = "XXXX"
# ─────────────────────────────────────────────────────────────────────────────

sb = create_client(RESSUP_URL, RESSUP_KEY)


def conectar():
    conn_str = (
        f"DRIVER={{SQL Server}};"
        f"SERVER={SERVIDOR},{PORTA};"
        f"DATABASE={BANCO};"
        f"UID={USUARIO};"
        f"PWD={SENHA}"
    )
    return pyodbc.connect(conn_str)


def limpar(val):
    if val is None:
        return None
    import math
    try:
        if isinstance(val, float) and math.isnan(val):
            return None
    except:
        pass
    s = str(val).strip()
    return s if s not in ('', 'nan', 'None', 'NaT') else None


def limpar_num(val):
    try:
        if val is None:
            return None
        f = float(val)
        import math
        return None if math.isnan(f) or math.isinf(f) else round(f, 4)
    except:
        return None


# Colunas da SD1 (sempre) + chave da NF-e (SF1) + CNPJ do fornecedor (SA2).
# Se a SF1 ou a SA2 não existirem com esse nome, o script tenta de novo sem elas.
COLS_SD1 = """
                RTRIM(D.D1_FILIAL)   AS filial,
                RTRIM(D.D1_COD)      AS produto,
                RTRIM(D.D1_NOME)     AS descricao,
                LEFT(D.D1_EMISSAO,6) AS mes,
                D.D1_EMISSAO         AS emissao,
                D.D1_DTDIGIT         AS dtdigit,
                RTRIM(D.D1_DOC)      AS nota_fiscal,
                RTRIM(D.D1_SERIE)    AS serie,
                RTRIM(D.D1_FORNECE)  AS fornecedor,
                RTRIM(D.D1_LOJA)     AS loja,
                RTRIM(D.D1_TES)      AS tes,
                D.D1_QUANT           AS qtd_entrada,
                D.D1_VUNIT           AS preco_unit,
                D.D1_TOTAL           AS valor_entrada"""
FILTRO = """
            WHERE D.D_E_L_E_T_ = ' '
              AND D.D1_EMISSAO >= '20250101'
              AND D.D1_QUANT > 0"""
JOIN_SF1 = """
            LEFT JOIN BEQ_LWH.dbo.LWHSF1010 F
                   ON F.F1_FILIAL = D.D1_FILIAL AND F.F1_DOC = D.D1_DOC AND F.F1_SERIE = D.D1_SERIE
                  AND F.F1_FORNECE = D.D1_FORNECE AND F.F1_LOJA = D.D1_LOJA AND F.D_E_L_E_T_ = ' '"""
JOIN_SA2 = """
            LEFT JOIN BEQ_LWH.dbo.LWHSA2010 A
                   ON A.A2_COD = D.D1_FORNECE AND A.A2_LOJA = D.D1_LOJA AND A.D_E_L_E_T_ = ' '"""

TENTATIVAS = [
    ("SD1 + chave (SF1) + CNPJ (SA2)",
     "SELECT" + COLS_SD1 + ", RTRIM(F.F1_CHVNFE) AS chave_nfe, RTRIM(A.A2_CGC) AS fornecedor_cnpj"
     "\n            FROM BEQ_LWH.dbo.LWHSD1010 D" + JOIN_SF1 + JOIN_SA2 + FILTRO),
    ("SD1 + chave (SF1)",
     "SELECT" + COLS_SD1 + ", RTRIM(F.F1_CHVNFE) AS chave_nfe, NULL AS fornecedor_cnpj"
     "\n            FROM BEQ_LWH.dbo.LWHSD1010 D" + JOIN_SF1 + FILTRO),
    ("só SD1",
     "SELECT" + COLS_SD1 + ", NULL AS chave_nfe, NULL AS fornecedor_cnpj"
     "\n            FROM BEQ_LWH.dbo.LWHSD1010 D" + FILTRO),
]


def sincronizar():
    print(f"\n🔄 Sincronizando movimentos_entrada... {datetime.now().strftime('%d/%m/%Y %H:%M:%S')}")
    try:
        conn = conectar()
        print("✅ Conectado ao Protheus.")

        df = None
        for nome, sql in TENTATIVAS:
            try:
                print(f"📥 Buscando SD1 do Protheus ({nome})...")
                df = pd.read_sql(sql, conn)
                break
            except Exception as e:
                print(f"  ⚠ Não deu com {nome}: {e}")
        conn.close()
        if df is None:
            print("❌ Nenhuma consulta funcionou.\n")
            return
        print(f"  {len(df)} registros lidos.")

        registros = []
        for _, row in df.iterrows():
            filial   = limpar(row["filial"])   or ""
            produto  = limpar(row["produto"])  or ""
            mes      = limpar(row["mes"])      or ""
            emissao  = limpar(row["emissao"])  or ""
            nf       = limpar(row["nota_fiscal"]) or ""
            serie    = limpar(row["serie"])    or ""
            if not filial or not produto or not mes:
                continue
            registros.append({
                "filial":          filial,
                "produto":         produto,
                "descricao":       limpar(row["descricao"]),
                "mes":             mes,
                "emissao":         emissao,
                "dtdigit":         limpar(row["dtdigit"]),
                "nota_fiscal":     nf,
                "serie":           serie,
                "fornecedor":      limpar(row["fornecedor"]),
                "loja":            limpar(row["loja"]),
                "fornecedor_cnpj": limpar(row["fornecedor_cnpj"]),
                "chave_nfe":       limpar(row["chave_nfe"]),
                "tes":             limpar(row["tes"]),
                "qtd_entrada":     limpar_num(row["qtd_entrada"]) or 0,
                "preco_unit":      limpar_num(row["preco_unit"]),
                "valor_entrada":   limpar_num(row["valor_entrada"]) or 0,
            })

        print(f"  {len(registros)} registros válidos.")

        # Limpar e reinserir
        print("  🗑️  Limpando movimentos_entrada...")
        sb.rpc("truncate_movimentos_entrada", {}).execute()

        print(f"  📤 Inserindo {len(registros)} registros...")
        LOTE = 500
        for i in range(0, len(registros), LOTE):
            lote = registros[i:i+LOTE]
            sb.table("movimentos_entrada").insert(lote).execute()
            print(f"  {min(i+LOTE, len(registros))}/{len(registros)} enviados...")

        print(f"✅ {len(registros)} registros sincronizados!")

        # Recalcula o cruzamento NF-e × SD1 do painel de Notas (SLA e "Lançada manual")
        try:
            sb.rpc("atualizar_nfe_sd1").execute()
            print("✅ Cruzamento com as Notas atualizado.\n")
        except Exception as e:
            print(f"  ⚠ Não atualizei o cruzamento com as Notas: {e}\n")

    except Exception as e:
        print(f"❌ Erro: {e}\n")
        import traceback
        traceback.print_exc()


# ── AGENDAMENTO ───────────────────────────────────────────────────────────────
sincronizar()

schedule.every().day.at("06:00").do(sincronizar)
schedule.every().day.at("12:00").do(sincronizar)
schedule.every().day.at("17:00").do(sincronizar)

print("⏰ Agendado para 06:00, 12:00 e 17:00. Aguardando...\n")

while True:
    schedule.run_pending()
    time.sleep(60)
