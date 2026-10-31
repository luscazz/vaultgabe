// Rotas da API (/api/...). Cada rota executa uma consulta de
// database/consultas pelo nome; o SQL nunca vem do navegador.
// As rotas de cada pagina ficam num arquivo proprio (ex.: catalogo.js).
import { Router } from 'express';
import { verificarConexao, totalConsultas } from '../banco.js';
import { rotasUsuarios } from './usuarios.js';
import { rotasCatalogo } from './catalogo.js';
import { rotasSkins } from './skins.js';
import { rotasCompras } from './compras.js';
import { rotasInventario } from './inventario.js';
import { rotasAnuncios } from './anuncios.js';
import { rotasNegociacoes } from './negociacoes.js';
import { rotasAvaliacoes } from './avaliacoes.js';
import { rotasAnalise } from './analise.js';

export function rotasApi() {
  const api = Router();

  // Dados mudam a cada compra ou anuncio: o navegador nao deve guardar copia.
  api.use((req, res, next) => {
    res.set('Cache-Control', 'no-store');
    next();
  });

  // Saude da aplicacao e do banco (tambem usada pelo Render).
  api.get('/saude', async (req, res) => {
    try {
      const banco = await verificarConexao();
      res.json({ status: 'ok', banco: { conectado: true, ...banco }, consultas: totalConsultas() });
    } catch (err) {
      console.error('Falha ao verificar o banco:', err.message);
      res.status(503).json({ status: 'erro', banco: { conectado: false } });
    }
  });

  api.use('/usuarios', rotasUsuarios());       // seletor "Entrar como" e Perfil
  api.use('/catalogo', rotasCatalogo());       // Catalogo
  api.use('/skins', rotasSkins());             // Detalhe da skin
  api.use('/compras', rotasCompras());         // janela Comprar
  api.use('/inventario', rotasInventario());   // Inventario
  api.use('/anuncios', rotasAnuncios());       // janela Novo anuncio e cancelamento
  api.use('/negociacoes', rotasNegociacoes()); // Negociacoes
  api.use('/avaliacoes', rotasAvaliacoes());   // janela Avaliar vendedor
  api.use('/analise', rotasAnalise());         // Analise de mercado

  api.use((req, res) => {
    res.status(404).json({ erro: 'Rota da API não encontrada.' });
  });

  return api;
}
