// API da pagina Catalogo (/api/catalogo). Consultas em database/consultas/catalogo.sql.
import { Router } from 'express';
import { consultar, expirarAnunciosVencidos } from '../banco.js';
import { DESGASTES, texto, inteiro, listaDeInteiros, numero, marcado, umDe, listaDe } from '../parametros.js';

const ORDENACOES = ['menor_preco', 'maior_preco', 'mais_ofertas', 'mais_vendidas', 'nome'];

export function rotasCatalogo() {
  const rotas = Router();

  // Opcoes dos filtros: categorias, raridades e colecoes (com quantidades).
  rotas.get('/filtros', async (req, res) => {
    const [categorias, raridades, colecoes] = await Promise.all([
      consultar('listar_categorias'),
      consultar('listar_raridades'),
      consultar('listar_colecoes'),
    ]);
    res.json({ categorias, raridades, colecoes });
  });

  // Busca do catalogo. Todos os parametros sao opcionais:
  //   busca, categoria (varios), raridade (varios), colecao, preco_min,
  //   preco_max, so_a_venda, desgaste (varios: FN MW FT WW BS), stattrak,
  //   souvenir, com_adesivos, ordenar
  rotas.get('/', async (req, res) => {
    const q = req.query;
    const parametros = [
      texto(q.busca),
      listaDeInteiros(q.categoria, 'categoria'),
      listaDeInteiros(q.raridade, 'raridade'),
      inteiro(q.colecao, 'colecao'),
      numero(q.preco_min, 'preco_min'),
      numero(q.preco_max, 'preco_max'),
      marcado(q.so_a_venda),
      listaDe(q.desgaste, DESGASTES, 'desgaste'),
      marcado(q.stattrak),
      marcado(q.souvenir),
      marcado(q.com_adesivos),
      umDe(q.ordenar, ORDENACOES, 'ordenar', 'menor_preco'),
    ];

    await expirarAnunciosVencidos();
    res.json(await consultar('buscar_catalogo', parametros));
  });

  return rotas;
}
