// Pagina Perfil do usuario ( /usuario/:id ): dados publicos e reputacao,
// anuncios ativos, avaliacoes recebidas e historico de trocas.
import {
  iniciarPagina, api, mostrarEstado, escaparHtml, idDoEndereco, imagemDoItem,
  formatarPreco, formatarData, formatarFloat, formatarNota, NOMES_DESGASTE, NOMES_STATUS,
} from './comum.js';

const idUsuario = idDoEndereco();
const secoes = ['anuncios-usuario', 'avaliacoes-usuario', 'trocas-usuario'].map((id) => document.getElementById(id));

const usuarioAtual = await iniciarPagina(null);
carregar();

async function carregar() {
  let dados;
  try {
    dados = await api(`/usuarios/${idUsuario}`);
  } catch (err) {
    const naoExiste = err.status === 404 || err.status === 400;
    const titulo = naoExiste ? 'Usuário não encontrado' : 'Não foi possível abrir este perfil';
    document.title = `${titulo} — VaultGabe`;
    document.getElementById('conteudo-perfil').innerHTML = `
      <h1>${escaparHtml(titulo)}</h1>
      <p class="aviso aviso-erro secao">${naoExiste ? 'Confira o endereço: não existe usuário com esse número.' : escaparHtml(err.message)}</p>
      <p><a href="/">← Voltar ao catálogo</a></p>`;
    return;
  }
  for (const secao of secoes) secao.removeAttribute('aria-busy');

  mostrarCabecalho(dados.usuario, dados.avaliacoes);
  mostrarAnuncios(dados.anuncios);
  mostrarAvaliacoes(dados.avaliacoes);
  mostrarTrocas(dados.trocas, dados.usuario.apelido);
}

function mostrarCabecalho(u, avaliacoes) {
  const proprio = usuarioAtual?.id === u.id;
  document.title = `${u.apelido} — VaultGabe`;
  document.getElementById('avatar').textContent = u.apelido.charAt(0);
  document.getElementById('apelido').textContent = proprio ? `${u.apelido} (você)` : u.apelido;
  document.getElementById('dados-usuario').textContent = [
    u.nome,
    `membro desde ${formatarData(u.data_cadastro).slice(3)}`,
    u.steam_guard_ativo ? 'Steam Guard ativo' : 'Steam Guard desativado',
    `${u.itens} ${u.itens === 1 ? 'item' : 'itens'} no inventário`,
  ].join(' · ');
  document.getElementById('acoes-perfil').classList.toggle('oculto', !proprio);
  document.getElementById('aviso-steam-guard').classList.toggle('oculto', u.steam_guard_ativo);

  // De onde vem cada avaliacao: uma venda ou uma troca concluida com este
  // usuario (o banco so deixa avaliar quem participou, uma vez).
  const deVendas = avaliacoes.filter((a) => a.origem === 'venda').length;
  const deTrocas = avaliacoes.length - deVendas;
  const origem = [
    deVendas ? `${deVendas} de ${deVendas === 1 ? 'venda' : 'vendas'}` : '',
    deTrocas ? `${deTrocas} de ${deTrocas === 1 ? 'troca' : 'trocas'}` : '',
  ].filter(Boolean).join(' · ');
  document.getElementById('ind-nota').innerHTML = u.nota_media === null
    ? '<span class="texto-suave">Sem avaliações</span>'
    : `★ ${formatarNota(u.nota_media)} <small class="texto-suave">(${u.avaliacoes} ${u.avaliacoes === 1 ? 'avaliação' : 'avaliações'})</small>
       <small class="detalhe-indicador">${origem}</small>`;
  document.getElementById('ind-vendas').textContent = u.vendas;
  document.getElementById('ind-compras').textContent = u.compras;
  document.getElementById('ind-trocas').textContent = u.trocas;
}

function mostrarAnuncios(anuncios) {
  const alvo = secoes[0];
  if (!anuncios.length) {
    mostrarEstado(alvo, 'Nenhum anúncio ativo', 'Quando este usuário anunciar um item, ele aparece aqui.');
    return;
  }
  alvo.className = 'grade-cards';
  alvo.innerHTML = anuncios.map((a) => {
    const detalhe = a.float_value === null
      ? ''
      : `${NOMES_DESGASTE[a.desgaste] ?? ''} · float ${formatarFloat(a.float_value, 4)}`;
    return `
      <a class="card-item" href="/skin/${a.modelo_id}" style="--cor-raridade: ${escaparHtml(a.cor_raridade)}">
        <div class="card-imagem">${imagemDoItem(a)}</div>
        <div class="card-corpo">
          <span class="card-nome">${escaparHtml(a.nome)}</span>
          ${detalhe ? `<span class="card-meta">${escaparHtml(detalhe)}</span>` : ''}
          ${a.reservada ? '<span class="selo selo-aviso">Reservado: venda em andamento</span>' : ''}
          <div class="card-preco">${formatarPreco(a.preco)}<small>expira em ${formatarData(a.data_expiracao)}</small></div>
        </div>
      </a>`;
  }).join('');
}

function estrelas(nota) {
  return `<span class="nota-estrelas" role="img" aria-label="Nota ${nota} de 5">${'★'.repeat(nota)}<span class="apagadas">${'★'.repeat(5 - nota)}</span></span>`;
}

const AVALIACOES_VISIVEIS = 10; // o resto aparece em "Ver todas"

function mostrarAvaliacoes(avaliacoes) {
  const alvo = secoes[1];
  document.getElementById('t-avaliacoes').textContent = `Avaliações recebidas (${avaliacoes.length})`;
  if (!avaliacoes.length) {
    mostrarEstado(alvo, 'Nenhuma avaliação recebida', 'As notas de quem comprou ou trocou com este usuário aparecem aqui.');
    return;
  }

  // Da mais recente para a mais antiga (ordem da consulta).
  const item = (a) => `
    <li class="avaliacao">
      <span class="avaliacao-avatar" aria-hidden="true">${escaparHtml(a.autor.charAt(0))}</span>
      <div class="avaliacao-corpo">
        <div class="avaliacao-topo">
          <span><a href="/usuario/${a.autor_id}">${escaparHtml(a.autor)}</a>
            <span class="texto-suave">· ${formatarData(a.data_avaliacao)}</span></span>
          ${estrelas(a.nota)}
        </div>
        ${a.comentario ? `<p>${escaparHtml(a.comentario)}</p>` : '<p class="texto-suave">Sem comentário.</p>'}
        <small class="texto-suave">${a.origem === 'venda' ? 'Venda' : 'Troca'} ${escaparHtml(a.protocolo ?? '')}</small>
      </div>
    </li>`;
  const desenhar = (todas) => {
    const lista = todas ? avaliacoes : avaliacoes.slice(0, AVALIACOES_VISIVEIS);
    alvo.className = 'lista-avaliacoes';
    alvo.innerHTML = `<ul>${lista.map(item).join('')}</ul>${lista.length < avaliacoes.length
      ? `<button type="button" class="botao botao-pequeno ver-todas">Ver todas as ${avaliacoes.length} avaliações</button>`
      : ''}`;
  };
  desenhar(false);
  alvo.addEventListener('click', (evento) => {
    if (!evento.target.closest('.ver-todas')) return;
    desenhar(true);
    // O foco vai para a primeira avaliacao que estava escondida.
    const proxima = alvo.querySelectorAll('.avaliacao a')[AVALIACOES_VISIVEIS];
    proxima?.focus();
  });
}

// Cor do selo de cada situacao de troca.
const SELO_TROCA = {
  concluida: 'selo-sucesso', aceita: 'selo-aviso', pendente: 'selo-aviso', recusada: 'selo-perigo', cancelada: '',
};

function mostrarTrocas(trocas, apelido) {
  const alvo = secoes[2];
  document.getElementById('t-trocas').textContent = `Histórico de trocas (${trocas.length})`;
  if (!trocas.length) {
    mostrarEstado(alvo, 'Nenhuma troca registrada');
    return;
  }

  // Um lado da troca: o dono e a lista de itens (um por linha).
  const lado = (dono, itens, link) => `
    <div class="troca-lado">
      <span class="rotulo">Itens de ${link ? `<a href="/usuario/${link}">${escaparHtml(dono)}</a>` : escaparHtml(dono)}</span>
      <ul>${(itens ? itens.split(', ') : []).map((i) => `<li>${escaparHtml(i)}</li>`).join('') || '<li class="texto-suave">—</li>'}</ul>
    </div>`;

  alvo.className = 'lista-trocas';
  alvo.innerHTML = `<ul>${trocas.map((t) => {
    // Do ponto de vista deste usuario: o proponente oferece os seus itens e
    // pede os do destinatario. So nas trocas concluidas os itens mudaram de
    // dono (o selo da situacao diz isso).
    const meus = t.papel === 'proponente' ? t.itens_oferecidos : t.itens_solicitados;
    const daOutraParte = t.papel === 'proponente' ? t.itens_solicitados : t.itens_oferecidos;
    const proposta = t.papel === 'proponente'
      ? `Proposta feita para <a href="/usuario/${t.outro_usuario_id}">${escaparHtml(t.outro_usuario)}</a>`
      : `Proposta recebida de <a href="/usuario/${t.outro_usuario_id}">${escaparHtml(t.outro_usuario)}</a>`;
    return `
      <li class="troca">
        <div class="troca-topo">
          <strong class="troca-protocolo">${escaparHtml(t.protocolo)}</strong>
          <span class="selo ${SELO_TROCA[t.status] ?? ''}">${escaparHtml(NOMES_STATUS[t.status] ?? t.status)}</span>
          <span class="troca-datas texto-suave">${proposta} em ${formatarData(t.data_proposta)}${t.data_efetivacao ? ` · efetivada em ${formatarData(t.data_efetivacao)}` : ''}</span>
        </div>
        <div class="troca-lados">
          ${lado(apelido, meus)}
          <span class="troca-seta" aria-hidden="true">⇄</span>
          ${lado(t.outro_usuario, daOutraParte, t.outro_usuario_id)}
        </div>
      </li>`;
  }).join('')}</ul>`;
}
