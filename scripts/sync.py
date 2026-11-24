# -*- coding: utf-8 -*-
"""
sync.py — Sincroniza os pedidos de compra (LWHSC7010) para a tabela pedidos_compra do banco de ressuprimento,
4x/dia (09h, 12h, 16h, 17h). Usada pelo painel principal, pela posição de estoque e pelo último preço de compra.

24/11/2026: deixou de gravar no projeto Supabase antigo (painel-protheus / manutenção), que foi desativado.
            Só grava no ressuprimento (todos os status do Protheus) e remove os pedidos que sumiram do Protheus.

Salvar em: C:\\painel-protheus\\sync.py
Rodar com: py C:\\painel-protheus\\sync.py
"""

import pyodbc
from supabase import create_client, Client
import pandas as pd
import schedule
import time
from datetime import datetime

# ── SQL SERVER (Protheus) ─────────────────────────────────────────────────────
SERVIDOR = "XXXX"
PORTA    = "1433"
USUARIO  = "XXXX"
SENHA    = "XXXX"
BANCO    = "BEQ_LWH"

# ── SUPABASE (ressuprimento) ──────────────────────────────────────────────────
RESSUP_URL = "XXXX"
RESSUP_KEY = "XXXX"

sb2: Client = create_client(RESSUP_URL, RESSUP_KEY)


def conectar_protheus():
    conn_str = (
        f"DRIVER={{SQL Server}};"
        f"SERVER={SERVIDOR},{PORTA};"
        f"DATABASE={BANCO};"
        f"UID={USUARIO};"
        f"PWD={SENHA}"
    )
    return pyodbc.connect(conn_str)


def sincronizar():
    print(f"\n🔄 Sincronizando pedidos... {datetime.now().strftime('%d/%m/%Y %H:%M:%S')}")
    try:
        conn = conectar_protheus()

        # ── Busca TODOS os pedidos desde jan/2024 — incluindo eliminados/rejeitados
        print("📥 Buscando pedidos de SC7010 (todos os status)...")
        sql = """
            SELECT
                C7_FILIAL, C7_NUM, C7_ITEM, C7_EMISSAO, [DT ENTREGA],
                C7_PRODUTO, C7_DESCRI, C7_QUANT, C7_UM, C7_TOTAL, C7_NUMSC,
                C7_GRPPROD, C7_USER, C7_COMPRADOR, C7_FORNECE, C7_OBS,
                C7_CONAPRO, C7_ENCER, C7_QUJE, STATUS_DESC
            FROM LWHSC7010
            WHERE C7_EMISSAO >= '20240101'
        """
        pedidos = pd.read_sql(sql, conn)
        conn.close()
        print(f"  Total buscado do Protheus: {len(pedidos)} registros")

        pedidos_ressup = {}      # id -> registro (fica o último, se vier repetido)
        for _, row in pedidos.iterrows():
            item   = str(row["C7_ITEM"]   or "").strip()
            filial = str(row["C7_FILIAL"] or "").strip()
            num    = str(row["C7_NUM"]    or "").strip()
            doc_id = f"{filial}_{num}_{item}"
            pedidos_ressup[doc_id] = {
                "id":           doc_id,
                "c7_filial":    filial,
                "c7_num":       num,
                "c7_item":      item,
                "c7_emissao":   str(row["C7_EMISSAO"]   or "").strip(),
                "dt_entrega":   str(row["DT ENTREGA"]   or "").strip(),
                "c7_produto":   str(row["C7_PRODUTO"]   or "").strip(),
                "c7_descri":    str(row["C7_DESCRI"]    or "").strip(),
                "c7_quant":     float(row["C7_QUANT"]   or 0),
                "c7_um":        str(row["C7_UM"]        or "").strip(),
                "c7_total":     float(row["C7_TOTAL"]   or 0),
                "c7_numsc":     str(row["C7_NUMSC"]     or "").strip(),
                "c7_grpprod":   str(row["C7_GRPPROD"]   or "").strip(),
                "c7_comprador": str(row["C7_COMPRADOR"] or row["C7_USER"] or "").strip(),
                "c7_fornece":   str(row["C7_FORNECE"]   or "").strip(),
                "c7_obs":       str(row["C7_OBS"]       or "").strip(),
                "status_desc":  str(row["STATUS_DESC"]  or "").strip().upper(),
            }
        lista = list(pedidos_ressup.values())
        print(f"  ✓ {len(lista)} pedidos únicos")

        # ── Upsert ressuprimento (todos os status reais do Protheus)
        print("🔄 Gravando no banco de ressuprimento...")
        enviados = 0
        for i in range(0, len(lista), 500):
            sb2.table("pedidos_compra").upsert(lista[i:i + 500]).execute()
            enviados += len(lista[i:i + 500])
            print(f"    {enviados} enviados...")
        print(f"  ✓ {enviados} pedidos gravados")

        # ── Remove os pedidos que sumiram do Protheus (apagados fisicamente)
        print("👻 Verificando pedidos que sumiram do Protheus...")
        todos_ids = []
        offset = 0
        while True:
            result = sb2.table("pedidos_compra").select("id").range(offset, offset + 999).execute()
            if not result.data:
                break
            todos_ids.extend([r["id"] for r in result.data])
            if len(result.data) < 1000:
                break
            offset += 1000
        fantasmas = [i for i in todos_ids if i not in pedidos_ressup]
        # trava: se o Protheus devolveu pouca coisa (falha na consulta), não apaga nada
        if fantasmas and len(lista) > 0.8 * len(todos_ids):
            for i in range(0, len(fantasmas), 500):
                sb2.table("pedidos_compra").delete().in_("id", fantasmas[i:i + 500]).execute()
            print(f"  ✓ {len(fantasmas)} removido(s)")
        elif fantasmas:
            print(f"  ⚠ {len(fantasmas)} sumiram, mas o Protheus devolveu poucos pedidos agora. Não apaguei nada.")
        else:
            print("  ✓ Nenhum")

        try:
            sb2.table("sync_log").upsert({"chave": "pedidos_compra", "atualizado_em": datetime.now().isoformat(),
                                          "total": len(lista)}, on_conflict="chave").execute()
        except Exception as e:
            print(f"  ⚠ Não registrei a hora no sync_log: {e}")

        print("✅ Sincronizado com sucesso!\n")

    except Exception as e:
        print(f"❌ Erro na sincronização: {e}\n")


# ── AGENDAMENTO ───────────────────────────────────────────────────────────────
sincronizar()
schedule.every().day.at("09:00").do(sincronizar)
schedule.every().day.at("12:00").do(sincronizar)
schedule.every().day.at("16:00").do(sincronizar)
schedule.every().day.at("17:00").do(sincronizar)

print("⏰ Agendado para 09:00, 12:00, 16:00 e 17:00 todos os dias. Aguardando...\n")

while True:
    schedule.run_pending()
    time.sleep(60)
