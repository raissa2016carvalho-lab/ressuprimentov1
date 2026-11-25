# -*- coding: utf-8 -*-
"""
rodar_syncs.py — o "maestro": UMA janela que roda todos os syncs dos painéis B&Q, um de cada vez, nos horários abaixo.

Salvar em: C:\\painel-protheus\\rodar_syncs.py   (na mesma pasta dos syncs)
Rodar:     cd /d C:\\painel-protheus && py rodar_syncs.py

Outros usos:
  py rodar_syncs.py --listar                → mostra os syncs e os horários
  py rodar_syncs.py --agora estoque         → roda só esse sync agora (pelo nome da tabela abaixo) e sai
  py rodar_syncs.py --sem-rodada-inicial    → não roda tudo ao abrir; só espera os horários

Como funciona:
  - Ao abrir, roda todos uma vez (na ordem da tabela) e depois segue os horários.
  - Nunca roda dois ao mesmo tempo (era isso que dava timeout e travava o login do Protheus).
  - Os syncs NÃO precisam ser alterados: cada um é chamado no modo "roda uma vez e sai"
    (o relógio interno dele e o "Pressione Enter" são ignorados).
  - Se um der erro, avisa, tenta de novo 15 minutos depois (uma vez) e os outros seguem.
  - Tudo fica no arquivo logs\\syncs_AAAA-MM-DD.log e no banco (tabela sync_log, chave "rodar:<nome>"),
    para o painel mostrar a hora da última atualização e avisar quando algum falhar.
"""

# ── TABELA DE SYNCS E HORÁRIOS ────────────────────────────────────────────────────────────────────────
# nome curto, arquivo, argumentos, horários ("HH:MM") ou intervalo em minutos, tempo máximo (minutos)
SYNCS = [
    # Notas fiscais
    dict(nome="nfe_master",     arquivo="sync_nfe_master.py",         args=[], cada_min=30,                                  limite=40),
    dict(nome="mov_entrada",    arquivo="sync_movimentos_entrada.py", args=[], horas=["06:30", "12:00", "17:00"],             limite=60),
    # Ressuprimento / painel principal
    dict(nome="cadastros",      arquivo="sync_ressuprimento.py",      args=[], horas=["07:00"],                               limite=60),
    dict(nome="funcionarios",   arquivo="sync_funcionarios.py",       args=[], horas=["07:00"],                               limite=30),
    dict(nome="itens_bloqueio", arquivo="sync_itens_bloqueio.py",     args=[], horas=["07:00"],                               limite=30),
    dict(nome="sc_pedidos_v2",  arquivo="sync_sc_pedidos_v2.py",      args=[], horas=["07:00", "09:00", "12:00", "16:00", "17:00"], limite=60),
    dict(nome="pedidos_compra", arquivo="sync.py",                    args=[], horas=["09:00", "12:00", "16:00", "17:00"],    limite=60),
    dict(nome="compras",        arquivo="upload_compras.py",          args=[], horas=["09:30", "12:30", "16:30"],             limite=60),
    # Estoque
    dict(nome="estoque",        arquivo="sync_estoque_sb2.py",        args=[], horas=["07:30"],                               limite=60),
    dict(nome="sd3",            arquivo="sync_sd3.py",                args=[], horas=["07:30"],                               limite=60),
    dict(nome="sd2",            arquivo="sync_sd2.py",                args=[], horas=["07:30"],                               limite=30),
    dict(nome="consumo_anual",  arquivo="sync_consumo_anual.py",      args=[], horas=["07:30"],                               limite=30),
    # Fechamento de consumo
    dict(nome="consumo_scp",    arquivo="sync_consumo_scp.py",        args=[], horas=["06:30", "12:00", "17:30"],             limite=60),
    dict(nome="devolucoes",     arquivo="sync_movmult.py",            args=[], horas=["08:00"],                               limite=60),
    # EPI
    dict(nome="descontos_epi",  arquivo="sync_descontos_epi.py",      args=[], horas=["08:00"],                               limite=60),
    dict(nome="entregas",       arquivo="sync_entregas.py",           args=[], horas=["18:00"],                               limite=60),
    # Compras (comparativo)
    dict(nome="faturamento",    arquivo="sync_faturamento.py",        args=[], horas=["18:00"],                               limite=30),
]
ESPERA_REPETIR_MIN = 15      # se der erro, tenta de novo depois de X minutos (uma vez)

import os, sys, time, json, threading, subprocess, datetime, re

PASTA = os.path.dirname(os.path.abspath(__file__))


# ═════════════════════════════════════════════════════════════════════════════════════════════════════
# MODO FILHO: roda UM sync uma vez e sai.  (py rodar_syncs.py --um sync_xxx.py [args])
# Troca a biblioteca "schedule" por uma de mentira (o laço "while True: schedule.run_pending()" do sync
# termina na hora) e faz o input("Pressione Enter...") seguir sozinho.
# ═════════════════════════════════════════════════════════════════════════════════════════════════════
def _modo_filho(arquivo, args):
    import types, builtins, runpy

    class _Qualquer:                       # every().day.at("07:00").do(f) → não faz nada
        def __getattr__(self, _):
            return self
        def __call__(self, *a, **k):
            return self

    class _FimDoSync(BaseException):
        pass

    falso = types.ModuleType("schedule")
    falso.every = lambda *a, **k: _Qualquer()
    def _run_pending(*a, **k):
        raise _FimDoSync()
    falso.run_pending = _run_pending
    falso.run_all = lambda *a, **k: None
    falso.clear = lambda *a, **k: None
    falso.jobs = []
    sys.modules["schedule"] = falso
    builtins.input = lambda *a, **k: ""

    sys.argv = [arquivo] + list(args)
    sys.path.insert(0, os.path.dirname(os.path.abspath(arquivo)))
    try:
        runpy.run_path(arquivo, run_name="__main__")
    except _FimDoSync:
        pass
    sys.stdout.flush()


# ═════════════════════════════════════════════════════════════════════════════════════════════════════
# MAESTRO
# ═════════════════════════════════════════════════════════════════════════════════════════════════════
def _agora():
    return datetime.datetime.now()


def _log(txt, tela=True):
    os.makedirs(os.path.join(PASTA, "logs"), exist_ok=True)
    linha = f"{_agora():%d/%m %H:%M:%S}  {txt}"
    with open(os.path.join(PASTA, "logs", f"syncs_{_agora():%Y-%m-%d}.log"), "a", encoding="utf-8") as f:
        f.write(linha + "\n")
    if tela:
        try:
            print(linha, flush=True)
        except Exception:
            print(linha.encode("ascii", "replace").decode(), flush=True)


# ── banco: usa o endereço/chave que já estão nos outros syncs da pasta ───────────────────────────────
_SB = None
def _banco():
    global _SB
    if _SB is not None:
        return _SB or None
    _SB = False
    try:
        import ast
        from supabase import create_client
        for nome in ("sync_movimentos_entrada.py", "sync_nfe_master.py", "sync_sc_pedidos_v2.py", "sync_consumo_scp.py"):
            arq = os.path.join(PASTA, nome)
            if not os.path.exists(arq):
                continue
            achou = {}
            for no in ast.parse(open(arq, encoding="utf-8", errors="ignore").read()).body:
                if isinstance(no, ast.Assign) and len(no.targets) == 1 and isinstance(no.targets[0], ast.Name) \
                        and isinstance(no.value, ast.Constant) and isinstance(no.value.value, str):
                    achou[no.targets[0].id] = no.value.value
            url = achou.get("RESSUP_URL") or achou.get("SUPABASE_URL")
            key = achou.get("RESSUP_KEY") or achou.get("SUPABASE_KEY")
            if url and key and "XXXX" not in (url + key):
                _SB = create_client(url, key)
                return _SB
    except Exception as e:
        _log(f"(não consegui conectar no banco para registrar as rodadas: {e})")
    return None


def _registrar(nome, status, inicio, fim, msg=""):
    sb = _banco()
    if not sb:
        return
    reg = {"chave": "rodar:" + nome, "atualizado_em": fim.astimezone().isoformat(),
           "status": status, "inicio": inicio.astimezone().isoformat(),
           "duracao_s": int((fim - inicio).total_seconds()), "mensagem": (msg or "")[:500]}
    try:
        sb.table("sync_log").upsert(reg, on_conflict="chave").execute()
    except Exception:
        try:   # banco ainda sem as colunas novas: grava só a hora
            sb.table("sync_log").upsert({"chave": reg["chave"], "atualizado_em": reg["atualizado_em"]},
                                        on_conflict="chave").execute()
        except Exception as e:
            _log(f"(não consegui registrar {nome} no banco: {e})", tela=False)


def _sinal_de_vida():
    sb = _banco()
    if sb:
        try:
            sb.table("sync_log").upsert({"chave": "rodar_syncs", "atualizado_em": _agora().astimezone().isoformat()},
                                        on_conflict="chave").execute()
        except Exception:
            pass


_RE_ERRO = re.compile(r"❌|\bERRO\b|Traceback \(most recent call last\)", re.I)
_RE_MOSTRA = re.compile(r"✅|❌|⚠|\bERRO\b|Erro|Traceback", re.I)


def rodar_um(s):
    """Roda um sync (modo filho) e devolve True se deu certo."""
    arq = os.path.join(PASTA, s["arquivo"])
    if not os.path.exists(arq):
        _log(f"⏭  {s['nome']:<15} pulado: {s['arquivo']} não está na pasta")
        return True
    inicio = _agora()
    _log(f"▶  {s['nome']:<15} começando ({s['arquivo']})")
    env = dict(os.environ, PYTHONIOENCODING="utf-8", PYTHONUTF8="1", PYTHONWARNINGS="ignore")
    cmd = [sys.executable, os.path.abspath(__file__), "--um", arq] + list(s.get("args") or [])
    p = subprocess.Popen(cmd, cwd=PASTA, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, env=env)
    estourou = {"v": False}
    def _mata():
        estourou["v"] = True
        try:
            p.kill()
        except Exception:
            pass
    t = threading.Timer(s.get("limite", 60) * 60, _mata)
    t.start()
    erro, ultimas = None, []
    for bruto in p.stdout:
        linha = bruto.decode("utf-8", "replace").rstrip()
        if not linha.strip():
            continue
        _log(f"   │ {s['nome']}: {linha}", tela=bool(_RE_MOSTRA.search(linha)))
        ultimas = (ultimas + [linha])[-5:]
        if erro is None and _RE_ERRO.search(linha):
            erro = linha.strip()
    p.wait()
    t.cancel()
    fim = _agora()
    dur = int((fim - inicio).total_seconds())
    dur_txt = f"{dur // 60} min {dur % 60:02d} s" if dur >= 60 else f"{dur} s"
    if estourou["v"]:
        erro = f"passou de {s.get('limite', 60)} minutos e foi interrompido"
    elif p.returncode not in (0, None) and not erro:
        erro = "terminou com erro: " + (ultimas[-1] if ultimas else f"código {p.returncode}")
    if erro:
        _log(f"✖  {s['nome']:<15} ERRO em {dur_txt}: {erro}")
        _registrar(s["nome"], "erro", inicio, fim, erro)
        return False
    _log(f"✔  {s['nome']:<15} OK em {dur_txt}")
    _registrar(s["nome"], "ok", inicio, fim, ultimas[-1] if ultimas else "")
    return True


def _proximas(s, depois):
    """Próximo horário em que o sync deve rodar, depois de 'depois'."""
    if s.get("cada_min"):
        return depois + datetime.timedelta(minutes=s["cada_min"])
    cands = []
    for d in (0, 1):
        dia = (depois + datetime.timedelta(days=d)).date()
        for h in s.get("horas", []):
            hh, mm = map(int, h.split(":"))
            dt = datetime.datetime.combine(dia, datetime.time(hh, mm))
            if dt > depois:
                cands.append(dt)
    return min(cands)


_TRAVA = None
def _so_um_maestro():
    """Impede dois maestros ao mesmo tempo (o .bat aberto duas vezes rodaria tudo em dobro)."""
    global _TRAVA
    caminho = os.path.join(PASTA, "logs", "maestro.trava")
    os.makedirs(os.path.dirname(caminho), exist_ok=True)
    _TRAVA = open(caminho, "a+")
    try:
        if os.name == "nt":
            import msvcrt
            _TRAVA.seek(0)
            msvcrt.locking(_TRAVA.fileno(), msvcrt.LK_NBLCK, 1)
        else:
            import fcntl
            fcntl.flock(_TRAVA.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        return True
    except OSError:
        return False


def maestro(rodada_inicial=True):
    os.chdir(PASTA)
    if not _so_um_maestro():
        print("\n⚠  Já existe um maestro rodando em outra janela. Esta não vai rodar nada.")
        print("   Deixe só a outra janela aberta. (Para rodar um sync na hora: py rodar_syncs.py --agora <nome>)")
        return
    _log("═" * 70)
    _log(f"Maestro dos syncs iniciado — {len(SYNCS)} syncs, um de cada vez. Não feche esta janela.")
    faltam = [s["arquivo"] for s in SYNCS if not os.path.exists(os.path.join(PASTA, s["arquivo"]))]
    if faltam:
        _log("Atenção, não achei na pasta: " + ", ".join(faltam))
    if not _banco():
        _log("(sem conexão com o banco para registrar as rodadas; segue só com o arquivo de log)")
    agora = _agora()
    prox = {s["nome"]: (agora if rodada_inicial else _proximas(s, agora)) for s in SYNCS}
    repetir = {}            # nome -> horário da nova tentativa depois de um erro
    ultimo_sinal = 0
    while True:
        if time.time() - ultimo_sinal > 300:
            _sinal_de_vida()
            ultimo_sinal = time.time()
        agora = _agora()
        # o que está na hora (na ordem da tabela)
        vez = [s for s in SYNCS if prox[s["nome"]] <= agora or (s["nome"] in repetir and repetir[s["nome"]] <= agora)]
        if not vez:
            # mostra o próximo de vez em quando
            if agora.second < 20 and agora.minute % 30 == 0:
                n = min(SYNCS, key=lambda s: min(prox[s["nome"]], repetir.get(s["nome"], prox[s["nome"]])))
                _log(f"…  aguardando. Próximo: {n['nome']} às {prox[n['nome']]:%H:%M}", tela=True)
            time.sleep(20)
            continue
        s = vez[0]
        era_repeticao = s["nome"] in repetir and repetir[s["nome"]] <= agora and prox[s["nome"]] > agora
        ok = rodar_um(s)
        fim = _agora()
        if not era_repeticao:
            prox[s["nome"]] = _proximas(s, max(fim, prox[s["nome"]]) if s.get("cada_min") else fim)
        if ok:
            repetir.pop(s["nome"], None)
        elif not era_repeticao:
            repetir[s["nome"]] = fim + datetime.timedelta(minutes=ESPERA_REPETIR_MIN)
            _log(f"   ↻ {s['nome']}: tento de novo às {repetir[s['nome']]:%H:%M}")
        else:
            repetir.pop(s["nome"], None)
            _log(f"   ✖ {s['nome']}: falhou de novo; fica para o próximo horário ({prox[s['nome']]:%H:%M})")


def listar():
    print("Syncs do maestro (na ordem em que rodam ao abrir):\n")
    for s in SYNCS:
        quando = f"a cada {s['cada_min']} min" if s.get("cada_min") else ", ".join(s["horas"])
        tem = "" if os.path.exists(os.path.join(PASTA, s["arquivo"])) else "   (NÃO ESTÁ NA PASTA)"
        print(f"  {s['nome']:<15} {s['arquivo']:<30} {quando}{tem}")


if __name__ == "__main__":
    try:
        sys.stdout.reconfigure(errors="replace")
    except Exception:
        pass
    a = sys.argv[1:]
    if a[:1] == ["--um"]:
        _modo_filho(a[1], a[2:])
    elif a[:1] == ["--listar"]:
        listar()
    elif a[:1] == ["--agora"]:
        nomes = a[1:]
        alvo = [s for s in SYNCS if s["nome"] in nomes or s["arquivo"] in nomes]
        if not alvo:
            print("Não achei esse sync. Use um destes nomes:", ", ".join(s["nome"] for s in SYNCS))
        for s in alvo:
            rodar_um(s)
    else:
        try:
            maestro(rodada_inicial="--sem-rodada-inicial" not in a)
        except KeyboardInterrupt:
            _log("Maestro encerrado (Ctrl+C).")
