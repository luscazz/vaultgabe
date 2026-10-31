// Pagina Negociacoes ( /negociacoes ): anuncios a venda (com cancelamento),
// vendas, compras (com a janela Avaliar vendedor) e anuncios encerrados do
// usuario selecionado. A aba fica no endereco (?aba=comprados).
import {
  iniciarPagina, api, mostrarEstado, escaparHtml, imagemDoItem, celula,
  formatarPreco, formatarData, formatarFloat, prepararAbas, prepararJanela,
  NOMES_DESGASTE, NOMES_STATUS, NOMES_PAGAMENTO,
} from './comum.js';

const conteudo = document.getElementById('conteudo-aba');
const listaAbas = document.getElementById('abas-negociacoes');
const tituloAba = document.getElementById('titulo-aba');

const janelaCancelar = document.getElementById('janela-cancelar');
const botaoConfirmarCancelar = document.getElementById('confirmar-cancelar');
const botaoManter = document.getElementById('manter-anuncio');
const erroCancelar = document.getElementById('erro-cancelar');

const janelaAvaliar = document.getElementById('janela-avaliar');
const formAvaliar = document.getElementById('form-avaliar');
const comentario = document.getElementById('comentario');
const botaoEnviar = document.getElementById('enviar-avaliacao');
const botaoCancelarAvaliacao = document.getElementById('cancelar-avaliacao');
const erroAvaliacao = document.getElementById('erro-avaliacao');

const ABAS = {
  a_venda: {
    titulo: 'À venda',
    vazio: ['Nenhum anúncio ativo', 'Anuncie um item do seu inventário para ele aparecer aqui.'],
  },
  vendidos: {
    titulo: 'Vendidos',
    vazio: ['Nenhuma venda ainda', 'Quando alguém comprar um anúncio seu, a venda aparece aqui.'],
  },
  comprados: {
    titulo: 'Comprados',
    vazio: ['Nenhuma compra ainda', 'Compre uma skin no catálogo e ela aparece aqui.'],
  },
  encerrados: {
    titulo: 'Encerrados',
    vazio: ['Nenhum anúncio encerrado', 'Anúncios cancelados ou vencidos aparecem aqui.'],
  },
};

let usuario = null;             // usuario selecionado em "Entrar como"
let dados = null;               // resposta de /api/negociacoes
let erroCarga = null;           // mensagem da ultima carga que falhou
let abaAtual = 'a_venda';
let anuncioEmCancelamento = null;
let compraEmAvaliacao = null;
let recarregarAoFechar = false; // acao feita ou recusada: atualiza ao fechar
let pedidoCarga = 0;            // so a resposta mais recente e mostrada

const marcarAba = prepararAbas(listaAbas, (aba) => {
  abaAtual = aba.dataset.aba;
  history.replaceState(null, '', abaAtual === 'a_venda' ? location.pathname : `?aba=${abaAtual}`);
  mostrarAba();
});
const abaDoEndereco = new URLSearchParams(location.search).get('aba');
if (Object.hasOwn(ABAS, abaDoEndereco ?? '')) {
  abaAtual = abaDoEndereco;
  marcarAba(document.getElementById(`aba-${abaAtual}`));
}

conteudo.addEventListener('click', (evento) => {
  const cancelar = evento.target.closest('[data-cancelar]');
  if (cancelar) abrirCancelamento(Number(cancelar.dataset.cancelar));
  const avaliar = evento.target.closest('[data-avaliar]');
  if (avaliar) abrirAvaliacao(Number(avaliar.dataset.avaliar));
});
comentario.addEventListener('input', atualizarContador);

prepararJanela(janelaCancelar, { aoEnviar: cancelarAnuncio, retorno: tituloAba });
prepararJanela(janelaAvaliar, { aoEnviar: enviarAvaliacao, retorno: tituloAba });
for (const janela of [janelaCancelar, janelaAvaliar]) {
  janela.addEventListener('close', () => {
    if (!recarregarAoFechar) return;
    recarregarAoFechar = false;
    tituloAba.focus(); // a tabela sera redesenhada
    carregar();
  });
}

usuario = await iniciarPagina('negociacoes');
if (usuario) {
  document.getElementById('titulo-negociacoes').textContent = `Negociações de ${usuario.apelido}`;
  document.getElementById('subtitulo-negociacoes').textContent =
    `O que ${usuario.apelido} está vendendo, já vendeu e comprou. Para ver as de outra pessoa, troque o usuário em "Entrar como".`;
  carregar();
} else {
  conteudo.removeAttribute('aria-busy');
  mostrarEstado(conteudo, 'Não foi possível carregar as negociações', 'O banco de dados não respondeu. Tente de novo em instantes.', 'erro');
}

// ---------- Carregamento ----------

async function carregar() {
  conteudo.classList.add('carregando');
  conteudo.setAttribute('aria-busy', 'true');
  const pedido = ++pedidoCarga;
  try {
    const resposta = await api(`/negociacoes?usuario=${usuario.id}`);
    if (pedido !== pedidoCarga) return;
    dados = resposta;
    erroCarga = null;
    for (const aba of Object.keys(ABAS)) {
      document.getElementById(`cont-${aba}`).textContent = `(${dados.contagens[aba]})`;
    }
    mostrarAba();
  } catch (err) {
    if (pedido !== pedidoCarga) return;
    // Sem dados atualizados, as abas nao podem voltar a mostrar a lista antiga.
    dados = null;
    erroCarga = err.message;
    for (const aba of Object.keys(ABAS)) document.getElementById(`cont-${aba}`).textContent = '';
    mostrarAba();
  } finally {
    if (pedido === pedidoCarga) {
      conteudo.classList.remove('carregando');
      conteudo.removeAttribute('aria-busy');
    }
  }
}

function mostrarAba() {
  tituloAba.textContent = ABAS[abaAtual].titulo;
  if (!dados) {
    if (erroCarga !== null) mostrarEstado(conteudo, 'Não foi possível carregar as negociações', erroCarga, 'erro');
    return;
  }
  const lista = dados[abaAtual];
  if (!lista.length) {
    mostrarEstado(conteudo, ...ABAS[abaAtual].vazio);
    return;
  }
  const tabela = { a_venda: tabelaAVenda, vendidos: tabelaVendidos, comprados: tabelaComprados, encerrados: tabelaEncerrados }[abaAtual];
  conteudo.className = 'tabela-rolagem';
  conteudo.innerHTML = tabela(lista);
}

// ---------- Tabelas ----------

// Miniatura + nome (link para a skin) + detalhe do exemplar. Igual nas quatro
// abas: arma, faca ou luva mostra desgaste e float (float_value e desgaste
// vem nulos nos outros itens, que mostram o numero de inspecao).
function itemMini(item) {
  const detalhe = item.float_value !== undefined && item.float_value !== null
    ? [NOMES_DESGASTE[item.desgaste], `float ${formatarFloat(item.float_value, 4)}`].filter(Boolean).join(' · ')
    : item.numero_inspecao;
  return `
    <div class="item-mini">
      <div class="miniatura">${imagemDoItem(item)}</div>
      <div>
        <a href="/skin/${item.modelo_id}">${escaparHtml(item.nome)}</a>
        <small class="texto-suave">${escaparHtml(detalhe)}</small>
      </div>
    </div>`;
}

function tabela(legenda, cabecalho, linhas) {
  return `
    <table class="tabela tabela-responsiva">
      <caption class="visualmente-oculto">${legenda}</caption>
      <thead><tr>${cabecalho}</tr></thead>
      <tbody>${linhas.join('')}</tbody>
    </table>`;
}

function pagamento(metodo, status) {
  const texto = NOMES_PAGAMENTO[metodo] ?? metodo;
  return status && status !== 'aprovado'
    ? `${escaparHtml(texto)}<small class="texto-suave">${escaparHtml(NOMES_STATUS[status] ?? status)}</small>`
    : escaparHtml(texto);
}

function protocoloENota(protocolo, chave) {
  return `${escaparHtml(protocolo)}${chave ? `<small class="chave-nf" title="Chave da nota fiscal">NF-e ${escaparHtml(chave.replace(/(\d{4})(?=\d)/g, '$1 '))}</small>` : ''}`;
}

function tabelaAVenda(lista) {
  return tabela('Anúncios à venda',
    '<th>Item</th><th>Publicado</th><th>Expira</th><th class="numero">Preço</th><th><span class="visualmente-oculto">Ação</span></th>',
    lista.map((a) => `
      <tr>
        ${celula('Item', itemMini(a))}
        ${celula('Publicado', formatarData(a.data_publicacao))}
        ${celula('Expira', formatarData(a.data_expiracao))}
        ${celula('Preço', `<strong>${formatarPreco(a.preco)}</strong>`, 'numero')}
        ${celula('', a.pode_cancelar
          ? `<button type="button" class="botao botao-perigo botao-pequeno" data-cancelar="${a.anuncio_id}"
               aria-label="Cancelar o anúncio de ${escaparHtml(a.nome)}">Cancelar</button>`
          : `<span class="selo selo-aviso">Venda pendente</span><small class="texto-suave">${escaparHtml(a.venda_pendente)} · não pode ser cancelado</small>`, 'acao')}
      </tr>`));
}

function tabelaVendidos(lista) {
  return tabela('Vendas concluídas',
    '<th>Item</th><th>Comprador</th><th>Data</th><th>Pagamento</th><th>Protocolo</th><th class="numero">Valor</th>',
    lista.map((v) => `
      <tr>
        ${celula('Item', itemMini(v))}
        ${celula('Comprador', `<a href="/usuario/${v.comprador_id}">${escaparHtml(v.comprador)}</a>`)}
        ${celula('Data', formatarData(v.data_venda))}
        ${celula('Pagamento', pagamento(v.metodo_pagamento))}
        ${celula('Protocolo', protocoloENota(v.protocolo, v.chave_nota_fiscal))}
        ${celula('Valor', `<strong>${formatarPreco(v.valor)}</strong>`, 'numero')}
      </tr>`));
}

function tabelaComprados(lista) {
  return tabela('Compras',
    '<th>Item</th><th>Vendedor</th><th>Data</th><th>Pagamento</th><th>Protocolo</th><th class="numero">Valor</th><th><span class="visualmente-oculto">Avaliação</span></th>',
    lista.map((c) => {
      let acao;
      if (c.pode_avaliar) {
        acao = `<button type="button" class="botao botao-primario botao-pequeno" data-avaliar="${c.venda_id}"
                  aria-label="Avaliar vendedor ${escaparHtml(c.vendedor)} pela compra ${escaparHtml(c.protocolo)}">Avaliar vendedor</button>`;
      } else if (c.ja_avaliou) {
        acao = '<span class="selo selo-sucesso">Avaliado</span>';
      } else {
        acao = `<span class="selo selo-aviso">${escaparHtml(NOMES_STATUS[c.status_venda] ?? c.status_venda)}</span>`;
      }
      return `
        <tr>
          ${celula('Item', itemMini(c))}
          ${celula('Vendedor', `<a href="/usuario/${c.vendedor_id}">${escaparHtml(c.vendedor)}</a>`)}
          ${celula('Data', formatarData(c.data_venda))}
          ${celula('Pagamento', pagamento(c.metodo_pagamento, c.status_pagamento))}
          ${celula('Protocolo', protocoloENota(c.protocolo, c.chave_nota_fiscal))}
          ${celula('Valor', `<strong>${formatarPreco(c.valor)}</strong>`, 'numero')}
          ${celula('', acao, 'acao')}
        </tr>`;
    }));
}

function tabelaEncerrados(lista) {
  return tabela('Anúncios encerrados',
    '<th>Item</th><th>Publicado</th><th>Validade</th><th>Situação</th><th class="numero">Preço</th>',
    lista.map((a) => `
      <tr>
        ${celula('Item', itemMini(a))}
        ${celula('Publicado', formatarData(a.data_publicacao))}
        ${celula('Validade', formatarData(a.data_expiracao))}
        ${celula('Situação', `<span class="selo ${a.status_anuncio === 'cancelado' ? '' : 'selo-aviso'}">${escaparHtml(NOMES_STATUS[a.status_anuncio] ?? a.status_anuncio)}</span>`)}
        ${celula('Preço', formatarPreco(a.preco), 'numero')}
      </tr>`));
}

// Mensagem de confirmacao de uma acao (fica acima das abas).
function mostrarAviso(texto) {
  const aviso = document.getElementById('aviso-acao');
  aviso.textContent = texto;
  aviso.classList.remove('oculto');
}

// ---------- Janela Cancelar anuncio ----------

function abrirCancelamento(idAnuncio) {
  anuncioEmCancelamento = dados?.a_venda.find((a) => a.anuncio_id === idAnuncio);
  if (!anuncioEmCancelamento) return;
  const a = anuncioEmCancelamento;
  document.getElementById('resumo-cancelar').innerHTML = `
    <div class="card-imagem">${imagemDoItem(a)}</div>
    <div>
      <strong>${escaparHtml(a.nome)}</strong><br>
      <small class="texto-suave">Publicado em ${formatarData(a.data_publicacao)} · expira em ${formatarData(a.data_expiracao)}</small>
      <div class="preco">${formatarPreco(a.preco)}</div>
    </div>`;
  erroCancelar.classList.add('oculto');
  botaoConfirmarCancelar.disabled = false;
  botaoConfirmarCancelar.textContent = 'Cancelar anúncio';
  janelaCancelar.showModal();
  botaoManter.focus(); // a opcao segura vem selecionada
}

async function cancelarAnuncio() {
  if (botaoConfirmarCancelar.disabled || !anuncioEmCancelamento) return null;
  const anuncio = anuncioEmCancelamento; // o anuncio deste envio
  botaoConfirmarCancelar.disabled = true;
  botaoConfirmarCancelar.textContent = 'Cancelando…';
  erroCancelar.classList.add('oculto');
  try {
    await api(`/anuncios/${anuncio.anuncio_id}/cancelar`, {
      method: 'POST',
      body: { usuario_id: usuario.id },
    });
    mostrarAviso(`Anúncio de ${anuncio.nome} cancelado. Ele foi para a aba Encerrados e o item voltou a ficar disponível no inventário.`);
    recarregarAoFechar = true;
    return 'fechar';
  } catch (err) {
    erroCancelar.textContent = err.message;
    erroCancelar.classList.remove('oculto');
    const tentarDeNovo = !err.status || err.status >= 500;
    botaoConfirmarCancelar.disabled = !tentarDeNovo;
    botaoConfirmarCancelar.textContent = tentarDeNovo ? 'Tentar de novo' : 'Cancelar anúncio';
    if (!tentarDeNovo) recarregarAoFechar = true; // o anuncio mudou (vendido, vencido...)
    return tentarDeNovo ? botaoConfirmarCancelar : botaoManter;
  }
}

// ---------- Janela Avaliar vendedor ----------

function abrirAvaliacao(idVenda) {
  compraEmAvaliacao = dados?.comprados.find((c) => c.venda_id === idVenda);
  if (!compraEmAvaliacao) return;
  const c = compraEmAvaliacao;
  document.getElementById('titulo-avaliar').textContent = `Avaliar ${c.vendedor}`;
  document.getElementById('compra-avaliada').textContent =
    `Compra ${c.protocolo} · ${c.nome} · ${formatarPreco(c.valor)} em ${formatarData(c.data_venda)}`;
  document.getElementById('link-perfil-avaliado').href = `/usuario/${c.vendedor_id}`;
  formAvaliar.reset();
  atualizarContador();
  erroAvaliacao.classList.add('oculto');
  botaoEnviar.disabled = false;
  botaoEnviar.textContent = 'Enviar avaliação';
  alternarEtapaAvaliacao(false);
  janelaAvaliar.showModal();
  formAvaliar.querySelector('input[name="nota"]:checked').focus();
}

function atualizarContador() {
  const n = comentario.value.length;
  document.getElementById('contador-comentario').textContent = `${n} de 500 caracteres`;
}

async function enviarAvaliacao() {
  if (botaoEnviar.disabled || !compraEmAvaliacao) return null;
  const compra = compraEmAvaliacao; // a compra deste envio
  botaoEnviar.disabled = true;
  botaoEnviar.textContent = 'Enviando…';
  erroAvaliacao.classList.add('oculto');
  try {
    const campos = new FormData(formAvaliar);
    const resposta = await api('/avaliacoes', {
      method: 'POST',
      body: {
        venda_id: compra.venda_id,
        autor_id: usuario.id,
        nota: Number(campos.get('nota')),
        comentario: campos.get('comentario'),
      },
    });
    document.getElementById('ticket-avaliacao').textContent = resposta.ticket;
    recarregarAoFechar = true;
    alternarEtapaAvaliacao(true);
    return document.getElementById('avaliacao-enviada');
  } catch (err) {
    erroAvaliacao.textContent = err.message;
    erroAvaliacao.classList.remove('oculto');
    // 400: dado invalido, da para corrigir. 5xx/sem conexao: tentar de novo.
    // Regra de negocio (ja avaliada...): a pagina e atualizada ao fechar.
    const tentarDeNovo = !err.status || err.status >= 500;
    const corrigivel = err.status === 400;
    botaoEnviar.disabled = !(tentarDeNovo || corrigivel);
    botaoEnviar.textContent = tentarDeNovo ? 'Tentar de novo' : 'Enviar avaliação';
    if (botaoEnviar.disabled) {
      recarregarAoFechar = true;
      return botaoCancelarAvaliacao;
    }
    return botaoEnviar;
  }
}

// false: preencher a avaliacao; true: avaliacao enviada.
function alternarEtapaAvaliacao(enviada) {
  document.getElementById('etapa-avaliar').classList.toggle('oculto', enviada);
  document.getElementById('acoes-avaliar').classList.toggle('oculto', enviada);
  document.getElementById('etapa-avaliada').classList.toggle('oculto', !enviada);
  document.getElementById('acoes-avaliada').classList.toggle('oculto', !enviada);
}
