// API da pagina Inventario (/api/inventario). Consultas em
// database/consultas/inventario.sql.
import { Router } from 'express';
import { consultar, expirarAnunciosVencidos } from '../banco.js';
import { inteiroObrigatorio, marcado, umDe } from '../parametros.js';

const TIPOS = ['equipamento', 'cosmetico', 'consumivel'];

export function rotasInventario() {
  const rotas = Router();

  // Itens do usuario e o resumo do topo. Parametros: usuario (obrigatorio),
  // tipo (equipamento | cosmetico | consumivel) e negociaveis (so os itens
  // que podem ser anunciados agora). Os filtros valem so para a lista: o
  // resumo traz todos os itens e o numero de cada aba, com e sem o filtro.
  rotas.get('/', async (req, res) => {
    const q = req.query;
    const usuario = inteiroObrigatorio(q.usuario, 'o usuário');
    const tipo = umDe(q.tipo, TIPOS, 'tipo');

    await expirarAnunciosVencidos();
    const [[resumo], itens] = await Promise.all([
      consultar('resumo_inventario', [usuario]),
      consultar('inventario_usuario', [usuario, tipo, marcado(q.negociaveis)]),
    ]);
    res.json({ resumo, itens });
  });

  return rotas;
}
