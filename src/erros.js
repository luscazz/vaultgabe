// Tratamento de erros da API: transforma erros do banco em respostas JSON
// com mensagens que podem ser mostradas ao usuario.

// Erro com status HTTP e mensagem pronta para o usuario.
export class ErroApi extends Error {
  constructor(status, mensagem) {
    super(mensagem);
    this.status = status;
  }
}

// Codigos de erro do PostgreSQL -> status HTTP.
const STATUS_POR_CODIGO = {
  P0001: 422,   // RAISE EXCEPTION dos triggers e funcoes: regra de negocio violada
  '23505': 409, // UNIQUE: o dado ja existe (ex.: segundo anuncio aberto do mesmo item)
  '23514': 400, // CHECK: valor fora do permitido
  '23503': 400, // FK: referencia a algo que nao existe
  '22P02': 400, // texto que nao converte para o tipo esperado
  '22003': 400, // numero fora do intervalo do tipo
  '22007': 400, // data em formato invalido
  '22008': 400, // data fora do intervalo aceito
};

// Mensagens amigaveis para as restricoes que o usuario pode esbarrar.
const MENSAGEM_POR_RESTRICAO = {
  anuncio_aberto_por_item_uk: 'Este item já tem um anúncio aberto.',
  anuncio_preco_ck:           'O preço precisa ser maior que zero.',
  anuncio_datas_ck:           'A validade do anúncio precisa ser depois da publicação.',
  avaliacao_nota_ck:          'A nota precisa ser de 1 a 5.',
  avaliacao_partes_ck:        'Ninguém pode avaliar a si mesmo.',
  pagamento_metodo_ck:        'Forma de pagamento inválida.',
};

// Mensagens dos triggers e funcoes (02_regras.sql) reescritas para o
// usuario: sem ids internos e com acentos. As demais passam como vieram.
const MENSAGEM_POR_REGRA = [
  [/nao pode comprar o proprio item/, 'Você não pode comprar o seu próprio anúncio.'],
  [/O anuncio \d+ nao existe/, 'Anúncio não encontrado.'],
  [/nao esta ativo/, 'Este anúncio não está mais à venda.'],
  [/venceu em/, 'Este anúncio já venceu.'],
  [/ja tem uma venda em andamento/, 'Este anúncio já tem uma venda em andamento.'],
  [/O item do anuncio \d+ nao esta mais disponivel/, 'O item deste anúncio não está mais disponível.'],
  [/nao e dono do item/, 'Você não é dono deste item.'],
  [/nao esta disponivel para negociacao/, 'Este item não está disponível para negociação.'],
  [/tem uma venda pendente e nao pode ser encerrado/, 'Este anúncio tem uma venda pendente e não pode ser encerrado.'],
  [/ja esta encerrado/, 'Este anúncio já está encerrado.'],
  [/ja avaliou a venda/, 'Você já avaliou esta compra.'],
  [/nao participou da venda/, 'Só quem participou da venda pode avaliá-la.'],
  [/So e possivel avaliar uma venda concluida/, 'Só é possível avaliar uma compra concluída.'],
  [/A venda \d+ nao existe/, 'Compra não encontrada.'],
];

// Falhas de rede ou do servidor do banco: o problema nao e do pedido.
const CODIGOS_BANCO_INDISPONIVEL = new Set([
  'ECONNREFUSED', 'ECONNRESET', 'ENOTFOUND', 'ETIMEDOUT', 'EAI_AGAIN',
  '57P01', '57P03', '08001', '08006', '53300',
]);

function mensagemDoBanco(err) {
  if (err.constraint && MENSAGEM_POR_RESTRICAO[err.constraint]) {
    return MENSAGEM_POR_RESTRICAO[err.constraint];
  }
  if (err.code === 'P0001') {
    const regra = MENSAGEM_POR_REGRA.find(([padrao]) => padrao.test(err.message));
    return regra ? regra[1] : err.message; // mensagem escrita no trigger/funcao
  }
  return 'Os dados enviados são inválidos.';
}

function bancoIndisponivel(err) {
  return CODIGOS_BANCO_INDISPONIVEL.has(err.code)
    || /timeout|terminated|connect/i.test(err.message ?? '');
}

// Middleware final do Express: toda falha de rota da API termina aqui.
export function tratarErros(err, req, res, next) {
  if (res.headersSent) return next(err);

  if (err instanceof ErroApi) {
    return res.status(err.status).json({ erro: err.message });
  }

  // Corpo do pedido que o express.json() recusou: JSON malformado (400) ou
  // grande demais (413). O problema e do pedido, nao do servidor.
  if (err.type === 'entity.parse.failed') {
    return res.status(400).json({ erro: 'O corpo do pedido não é um JSON válido.' });
  }
  if (err.status >= 400 && err.status < 500 && err.expose) {
    return res.status(err.status).json({ erro: 'Pedido inválido.' });
  }

  if (STATUS_POR_CODIGO[err.code]) {
    return res.status(STATUS_POR_CODIGO[err.code]).json({ erro: mensagemDoBanco(err) });
  }

  if (bancoIndisponivel(err)) {
    console.error('Banco indisponivel:', err.code ?? '', err.message);
    return res.status(503).json({
      erro: 'Não foi possível falar com o banco de dados. Tente de novo em instantes.',
    });
  }

  // Erro inesperado: registra no console e nao expoe detalhes ao usuario.
  console.error(err);
  res.status(500).json({ erro: 'Erro interno do servidor.' });
}
