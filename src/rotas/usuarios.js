// API dos usuarios: seletor "Entrar como" e pagina Perfil (/api/usuarios).
// Consultas em database/consultas/comum.sql e perfil.sql.
import { Router } from 'express';
import { consultar, expirarAnunciosVencidos } from '../banco.js';
import { ErroApi } from '../erros.js';
import { inteiroObrigatorio } from '../parametros.js';

export function rotasUsuarios() {
  const rotas = Router();

  // Seletor "Entrar como".
  rotas.get('/', async (req, res) => {
    res.json(await consultar('listar_usuarios'));
  });

  // Perfil publico: dados e reputacao, anuncios ativos, avaliacoes
  // recebidas e historico de trocas.
  rotas.get('/:id', async (req, res) => {
    const id = inteiroObrigatorio(req.params.id, 'o id do usuário');
    await expirarAnunciosVencidos();
    const [[usuario], anuncios, avaliacoes, trocas] = await Promise.all([
      consultar('perfil_usuario', [id]),
      consultar('anuncios_ativos_do_usuario', [id]),
      consultar('avaliacoes_recebidas', [id]),
      consultar('trocas_do_usuario', [id]),
    ]);
    if (!usuario) throw new ErroApi(404, 'Usuário não encontrado.');
    res.json({ usuario, anuncios, avaliacoes, trocas });
  });

  return rotas;
}
