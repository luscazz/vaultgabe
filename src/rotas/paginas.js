// Rotas das paginas do site (docs/escopo.md, secao 2).
// Cada rota entrega um arquivo HTML de views/; o JavaScript da pagina
// busca os dados na API depois que ela abre.
import path from 'node:path';
import { Router } from 'express';

const PAGINAS = {
  '/':            'catalogo.html',
  '/inventario':  'inventario.html',
  '/negociacoes': 'negociacoes.html',
  '/analise':     'analise.html',
};

// Paginas que recebem um id numerico no endereco.
const PAGINAS_COM_ID = {
  '/skin/:id':    'skin.html',
  '/usuario/:id': 'perfil.html',
};

export function rotasPaginas(pastaViews) {
  const rotas = Router();
  const enviar = (arquivo) => (req, res) => res.sendFile(path.join(pastaViews, arquivo));

  for (const [endereco, arquivo] of Object.entries(PAGINAS)) {
    rotas.get(endereco, enviar(arquivo));
  }

  for (const [endereco, arquivo] of Object.entries(PAGINAS_COM_ID)) {
    rotas.get(endereco, (req, res, next) => {
      // Id que nao e numero (ex.: /skin/abc) cai no 404.
      if (!/^\d+$/.test(req.params.id)) return next();
      enviar(arquivo)(req, res);
    });
  }

  return rotas;
}
