// Monta a aplicacao Express: arquivos estaticos, API e paginas.
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import express from 'express';
import { rotasApi } from './rotas/api.js';
import { rotasPaginas } from './rotas/paginas.js';
import { tratarErros } from './erros.js';

// public/ -> CSS, JavaScript e imagens, servidos como arquivos estaticos.
// views/  -> paginas HTML, entregues pelas rotas de src/rotas/paginas.js.
const PASTA_PUBLIC = fileURLToPath(new URL('../public', import.meta.url));
const PASTA_VIEWS = fileURLToPath(new URL('../views', import.meta.url));

export function criarApp() {
  const app = express();
  app.disable('x-powered-by');

  // Cabecalhos de seguranca (o site e publico). A politica de conteudo so
  // deixa rodar scripts do proprio site; fontes do Google Fonts; imagens de
  // qualquer endereco https (as imagens oficiais vem do CDN da Steam).
  app.use((req, res, next) => {
    res.set({
      'Content-Security-Policy': [
        "default-src 'self'",
        "script-src 'self'",
        "style-src 'self' 'unsafe-inline' https://fonts.googleapis.com",
        "font-src https://fonts.gstatic.com",
        "img-src 'self' https: data:",
        "connect-src 'self'",
        "frame-ancestors 'none'",
        "base-uri 'self'",
        "form-action 'self'",
      ].join('; '),
      'X-Content-Type-Options': 'nosniff',
      'Referrer-Policy': 'same-origin',
    });
    next();
  });

  app.use(express.static(PASTA_PUBLIC, { index: false }));
  app.use(express.json());

  app.use('/api', rotasApi());
  app.use(rotasPaginas(PASTA_VIEWS));

  app.use((req, res) => {
    res.status(404).sendFile(path.join(PASTA_VIEWS, '404.html'));
  });

  // Erros das rotas (inclusive os do banco) viram respostas JSON.
  app.use(tratarErros);

  return app;
}
