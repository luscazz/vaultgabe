// Partes comuns a todas as paginas: topo, rodape, seletor de usuario,
// acesso a API e funcoes de formatacao.
// iniciarPagina(nome) devolve o usuario de "Entrar como" ({ id, apelido, nome })
// ou null, se o banco estiver indisponivel.

const LINKS = [
  { pagina: 'catalogo',    endereco: '/',            texto: 'Catálogo' },
  { pagina: 'inventario',  endereco: '/inventario',  texto: 'Inventário' },
  { pagina: 'negociacoes', endereco: '/negociacoes', texto: 'Negociações' },
  { pagina: 'analise',     endereco: '/analise',     texto: 'Análise' },
];

const CHAVE_USUARIO = 'vaultgabe:usuario';
const USUARIO_PADRAO = 'isizinha'; // usuario de demonstracao (docs/escopo.md)

export async function iniciarPagina(paginaAtual) {
  montarTopo(paginaAtual);
  montarRodape();
  return carregarUsuarios();
}

// ---------- Acesso a API ----------

// Chama a API do VaultGabe e devolve o JSON. Em caso de erro, lanca um
// Error com a mensagem que o servidor mandou (pronta para o usuario) e o
// status HTTP em erro.status (ausente quando nem chegou ao servidor).
export async function api(caminho, opcoes = {}) {
  let resposta;
  try {
    resposta = await fetch(`/api${caminho}`, {
      ...opcoes,
      headers: { 'Content-Type': 'application/json', ...opcoes.headers },
      body: opcoes.body === undefined ? undefined : JSON.stringify(opcoes.body),
    });
  } catch {
    throw new Error('Sem conexão com o servidor. Verifique sua internet.');
  }

  const dados = await resposta.json().catch(() => ({}));
  if (!resposta.ok) {
    const erro = new Error(dados.erro || `Erro ${resposta.status} ao falar com o servidor.`);
    erro.status = resposta.status;
    throw erro;
  }
  return dados;
}

// ---------- Topo e rodape ----------

function montarTopo(paginaAtual) {
  const topo = document.getElementById('topo');
  topo.className = 'topo';
  topo.innerHTML = `
    <div class="container">
      <a class="marca" href="/" aria-label="VaultGabe - página inicial">
        <img src="/img/logo.svg" alt="">
        <div>Vault<span>Gabe</span></div>
      </a>
      <nav class="navegacao" aria-label="Principal">
        ${LINKS.map((l) => `
          <a href="${l.endereco}"${l.pagina === paginaAtual ? ' class="ativo" aria-current="page"' : ''}>${l.texto}</a>
        `).join('')}
      </nav>
      <div class="seletor-usuario">
        <label for="usuario-atual">Entrar como</label>
        <select id="usuario-atual" disabled>
          <option>Carregando…</option>
        </select>
        <a id="link-meu-perfil" class="botao botao-pequeno oculto" href="#">Meu perfil</a>
      </div>
    </div>`;
}

function montarRodape() {
  const rodape = document.getElementById('rodape');
  rodape.className = 'rodape';
  rodape.innerHTML = `
    <div class="container rodape-conteudo">
      <a class="rodape-marca" href="/" aria-label="VaultGabe - página inicial">
        <img src="/img/logo-vaultgabe.webp" width="96" height="96" alt="" loading="lazy" decoding="async">
      </a>
      <p class="rodape-nota">Usuários, preços, vendas e avaliações são dados de demonstração e não representam o mercado real.</p>
      <p class="rodape-nota">Imagens e nomes dos itens © Valve Corporation · Dados do catálogo:
        <a href="https://github.com/ByMykel/CSGO-API" target="_blank" rel="noopener">CSGO-API</a> (projeto não oficial) ·
        O VaultGabe não tem vínculo com a Valve · Projeto acadêmico da disciplina de Banco de Dados II.</p>
    </div>`;
}

// Aviso no topo da pagina (ex.: banco indisponivel). Um aviso novo
// substitui o anterior, em vez de empilhar.
export function mostrarAvisoGlobal(mensagem) {
  let aviso = document.getElementById('aviso-global');
  if (!aviso) {
    aviso = document.createElement('p');
    aviso.id = 'aviso-global';
    aviso.className = 'aviso aviso-erro';
    aviso.setAttribute('role', 'alert');
    document.querySelector('main').prepend(aviso);
  }
  aviso.textContent = mensagem;
}

// Id numerico no fim do endereco (/skin/12 ou /skin/12/); 0 se nao houver.
export function idDoEndereco() {
  return Number(location.pathname.match(/\/(\d+)\/?$/)?.[1] ?? 0);
}

// ---------- Abas ----------

// Abas acessiveis (role="tab" dentro de role="tablist"): clique ou setas
// trocam a aba, e so a aba atual entra na ordem do Tab. aoTrocar(aba) e
// chamada quando o usuario troca. Devolve marcar(aba), que so muda a aba
// selecionada (ex.: a aba que veio no endereco), sem chamar aoTrocar.
export function prepararAbas(lista, aoTrocar) {
  const abas = [...lista.querySelectorAll('[role="tab"]')];
  const marcar = (aba) => {
    for (const a of abas) {
      a.setAttribute('aria-selected', String(a === aba));
      a.tabIndex = a === aba ? 0 : -1;
    }
    const painel = document.getElementById(aba.getAttribute('aria-controls'));
    painel?.setAttribute('aria-labelledby', aba.id);
  };
  const escolher = (aba) => {
    marcar(aba);
    aoTrocar(aba);
  };

  lista.addEventListener('click', (evento) => {
    const aba = evento.target.closest('[role="tab"]');
    if (aba) escolher(aba);
  });
  lista.addEventListener('keydown', (evento) => {
    const i = abas.indexOf(document.activeElement);
    const destino = { ArrowRight: i + 1, ArrowLeft: i - 1, Home: 0, End: abas.length - 1 }[evento.key];
    if (i < 0 || destino === undefined) return;
    evento.preventDefault();
    const aba = abas[(destino + abas.length) % abas.length];
    escolher(aba);
    aba.focus();
  });
  return marcar;
}

// ---------- Janelas (dialog) ----------

// Prepara uma janela <dialog> com formulario. Enter ou o botao de envio
// chamam aoEnviar() sem fechar a janela; aoEnviar() pode devolver o elemento
// que recebe o foco ou 'fechar'. Enquanto aoEnviar() roda, Esc e [data-fechar] nao fecham
// (o pedido ja foi enviado ao banco). Ao fechar, se o botao que abriu a
// janela sumiu (tabela redesenhada), o foco vai para `retorno`.
export function prepararJanela(janela, { aoEnviar, retorno }) {
  const form = janela.querySelector('form');
  const botoesFechar = janela.querySelectorAll('[data-fechar]');
  let ocupada = false;

  const marcarOcupada = (valor) => {
    ocupada = valor;
    janela.setAttribute('aria-busy', String(valor));
    for (const botao of botoesFechar) botao.disabled = valor;
  };

  form.addEventListener('submit', async (evento) => {
    evento.preventDefault();
    if (ocupada) return;
    marcarOcupada(true);
    let resultado = null;
    try {
      resultado = await aoEnviar();
    } finally {
      marcarOcupada(false);
      if (resultado === 'fechar') janela.close();
      else resultado?.focus?.();
    }
  });
  for (const botao of botoesFechar) {
    botao.addEventListener('click', () => {
      if (!ocupada) janela.close();
    });
  }
  janela.addEventListener('cancel', (evento) => {
    if (ocupada) evento.preventDefault();
  });
  janela.addEventListener('close', (evento) => {
    // O navegador pode fechar a janela mesmo com o Esc bloqueado (no Chrome,
    // o segundo Esc seguido). Com o pedido em andamento, ela reabre na hora
    // e a pagina nem fica sabendo (os outros ouvintes de "close" nao rodam).
    if (ocupada) {
      evento.stopImmediatePropagation();
      janela.showModal();
      return;
    }
    if (retorno && (!document.activeElement || document.activeElement === document.body)) retorno.focus();
  });
}

// ---------- Usuario selecionado ("Entrar como") ----------

async function carregarUsuarios() {
  const seletor = document.getElementById('usuario-atual');
  const linkPerfil = document.getElementById('link-meu-perfil');

  let usuarios;
  try {
    usuarios = await api('/usuarios');
  } catch (err) {
    seletor.innerHTML = '<option>Indisponível</option>';
    mostrarAvisoGlobal(err.message);
    return null;
  }

  // Mantem a escolha anterior; na primeira visita, usa o usuario de demonstracao.
  const salvo = usuarios.find((u) => u.id === lerUsuarioSalvo());
  const usuario = salvo ?? usuarios.find((u) => u.apelido === USUARIO_PADRAO) ?? usuarios[0];
  salvarUsuario(usuario.id);

  seletor.innerHTML = usuarios.map((u) => `
    <option value="${u.id}"${u.id === usuario.id ? ' selected' : ''}>${escaparHtml(u.apelido)} (${escaparHtml(u.nome)})</option>
  `).join('');
  seletor.disabled = false;
  seletor.addEventListener('change', () => {
    salvarUsuario(Number(seletor.value));
    location.reload(); // inventario, anuncios e compras dependem do usuario
  });

  linkPerfil.href = `/usuario/${usuario.id}`;
  linkPerfil.classList.remove('oculto');

  return usuario;
}

function lerUsuarioSalvo() {
  try {
    return Number(localStorage.getItem(CHAVE_USUARIO)) || null;
  } catch {
    return null;
  }
}

function salvarUsuario(id) {
  try {
    localStorage.setItem(CHAVE_USUARIO, String(id));
  } catch {
    // Navegador sem localStorage: a escolha vale so para esta visita.
  }
}

// ---------- Estados de tela: vazio e erro ----------

export function mostrarEstado(elemento, titulo, texto = '', tipo = '') {
  elemento.className = `estado${tipo ? ` estado-${tipo}` : ''}`;
  elemento.innerHTML = `<strong>${escaparHtml(titulo)}</strong>${escaparHtml(texto)}`;
}

// ---------- Imagem do item ----------

// Conteudo de .card-imagem: a imagem do item (link no banco) ou, sem link,
// o nome da arma (antes do " | ") na cor da raridade.
export function imagemDoItem(item) {
  const nomeCurto = escaparHtml(String(item.nome).split(' | ')[0]);
  if (/^https?:\/\//.test(item.imagem ?? '')) {
    return `<img src="${escaparHtml(item.imagem)}" alt="" loading="lazy" data-sem-imagem="${nomeCurto}">`;
  }
  return `<span class="sem-imagem" aria-hidden="true">${nomeCurto}</span>`;
}

// Imagem que nao carrega (ex.: link fora do ar) tambem vira o nome colorido.
// O evento "error" de imagem nao sobe pela pagina; por isso a captura (true).
document.addEventListener('error', (evento) => {
  const img = evento.target;
  if (!(img instanceof HTMLImageElement) || img.dataset.semImagem === undefined) return;
  const nome = document.createElement('span');
  nome.className = 'sem-imagem';
  nome.setAttribute('aria-hidden', 'true');
  nome.textContent = img.dataset.semImagem;
  img.replaceWith(nome);
}, true);

// ---------- Formatacao ----------

const moeda = new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' });

export function formatarPreco(valor) {
  return valor === null || valor === undefined ? '—' : moeda.format(Number(valor));
}

// '2026-01-06' ou '2026-01-06 14:00:00' -> '06/01/2026' (sem conversao de fuso:
// a API ja entrega no horario de Sao Paulo).
export function formatarData(valor) {
  if (!valor) return '—';
  const [ano, mes, dia] = String(valor).slice(0, 10).split('-');
  return `${dia}/${mes}/${ano}`;
}

// '2026-01-06 14:00:00' -> '06/01/2026 14:00'
export function formatarDataHora(valor) {
  if (!valor) return '—';
  return `${formatarData(valor)} ${String(valor).slice(11, 16)}`.trim();
}

// 0.1523 -> '0,1523'
export function formatarFloat(valor, casas = 4) {
  return valor === null || valor === undefined ? '—' : Number(valor).toFixed(casas).replace('.', ',');
}

// 4.5 -> '4,5'
export function formatarNota(nota) {
  return Number(nota).toFixed(1).replace('.', ',');
}

// Codigo de desgaste (fn_desgaste) -> nome.
export const NOMES_DESGASTE = {
  FN: 'Factory New', MW: 'Minimal Wear', FT: 'Field-Tested', WW: 'Well-Worn', BS: 'Battle-Scarred',
};

// Nomes dos tipos de cosmetico e consumivel, como aparecem na tela.
export const NOMES_TIPO = {
  adesivo: 'Adesivo', chaveiro: 'Chaveiro',
  caixa: 'Caixa', capsula: 'Cápsula', chave: 'Chave', grafite: 'Grafite',
};

// Situacao vinda do banco (sem acento) -> texto da tela.
export const NOMES_STATUS = {
  pendente: 'Pendente', cancelado: 'Cancelado', cancelada: 'Cancelada', expirado: 'Expirado',
  concluida: 'Concluída', recusado: 'Recusado', recusada: 'Recusada', aceita: 'Aceita',
};

export const NOMES_PAGAMENTO = {
  pix: 'Pix', cartao_credito: 'Cartão de crédito', cartao_debito: 'Cartão de débito',
  boleto: 'Boleto', saldo_steam: 'Saldo Steam',
};

// Celula de tabela com rotulo: em tela pequena a linha vira um cartao e o
// rotulo aparece ao lado do valor (CSS .tabela-responsiva).
export function celula(rotulo, conteudo, classe = '') {
  return `<td${classe ? ` class="${classe}"` : ''} data-rotulo="${escaparHtml(rotulo)}"><div>${conteudo}</div></td>`;
}

// Versao de uma arma, faca ou luva: desgaste + StatTrak/Souvenir
// (ex.: Factory New StatTrak). Vazio para cosmeticos e consumiveis.
export function nomeVersao(item) {
  if (!item.desgaste) return '';
  return [NOMES_DESGASTE[item.desgaste], item.stattrak && 'StatTrak™', item.souvenir && 'Souvenir']
    .filter(Boolean).join(' ');
}

// Com que vendas a media foi calculada (base_media de
// fn_media_vendas_comparaveis): as da mesma versao ou, com poucas, todas as
// do modelo. Sem versao (cosmeticos e consumiveis) nao ha o que explicar.
export function baseDaMedia(base, versao) {
  if (!versao) return '';
  return base === 'versao' ? versao : 'todas as versões';
}

// Diferenca percentual de um preco para a media das vendas comparaveis.
export function analisePreco(percentual, base, versao = '') {
  if (percentual === null || percentual === undefined) return '';
  const p = Number(percentual);
  const referencia = baseDaMedia(base, versao);
  const detalhe = referencia ? `<small class="texto-suave">(${escaparHtml(referencia)})</small>` : '';
  if (Math.abs(p) < 0.5) return `<span class="analise-preco">na média das vendas${detalhe}</span>`;
  const texto = `${Math.abs(p).toFixed(1).replace('.', ',')}% ${p < 0 ? 'abaixo' : 'acima'} da média`;
  return `<span class="analise-preco ${p < 0 ? 'abaixo' : 'acima'}">${texto}${detalhe}</span>`;
}

export function escaparHtml(texto) {
  return String(texto ?? '').replace(/[&<>"']/g, (c) => (
    { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]
  ));
}
