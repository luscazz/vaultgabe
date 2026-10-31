// API da pagina Negociacoes (/api/negociacoes). Consultas em
// database/consultas/negociacoes.sql.
import { Router } from 'express';
import { consultar, expirarAnunciosVencidos } from '../banco.js';
import { inteiroObrigatorio } from '../parametros.js';

export function rotasNegociacoes() {
  const rotas = Router();

  // As quatro abas de uma vez (sao listas curtas): a venda, vendidos,
  // comprados e encerrados, mais os numeros de cada aba.
  rotas.get('/', async (req, res) => {
    const usuario = inteiroObrigatorio(req.query.usuario, 'o usuário');
    await expirarAnunciosVencidos();
    const [[contagens], aVenda, vendidos, comprados, encerrados] = await Promise.all([
      consultar('contar_negociacoes', [usuario]),
      consultar('anuncios_a_venda', [usuario]),
      consultar('anuncios_vendidos', [usuario]),
      consultar('compras_do_usuario', [usuario]),
      consultar('anuncios_encerrados', [usuario]),
    ]);
    res.json({ contagens, a_venda: aVenda, vendidos, comprados, encerrados });
  });

  return rotas;
}
