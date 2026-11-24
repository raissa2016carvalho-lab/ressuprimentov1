/* bq-acesso.js — trava de acesso dos painéis B&Q.
 * Uso (no fim do <body>, depois dos scripts da página):
 *   <script src="/bq-acesso.js" data-painel="compras"></script>                    → tela sem login próprio: a trava pede e-mail e senha
 *   <script src="/bq-acesso.js" data-painel="notas" data-login="proprio"></script> → tela que já tem login: a trava só confere o acesso depois do login
 * Quem pode ver cada painel é definido na tela "Acessos" (acessos.html), só para administradores.
 * O banco responde pela função acesso_nivel(painel): 'editar', 'ver' ou 'nenhum' (admin = editar).
 * 'ver' (somente visualização): a trava barra as gravações feitas pelo cliente Supabase da página (variável global db).
 *   Telas que gravam por fetch() direto (compras, fardamento) não são cobertas pelo 'ver'.
 */
(function () {
  var S = document.currentScript || {};
  var ds = S.dataset || {};
  var PAINEL = ds.painel || '';
  var PROPRIO = ds.login === 'proprio';
  var URL = 'https://eugefrjckrxisfpizkjb.supabase.co';
  var KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImV1Z2Vmcmpja3J4aXNmcGl6a2piIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODg0MzEzNjksImV4cCI6MjEwNDAwNzM2OX0.sNQjKjlUm1TWeiDGG2SDeER7GGaf4PucofJWNKxqygI';
  var NOMES = {
    'index': 'Painel de Ressuprimento', 'gerente': 'Painel do Gerente', 'formulario': 'Solicitação de Ressuprimento',
    'ruptura': 'Risco de Ruptura', 'estoque': 'Posição de Estoque', 'compras': 'Compras', 'fechamento': 'Fechamento de Consumo',
    'notas': 'Notas Fiscais / Recebimento', 'separacao': 'Separação', 'descontos': 'Descontos de EPI',
    'estoque-central': 'Estoque Central', 'fardamento': 'Fardamento', 'abrir-sc': 'Abrir SC',
    'inventario': 'Inventário rotativo — contar', 'inventario-coord': 'Inventário rotativo — coordenador',
    'acessos': 'Acessos (administração)'
  };
  window.BQ_PAINEIS = NOMES;

  var css = '#bqa{position:fixed;inset:0;z-index:2147483000;background:linear-gradient(135deg,#0b1f4d,#1e40af);display:flex;align-items:center;justify-content:center;padding:20px;font-family:system-ui,-apple-system,"Segoe UI",sans-serif}' +
    '#bqa .bqa-card{background:#fff;border-radius:14px;width:100%;max-width:370px;padding:30px;box-shadow:0 20px 50px #00000066;color:#0f172a}' +
    '#bqa h2{margin:0 0 4px;font-size:19px}#bqa p{color:#64748b;margin:0 0 16px;font-size:13px;line-height:1.45}' +
    '#bqa label{display:block;font-size:12px;font-weight:600;color:#475569;margin:10px 0 5px}' +
    '#bqa input{width:100%;box-sizing:border-box;border:1px solid #cbd5e1;border-radius:9px;padding:11px 12px;font-size:14px;font-family:inherit;outline:none}#bqa input:focus{border-color:#1e40af}' +
    '#bqa button{width:100%;margin-top:16px;background:#1e40af;color:#fff;border:none;border-radius:9px;padding:12px;font-size:14px;font-weight:700;cursor:pointer;font-family:inherit}#bqa button:disabled{background:#94a3b8;cursor:wait}' +
    '#bqa button.bqa-sec{background:#fff;color:#475569;border:1px solid #cbd5e1;margin-top:10px}' +
    '#bqa .bqa-msg{display:none;margin-top:12px;background:#fee2e2;color:#991b1b;border-radius:8px;padding:9px 12px;font-size:12.5px}' +
    '#bqa .bqa-marca{font-weight:900;font-size:22px;color:#1e40af;margin-bottom:12px}#bqa .bqa-marca b{color:#f26522}' +
    '#bqa a{display:block;text-align:center;margin-top:14px;color:#64748b;font-size:12.5px;text-decoration:none}' +
    '#bqa .bqa-spin{width:34px;height:34px;border:4px solid #dbeafe;border-top-color:#1e40af;border-radius:50%;animation:bqa-g 1s linear infinite;margin:6px auto 14px}@keyframes bqa-g{to{transform:rotate(360deg)}}';
  var st = document.createElement('style'); st.textContent = css; document.head.appendChild(st);

  var ov = document.createElement('div'); ov.id = 'bqa';
  var nome = NOMES[PAINEL] || PAINEL;
  function esc(t) { return String(t == null ? '' : t).replace(/[&<>"]/g, function (c) { return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]; }); }
  function tela(html) { ov.innerHTML = '<div class="bqa-card"><div class="bqa-marca">B<b>&amp;</b>Q</div>' + html + '</div>'; if (!ov.parentNode) document.body.appendChild(ov); }
  function soltar() { if (ov.parentNode) ov.parentNode.removeChild(ov); }
  function verificando() { tela('<div class="bqa-spin"></div><p style="text-align:center;margin:0">Conferindo seu acesso a <b>' + esc(nome) + '</b>…</p>'); }

  var cli = null;
  function cliente() {
    if (cli) return cli;
    try { if (typeof db !== 'undefined' && db && db.auth) { cli = db; return cli; } } catch (e) { /* sem db na página */ }
    cli = window.supabase.createClient(URL, KEY);
    return cli;
  }

  async function sair() {
    try { await cliente().auth.signOut({ scope: 'local' }); } catch (e) { /* segue */ }
    location.reload();
  }

  function semAcesso(email) {
    tela('<h2>Sem acesso</h2><p>O usuário <b>' + esc(email) + '</b> não tem acesso a <b>' + esc(nome) +
      '</b>.<br>Peça a um administrador para liberar na tela de Acessos.</p>' +
      '<button type="button" id="bqa-sair">Entrar com outro usuário</button><a href="/los.html">← Voltar ao menu de sistemas</a>');
    document.getElementById('bqa-sair').onclick = sair;
  }

  function login(msg) {
    tela('<h2>' + esc(nome) + '</h2><p>Entre com o seu e-mail e senha dos painéis B&amp;Q.</p>' +
      '<form id="bqa-form" autocomplete="on"><label>E-mail</label><input id="bqa-email" type="email" autocomplete="username" required>' +
      '<label>Senha</label><input id="bqa-senha" type="password" autocomplete="current-password" required>' +
      '<button type="submit" id="bqa-btn">Entrar</button><div class="bqa-msg" id="bqa-msg"></div></form>' +
      '<a href="/los.html">← Voltar ao menu de sistemas</a>');
    var m = document.getElementById('bqa-msg');
    if (msg) { m.textContent = msg; m.style.display = 'block'; }
    document.getElementById('bqa-email').focus();
    document.getElementById('bqa-form').onsubmit = async function (ev) {
      ev.preventDefault();
      var email = document.getElementById('bqa-email').value.trim(), senha = document.getElementById('bqa-senha').value, b = document.getElementById('bqa-btn');
      b.disabled = true; b.textContent = 'Entrando…'; m.style.display = 'none';
      var r = await cliente().auth.signInWithPassword({ email: email, password: senha });
      if (r.error) {
        b.disabled = false; b.textContent = 'Entrar';
        m.textContent = r.error.message === 'Invalid login credentials' ? 'E-mail ou senha incorretos.' : r.error.message; m.style.display = 'block';
        return;
      }
      conferir(r.data.session);
    };
  }

  // somente visualização: qualquer gravação (insert/update/upsert/delete e RPCs de gravação) é barrada na tela
  var avisouEm = 0;
  function avisoSoVer() {
    if (Date.now() - avisouEm < 1500) return; avisouEm = Date.now();
    alert('Você tem acesso somente para visualização neste painel. Nada foi alterado.');
  }
  function bloqueado() {
    var res = { data: null, error: { message: 'Acesso somente para visualização', code: 'somente_ver' }, status: 403 };
    var p = new Proxy(function () {}, {
      get: function (_, prop) {
        if (prop === 'then') return function (ok) { return Promise.resolve(res).then(ok); };
        if (prop === 'catch' || prop === 'finally') return function () { return Promise.resolve(res); };
        return function () { return p; };
      },
      apply: function () { return p; }
    });
    return p;
  }
  var RPC_GRAVA = /criar|salvar|gravar|definir|excluir|apagar|atualizar|aprovar|decidir|inserir|registrar|baixar|enviar|alterar|cancelar|lancar|marcar|confirmar|reabrir|devolver|remover|limpar/i;
  function somenteVer(c) {
    if (c.__bqSoVer) return; c.__bqSoVer = true;
    var from = c.from.bind(c), rpc = c.rpc.bind(c);
    c.from = function (t) {
      var q = from(t);
      ['insert', 'update', 'upsert', 'delete'].forEach(function (m) { q[m] = function () { avisoSoVer(); return bloqueado(); }; });
      return q;
    };
    c.rpc = function (nome, args, op) { if (RPC_GRAVA.test(nome)) { avisoSoVer(); return bloqueado(); } return rpc(nome, args, op); };
    var faixa = document.createElement('div');
    faixa.textContent = '👁 Somente visualização — você pode consultar, mas não alterar nada neste painel.';
    faixa.style.cssText = 'position:fixed;left:50%;bottom:12px;transform:translateX(-50%);z-index:2147482000;background:#1e293b;color:#fff;padding:8px 16px;border-radius:999px;font:600 12.5px system-ui,-apple-system,sans-serif;box-shadow:0 6px 18px #0004;pointer-events:none';
    document.body.appendChild(faixa);
  }

  async function conferir(sess) {
    verificando();
    var email = sess && sess.user && sess.user.email || '';
    var r = await cliente().rpc('acesso_nivel', { p_painel: PAINEL });
    if (r.error) {
      // sessão vencida ou derrubada: volta para o login
      if (/jwt|token|auth|401|permission/i.test((r.error.message || '') + (r.error.code || ''))) {
        try { await cliente().auth.signOut({ scope: 'local' }); } catch (e) { /* segue */ }
        if (PROPRIO) { location.reload(); return; }
        login('Sua sessão expirou. Entre de novo.'); return;
      }
      tela('<h2>Não consegui conferir o acesso</h2><p>' + esc(r.error.message) + '</p><button type="button" onclick="location.reload()">Tentar de novo</button>');
      return;
    }
    var nivel = r.data;
    if (nivel === 'editar' || nivel === 'ver') {
      if (nivel === 'ver') somenteVer(cliente());
      soltar();
      window.BQ_ACESSO = { painel: PAINEL, email: email, nivel: nivel };
      document.dispatchEvent(new CustomEvent('bq-acesso-ok', { detail: { email: email, nivel: nivel } }));
    } else semAcesso(email);
  }

  async function iniciar() {
    var s = null;
    try { s = (await cliente().auth.getSession()).data.session; } catch (e) { /* sem sessão */ }
    if (s) { conferir(s); return; }
    if (!PROPRIO) { login(); return; }
    // tela com login próprio: espera a pessoa entrar pela tela da página e então confere
    soltar();
    var t = setInterval(async function () {
      var x = null;
      try { x = (await cliente().auth.getSession()).data.session; } catch (e) { /* segue */ }
      if (x) { clearInterval(t); conferir(x); }
    }, 700);
  }

  // cobre a tela já, antes de qualquer coisa aparecer (nas telas sem login próprio)
  if (!PROPRIO) verificando();
  if (window.supabase && window.supabase.createClient) iniciar();
  else {
    var sc = document.createElement('script'); sc.src = '/vendor/supabase-2.118.0.js';
    sc.onload = iniciar;
    sc.onerror = function () { tela('<h2>Não consegui carregar o login</h2><p>Atualize a página.</p>'); };
    document.head.appendChild(sc);
  }
})();
