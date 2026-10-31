// Carrega o SQL de database/consultas/: cada bloco "-- name: <nome>" vira
// uma consulta que a API executa pelo nome (formato descrito em
// database/consultas/README.md). Nenhum SQL fica espalhado pelo codigo.
import fs from 'node:fs';

const PASTA = new URL('../database/consultas/', import.meta.url);

export function carregarConsultas() {
  const consultas = new Map();

  for (const arquivo of fs.readdirSync(PASTA).filter((f) => f.endsWith('.sql'))) {
    const texto = fs.readFileSync(new URL(arquivo, PASTA), 'utf8');

    for (const bloco of texto.split(/^-- name: /m).slice(1)) {
      const fimDaLinha = bloco.indexOf('\n');
      const nome = bloco.slice(0, fimDaLinha).trim();
      if (consultas.has(nome)) {
        throw new Error(`Consulta duplicada em database/consultas: ${nome} (${arquivo})`);
      }
      consultas.set(nome, bloco.slice(fimDaLinha + 1));
    }
  }

  return consultas;
}
