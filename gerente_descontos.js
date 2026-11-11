// Tela do gerente — aba "Descontos de EPI": o gerente responde Abonar/Descontar nos descontos dos seus CCs.
// Grava em descontos_decisao (gerente_decisao / gerente_por / gerente_em / gerente_obs). Usa db, $, meusCC e userEmail da tela.
(function(){
  const MES=['Jan','Fev','Mar','Abr','Mai','Jun','Jul','Ago','Set','Out','Nov','Dez'];
  const MOT={'1':'Perda','2':'Roubo','3':'Desgaste','4':'Defeito','5':'Admissional','6':'Mal uso','7':'Manutenção','8':'Transferência','9':'Consumo','A':'Mobilização','C':'Complementação'};
  const R=v=>'R$ '+(Number(v)||0).toLocaleString('pt-BR',{minimumFractionDigits:2,maximumFractionDigits:2});
  const D=d=>d?new Date(String(d).slice(0,10)+'T12:00').toLocaleDateString('pt-BR'):'–';
  const E=v=>String(v==null?'':v).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  let DG=[],DGD={},FECH=false,ULT=null,ini=false,carregou=false;
  // períodos da folha: dia 21 de um mês ao dia 20 do seguinte
  function pers(){let h=new Date(),y=h.getFullYear(),m=h.getMonth();if(h.getDate()>20){m++;if(m>11){m=0;y++}}let o=[];
    for(let k=0;k<14;k++){let fy=y,fm=m-k;while(fm<0){fm+=12;fy--}let iy=fy,im=fm-1;if(im<0){im=11;iy--}
      o.push({ini:`${iy}-${String(im+1).padStart(2,'0')}-21`,fim:`${fy}-${String(fm+1).padStart(2,'0')}-20`,rot:`21 ${MES[im]}/${String(iy).slice(2)} a 20 ${MES[fm]}/${String(fy).slice(2)}`})}return o}
  // período fechado = já integrado na folha (ZZA_INTEG = S em algum desconto); abre no período em aberto
  async function iniciar(){
    if(ini)return;ini=true;
    try{let{data}=await db.from('descontos_epi').select('datinc').eq('integrado','S').order('datinc',{ascending:false}).limit(1);ULT=data&&data[0]?data[0].datinc:null}catch(e){}
    let ps=pers();if(ULT){let f=ps.find(p=>p.ini<=ULT&&ULT<=p.fim);if(f)ULT=f.fim}
    let ab=ps.slice().reverse().find(p=>!ULT||p.fim>ULT);
    $('dg-per').innerHTML=ps.map(p=>`<option value="${p.ini}|${p.fim}"${ab&&p.ini===ab.ini?' selected':''}>${p.rot}${ULT&&p.fim<=ULT?' · fechado':ab&&p.ini===ab.ini?' · EM ABERTO':''}</option>`).join('');
  }
  window.dgCarregar=async function(){
    await iniciar();carregou=true;
    let [i,f]=$('dg-per').value.split('|');FECH=!!(ULT&&f<=ULT);
    $('dg-lista').innerHTML='<div style="padding:20px;color:#64748b;font-size:13px">Carregando...</div>';
    let ccs=(typeof meusCC!=='undefined'&&meusCC?meusCC:[]).map(c=>String(c).trim());
    if(!ccs.length){$('dg-resumo').innerHTML='';$('dg-lista').innerHTML='<div style="padding:20px;color:#64748b">Nenhum centro de custo ligado ao seu usuário.</div>';return}
    DG=[];
    for(let o=0;;o+=1000){let{data,error}=await db.from('descontos_epi').select('*').in('cc',ccs).gte('datinc',i).lte('datinc',f).order('nome').range(o,o+999);
      if(error){$('dg-lista').innerHTML='<div style="padding:20px;color:#b91c1c">Não consegui carregar: '+E(error.message)+'</div>';return}
      DG=DG.concat(data||[]);if(!data||data.length<1000)break}
    DGD={};let ch=DG.map(d=>d.chave);
    for(let k=0;k<ch.length;k+=200){let{data}=await db.from('descontos_decisao').select('*').in('chave',ch.slice(k,k+200));(data||[]).forEach(x=>DGD[x.chave]=x)}
    dgDesenhar();
  };
  const resp=d=>FECH?(d.integrado==='S'?'descontar':'abonar'):((DGD[d.chave]||{}).gerente_decisao||'');
  window.dgDesenhar=function(){
    let fl=$('dg-filtro').value,q=$('dg-busca').value.toLowerCase().trim();
    let L=DG.filter(d=>{let r=resp(d);if(fl==='pend'&&r)return false;if(fl&&fl!=='pend'&&r!==fl)return false;
      if(q&&![d.nome,d.matricula,d.produto,d.descricao,d.sa].some(x=>String(x||'').toLowerCase().includes(q)))return false;return true});
    let soma=a=>a.reduce((s,d)=>s+(Number(d.valor_desconto)||0),0),pe=DG.filter(d=>!resp(d)),ab=DG.filter(d=>resp(d)==='abonar'),de=DG.filter(d=>resp(d)==='descontar');
    let box=(t,v,c,sub)=>`<div style="background:#fff;border:1px solid #e2e8f0;border-radius:10px;padding:8px 14px;font-size:12px;color:#64748b;min-width:150px">${t}<div style="font-size:18px;font-weight:800;color:${c}">${v}</div>${sub||''}</div>`;
    $('dg-resumo').innerHTML=(FECH?'<div style="width:100%;background:#f1f5f9;color:#475569;border-radius:8px;padding:8px 12px;font-size:12.5px">🔒 Período fechado: já foi para a folha. Só consulta.</div>':'')+
      box('Descontos',DG.length,'#0f172a',R(soma(DG)))+box('Sem resposta',pe.length,'#b45309',R(soma(pe)))+
      box(FECH?'Abonados':'Você abonou',ab.length,'#16a34a',R(soma(ab)))+box(FECH?'Descontados':'Você descontou',de.length,'#ea580c',R(soma(de)));
    const bt=(k,dec,r,txt,cor)=>`<button onclick="dgResp('${k}','${dec}')" style="border:1px solid ${r===dec?cor:'#e2e8f0'};background:${r===dec?cor:'#fff'};color:${r===dec?'#fff':'#64748b'};border-radius:7px;padding:5px 9px;font-size:11.5px;font-weight:700;cursor:pointer">${txt}</button>`;
    $('dg-lista').innerHTML=L.length?`<div style="background:#fff;border:1px solid #e2e8f0;border-radius:12px;overflow:auto"><table style="width:100%;border-collapse:collapse;font-size:12.5px"><thead><tr style="background:#f8fafc;color:#64748b;font-size:11px;text-align:left">
      <th style="padding:8px">Emissão / SA</th><th>Funcionário</th><th>Produto</th><th style="text-align:right">Vida útil</th><th style="text-align:right">Faltava</th><th style="text-align:right">Custo</th><th style="text-align:right">Desconto</th><th style="padding-left:8px">Motivo / observação</th><th>Sua resposta</th></tr></thead><tbody>`+
      L.map(d=>{let r=resp(d),x=DGD[d.chave]||{},p=Number(d.valor)>0?Math.min(1,(Number(d.valor_desconto)||0)/Number(d.valor)):null,fal=p!=null&&d.vida_util!=null?Math.round(p*Number(d.vida_util)):null,k=E(d.chave);
        return `<tr style="border-top:1px solid #f1f5f9;background:${r==='abonar'?'#f0fdf4':r==='descontar'?'#fff7ed':'#fff'}">
          <td style="padding:7px 8px;white-space:nowrap">${D(d.emissao)}<div style="color:#94a3b8;font-size:11px">SA ${E(d.sa)}</div></td>
          <td><b>${E(d.nome||'(sem nome)')}</b><div style="color:#94a3b8;font-size:11px">${E(d.matricula)}${d.funcao?' · '+E(d.funcao):''}</div></td>
          <td>${E(d.descricao||'')}<div style="color:#94a3b8;font-size:11px">${E(d.produto)}${Number(d.quantidade)>1?' · qtd '+Number(d.quantidade):''}</div></td>
          <td style="text-align:right;white-space:nowrap">${d.vida_util!=null?Number(d.vida_util)+' d':'–'}</td>
          <td style="text-align:right;white-space:nowrap">${fal!=null?fal+' d ('+Math.round(p*100)+'%)':'–'}</td>
          <td style="text-align:right;white-space:nowrap">${R(d.valor)}</td><td style="text-align:right;font-weight:700;white-space:nowrap">${R(d.valor_desconto)}</td>
          <td style="max-width:200px;font-size:11.5px;padding-left:8px">${E(MOT[d.motivo]||d.motivo||'')}<div style="color:#475569">${E(d.observacao||'')}</div></td>
          <td style="padding:6px 8px">${FECH?`<b style="color:${r==='abonar'?'#16a34a':'#ea580c'}">${r==='abonar'?'Abonado':'Descontado'}</b>`:
            `<div style="display:flex;gap:4px">${bt(k,'abonar',r,'Abonar','#16a34a')}${bt(k,'descontar',r,'Descontar','#ea580c')}</div>
             <input placeholder="Justificativa (opcional)" value="${E(x.gerente_obs||'')}" onchange="dgObs('${k}',this.value)" style="margin-top:4px;width:180px;border:1px solid #e2e8f0;border-radius:6px;padding:4px 6px;font-size:11.5px">`}</td></tr>`}).join('')+'</tbody></table></div>'
      :'<div style="padding:20px;color:#64748b;font-size:13px;background:#fff;border:1px dashed #e2e8f0;border-radius:12px;text-align:center">Nenhum desconto com esse filtro.</div>';
  };
  async function salvar(chave,campos){
    let reg=Object.assign({chave},campos);
    let{error}=await db.from('descontos_decisao').upsert(reg,{onConflict:'chave'});
    if(error){alert('Não consegui salvar: '+error.message);return false}
    DGD[chave]=Object.assign({},DGD[chave]||{},reg);return true;
  }
  // clicar de novo na mesma resposta desfaz
  window.dgResp=async function(chave,dec){
    let atual=(DGD[chave]||{}).gerente_decisao;
    let ok=await salvar(chave,atual===dec?{gerente_decisao:null,gerente_por:null,gerente_em:null}:{gerente_decisao:dec,gerente_por:userEmail||null,gerente_em:new Date().toISOString()});
    if(ok)dgDesenhar();
  };
  window.dgObs=async function(chave,v){await salvar(chave,{gerente_obs:v.trim()||null})};
  // troca de aba: a função original cuida de Avaliar/Acompanhar; esta cuida de Descontos
  const _ir=window.irParaTab;
  window.irParaTab=function(tab){
    let b=$('tab-btn-descontos'),on=tab==='descontos';
    $('tab-descontos').style.display=on?'block':'none';
    b.style.background=on?'#fff':'transparent';b.style.color=on?'#0f172a':'#64748b';b.style.fontWeight=on?'600':'500';b.style.boxShadow=on?'0 1px 3px rgba(0,0,0,.08)':'none';
    if(on){$('tab-avaliar').style.display='none';$('tab-acompanhar').style.display='none';
      ['tab-btn-avaliar','tab-btn-acompanhar'].forEach(id=>{let x=$(id);if(x){x.style.background='transparent';x.style.color='#64748b';x.style.fontWeight='500';x.style.boxShadow='none'}});
      if(!carregou)dgCarregar();return}
    if(_ir)_ir(tab);
  };
})();
