# -*- coding: utf-8 -*-
"""
sync_estoque_sb2.py — Sincroniza posição de estoque da SB2 (LWHSB2010) para o Supabase.
Roda uma vez por dia (horário configurável abaixo).

Tabela sincronizada:
  LWHSB2010  → estoque_sb2  (posição de estoque por filial/armazém/produto)

Instalar dependências (mesmas do sync_ressuprimento.py):
  pip install supabase pandas pyodbc schedule
"""

import ssl
ssl._create_default_https_context = ssl._create_unverified_context

import pyodbc
import pandas as pd
import schedule
import time
from datetime import datetime
from supabase import create_client, Client

# ── SUPABASE (mesmo banco do ressuprimento) ───────────────────────────────────
SUPABASE_URL = "https://vvwtqbehfwrgcmbjdniu.supabase.co"
SUPABASE_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZ2d3RxYmVoZndyZ2NtYmpkbml1Iiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc4MTUyODc1NywiZXhwIjoyMDk3MTA0NzU3fQ.bYL29QKgSWM9K4E20YNU2Gk0pJ2OjYViOiOuKCm9Grg"

# ── SQL SERVER (Protheus) — mesmas credenciais ────────────────────────────────
SERVIDOR  = "192.168.224.97"
PORTA     = "1433"
USUARIO   = "raissa.carvalho"
SENHA     = r"pZ4\5Ki3@m"
BANCO     = "BEQ_LWH"

# ── HORÁRIO DE EXECUÇÃO ───────────────────────────────────────────────────────
HORA_SYNC = "07:30"   # 30 minutos após o sync principal

# ─────────────────────────────────────────────────────────────────────────────

sb: Client = create_client(SUPABASE_URL, SUPABASE_KEY)


def conectar_protheus():
    conn_str = (
        f"DRIVER={{SQL Server}};"
        f"SERVER={SERVIDOR},{PORTA};"
        f"DATABASE={BANCO};"
        f"UID={USUARIO};"
        f"PWD={SENHA}"
    )
    return pyodbc.connect(conn_str)


def upsert_em_lotes(tabela, registros, tamanho=500, on_conflict=None):
    """Faz upsert em lotes para não estourar o limite do Supabase."""
    total = len(registros)
    enviados = 0
    for i in range(0, total, tamanho):
        lote = registros[i:i + tamanho]
        q = sb.table(tabela).upsert(lote, on_conflict=on_conflict) if on_conflict else sb.table(tabela).upsert(lote)
        q.execute()
        enviados += len(lote)
        print(f"    {enviados}/{total} enviados...")
    return enviados


def registrar_carimbo(base, registros):
    sb.table("bases_status").upsert({
        "base": base,
        "atualizado_em": datetime.now().isoformat(),
        "registros": registros
    }).execute()


# ─────────────────────────────────────────────────────────────────────────────
# SB2 → estoque_sb2
# ─────────────────────────────────────────────────────────────────────────────
def sincronizar_sb2(conn):
    print("📦 SB2 → estoque_sb2...")

    sql = """
        SELECT
            RTRIM(B2_FILIAL)   AS filial,
            RTRIM(B2_COD)      AS codigo,
            RTRIM(B2_LOCAL)    AS armazem,
            B2_QATU            AS qtd_atual,
            B2_QFIM            AS qtd_fim,
            B2_CM1             AS custo_medio,
            B2_QEMP            AS qtd_empenhada,
            B2_RESERVA         AS qtd_reserva,
            B2_SALPEDI         AS saldo_pedido,
            RTRIM(B2_BLOQUEI)  AS bloqueado,
            RTRIM(B2_STATUS)   AS status,
            RTRIM(B2_DULT)     AS dt_ult_entrada,
            RTRIM(B2_DMOV)     AS dt_ult_movimento,
            RTRIM(B2_LOCALIZ)  AS localizacao
        FROM LWHSB2010
        WHERE D_E_L_E_T_ = ''
          AND RTRIM(B2_COD) <> ''
    """

    df = pd.read_sql(sql, conn)
    print(f"  {len(df)} registros lidos.")

    registros = []
    vistos = set()

    for _, r in df.iterrows():
        filial  = str(r["filial"]  or "").strip()
        codigo  = str(r["codigo"]  or "").strip()
        armazem = str(r["armazem"] or "").strip()

        if not filial or not codigo:
            continue

        # Chave única: filial + codigo + armazem
        chave = f"{filial}|{codigo}|{armazem}"
        if chave in vistos:
            continue
        vistos.add(chave)

        bloq = str(r["bloqueado"] or "").strip().upper()
        is_bloqueado = bloq in ("1", "S", "SIM", "X", "YES", "B")

        registros.append({
            "filial":            filial,
            "codigo":            codigo,
            "armazem":           armazem,
            "qtd_atual":         float(r["qtd_atual"]     or 0),
            "qtd_fim":           float(r["qtd_fim"]       or 0),
            "custo_medio":       float(r["custo_medio"]   or 0),
            "qtd_empenhada":     float(r["qtd_empenhada"] or 0),
            "qtd_reserva":       float(r["qtd_reserva"]   or 0),
            "saldo_pedido":      float(r["saldo_pedido"]  or 0),
            "bloqueado":         is_bloqueado,
            "status":            str(r["status"]            or "").strip(),
            "dt_ult_entrada":    str(r["dt_ult_entrada"]    or "").strip() or None,
            "dt_ult_movimento":  str(r["dt_ult_movimento"]  or "").strip() or None,
            "localizacao":       str(r["localizacao"]       or "").strip() or None,
            "atualizado_em":     datetime.now().isoformat(),
        })

    print(f"  {len(registros)} registros válidos.")

    # Limpa e reinsere (igual ao consumo_mensal — garante que itens removidos somam)
    print("  Limpando estoque_sb2...")
    sb.table("estoque_sb2").delete().neq("id", 0).execute()

    for i in range(0, len(registros), 500):
        lote = registros[i:i + 500]
        sb.table("estoque_sb2").insert(lote).execute()
        print(f"  {min(i+500, len(registros))}/{len(registros)}...")

    registrar_carimbo("estoque_sb2", len(registros))
    print(f"  ✓ {len(registros)} registros salvos.")


# ─────────────────────────────────────────────────────────────────────────────
# SINCRONIZAÇÃO PRINCIPAL
# ─────────────────────────────────────────────────────────────────────────────
def sincronizar():
    print(f"\n🔄 Iniciando sync SB2... {datetime.now().strftime('%d/%m/%Y %H:%M:%S')}")
    try:
        conn = conectar_protheus()
        print("✓ Conectado ao Protheus.\n")

        sincronizar_sb2(conn)

        conn.close()
        print(f"✅ Sync SB2 concluído! {datetime.now().strftime('%d/%m/%Y %H:%M:%S')}\n")

    except Exception as e:
        print(f"❌ Erro no sync SB2: {e}\n")


# ─────────────────────────────────────────────────────────────────────────────
# INICIALIZAÇÃO
# ─────────────────────────────────────────────────────────────────────────────
if __name__ == "__main__":
    print(f"🚀 sync_estoque_sb2.py iniciado")
    print(f"⏰ Sincroniza todo dia às {HORA_SYNC}\n")

    # roda imediatamente na primeira vez
    sincronizar()

    # agenda para rodar todo dia no horário definido
    schedule.every().day.at(HORA_SYNC).do(sincronizar)

    while True:
        schedule.run_pending()
        time.sleep(60)
