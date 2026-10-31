# Banco de dados do VaultGabe

Scripts PostgreSQL que montam o banco do zero. Execute **sempre nesta ordem**:

| Ordem | Arquivo | O que faz |
|---|---|---|
| 1 | `01_tabelas.sql` | Cria as 20 tabelas, com chaves, restrições (`CHECK`, `UNIQUE`, `FK`), índices e 3 visões de apoio às consultas |
| 2 | `02_regras.sql` | Cria os triggers das regras de negócio e as funções que a aplicação chama (comprar, avaliar, expirar anúncios, média da análise de preço) |
| 3 | `03_dados.sql` | Insere os dados de demonstração vindos do BD I, com correções (usuários, itens, anúncios, vendas, trocas...) |
| 4 | `04_dados_ampliados.sql` | Amplia os dados: catálogo com 80 modelos reais, mais exemplares, histórico de vendas simuladas em 12 meses, avaliações e anúncios ativos. A seção 11 corrige alguns dados do 03 (coleções, datas dos chaveiros, variantes, preço da cápsula, aberturas e acentos) |
| 5 | `05_verificacao.sql` | Confere as contagens e as regras que o banco não garante sozinho (somente `SELECT`) |

> **Atenção:** `01_tabelas.sql` apaga todas as tabelas, e `03_dados.sql` apaga todos os dados antes de reinserir. O `04_dados_ampliados.sql` só pode rodar logo depois do 03 (ele acrescenta dados e continua a numeração das vendas).
> Nunca execute esses dois arquivos em um banco cujos dados precisam ser mantidos.

## Banco na nuvem (Neon)

O banco fica no [Neon](https://neon.tech), no projeto `vaultgabe_t1` (região AWS US East 2, Ohio; PostgreSQL 18). O projeto tem duas **branches**, cópias independentes do banco:

| Branch | Uso | Variável no `.env` |
|---|---|---|
| `production` | Banco do site publicado (Render) | `DATABASE_URL_PRODUCAO` |
| `development` | Desenvolvimento e testes no computador | `DATABASE_URL` |

- As duas estão configuradas com `timezone = America/Sao_Paulo` e montadas com `01` a `04`: a `development` com `npm run banco:dev` e a `production`, usada pelo site, com `npm run banco:producao -- --confirmo` (ver [`README.md`](../README.md), seção Publicação).
- Numa branch ou banco novo, configure o fuso uma vez antes de montar: `ALTER DATABASE <nome_do_banco> SET timezone = 'America/Sao_Paulo';` (no Neon, o banco padrão é `neondb`; vale para as conexões abertas depois).
- **Testes que gravam dados** (compras, anúncios, avaliações) rodam **só na `development`**. Para restaurar os dados de demonstração, execute novamente 01 a 04 nessa branch (o `npm run test:neon` já faz isso ao final).
- As connection strings ficam **apenas** no `.env`, que não vai para o GitHub (ver `.env.example`).

## Como executar

### Opção 1 — Comando do projeto (recomendado)

Na pasta `vaultgabe_t1`, com o `.env` preenchido:

| Comando | O que faz |
|---|---|
| `npm run banco:dev` | Monta a branch `development` com 01 a 04 e roda o 05. Também lê `DATABASE_URL_PRODUCAO`, só para se recusar a rodar se `DATABASE_URL` apontar para a produção |
| `npm run banco:producao -- --confirmo` | O mesmo na branch `production` (sem `--confirmo`, não faz nada) |

Ao final, o comando informa se o 05 retornou `OK` em todas as verificações e exibe os números do banco (modelos, itens, vendas e anúncios ativos).

### Opção 2 — Editor visual (pgAdmin, DBeaver, DataGrip ou o SQL Editor do Neon)

Abra cada arquivo, na ordem acima, e execute o conteúdo inteiro.

### Opção 3 — Terminal (`psql`)

Dentro desta pasta, troque `<URL_DO_BANCO>` pela URL de conexão:

```bash
psql "<URL_DO_BANCO>" -v ON_ERROR_STOP=1 -f 01_tabelas.sql
psql "<URL_DO_BANCO>" -v ON_ERROR_STOP=1 -f 02_regras.sql
psql "<URL_DO_BANCO>" -v ON_ERROR_STOP=1 -f 03_dados.sql
psql "<URL_DO_BANCO>" -v ON_ERROR_STOP=1 -f 04_dados_ampliados.sql
psql "<URL_DO_BANCO>" -f 05_verificacao.sql
```

`-v ON_ERROR_STOP=1` interrompe a execução no primeiro erro, em vez de seguir adiante com o banco pela metade.

## Como verificar o resultado

O `05_verificacao.sql` retorna três blocos de resultado:

1. **Contagens:** a coluna `situacao` deve mostrar `OK` em todas as tabelas.
2. **Regras semânticas (RS-01 a RS-25):** a coluna `resultado` deve mostrar `OK` em todas as linhas. Qualquer `*** VIOLADA ***` indica dado incoerente.
3. **Rastreabilidade:** consultas informativas que mostram as cardinalidades do modelo nos dados.

## Consultas da aplicação

A pasta [`consultas/`](consultas/README.md) guarda todo o SQL que a aplicação executa, com um arquivo por página. Esses arquivos **não** fazem parte da montagem do banco: o backend os carrega e executa cada consulta pelo nome.
