<p align="center"><img src="public/img/logo-vaultgabe.webp" width="180" alt="Logo do VaultGabe"></p>

# VaultGabe

Marketplace de skins de Counter-Strike 2: busca no catálogo com filtros combinados, inventário de cada usuário, publicação e cancelamento de anúncios, compra com pagamento simulado e avaliação do vendedor.

**Aplicação no ar:** https://vaultgabe.onrender.com (no plano gratuito do Render, o primeiro acesso depois de um tempo sem uso pode levar cerca de 1 minuto)

Projeto da disciplina **Banco de Dados II**, construído sobre o banco desenvolvido em Banco de Dados I: as mesmas 20 tabelas, com acréscimos para a aplicação (índices, visões, funções e triggers) e as correções listadas em [`docs/mapeamento_banco.md`](docs/mapeamento_banco.md), seção 5.

**Autores:** Lucas Ienne, Lucas Silveira, Vinicius de Paula e Gabriel Trevisoli.

## Créditos

Imagens e nomes dos itens © Valve Corporation. Os links das imagens oficiais e os dados dos itens vêm do [CSGO-API](https://github.com/ByMykel/CSGO-API) (projeto não oficial). O VaultGabe é um projeto acadêmico, sem fins comerciais e sem vínculo com a Valve.

## Tecnologias

| Camada | Tecnologia |
|---|---|
| Banco de dados | PostgreSQL, hospedado no [Neon](https://neon.tech) |
| Backend | Node.js + Express |
| Frontend | HTML, CSS e JavaScript |
| Hospedagem | [Render](https://render.com) |

## Páginas

| Página | Endereço | Funcionalidades |
|---|---|---|
| Catálogo | `/` | Buscar skins com filtros combinados (categoria, raridade, coleção, preço, desgaste, StatTrak, adesivos) |
| Detalhe da skin | `/skin/:id` | Comparar ofertas, ver o gráfico e o histórico de preços e **comprar** (pagamento simulado) |
| Inventário | `/inventario` | Ver os itens do usuário e **anunciar**, com análise de preço |
| Negociações | `/negociacoes` | Acompanhar e **cancelar** anúncios; ver vendas e compras e **avaliar o vendedor** |
| Análise de mercado *(extra)* | `/analise` | Indicadores, gráficos e rankings por período e categoria |
| Perfil do usuário | `/usuario/:id` | Reputação, avaliações recebidas, anúncios ativos e trocas |

O enunciado pede um de dois temas. O VaultGabe segue o de **buscas complexas de forma simplificada e inserção de dados** (Catálogo, Detalhe, Inventário e Negociações). Os **gráficos** (Análise de mercado e gráfico de preço do Detalhe) são um extra que cobre parte do outro tema (análise visual e estatística).

Não há login: o seletor **"Entrar como"**, no topo, escolhe o usuário de demonstração (padrão: `isizinha`).

Usuários, preços, vendas e avaliações são dados simulados para demonstração; o site avisa isso no rodapé e na Análise de mercado.

O escopo detalhado de cada página está em [`docs/escopo.md`](docs/escopo.md).

## Estrutura do projeto

```
vaultgabe/
├── database/          Scripts SQL que montam o banco (ver database/README.md)
│   ├── carregar.mjs   Monta uma branch do Neon com 01 a 04 (npm run banco:dev)
│   └── consultas/     SQL usado pela aplicação, um arquivo por página
├── docs/
│   ├── escopo.md              Telas, funcionalidades e prioridades da aplicação
│   └── mapeamento_banco.md    Tabelas, regras, dados e correções em relação ao BD I
├── public/            Arquivos enviados direto ao navegador
│   ├── css/estilo.css    Identidade visual
│   ├── js/               JavaScript de cada página (+ comum.js: topo, janelas, formatação;
│   │                     graficos.js: gráficos em SVG, sem biblioteca externa)
│   └── img/              Logo
├── src/               Servidor Node.js (Express)
│   ├── server.js         Ponto de entrada
│   ├── app.js            Monta a aplicação: arquivos, API, páginas e erros
│   ├── banco.js          Conexão com o PostgreSQL e execução das consultas pelo nome
│   ├── consultas.js      Carrega o SQL de database/consultas/
│   ├── erros.js          Transforma erros do banco em mensagens para o usuário
│   ├── parametros.js     Lê e valida os parâmetros que chegam do navegador
│   └── rotas/            Rotas da API (api.js + um arquivo por página ou janela) e das páginas (paginas.js)
├── views/             Páginas HTML
├── tests/             Testes do banco (npm test) e da API (npm run test:neon)
├── .env.example       Modelo das variáveis de ambiente
├── render.yaml        Configuração da hospedagem no Render
└── package.json
```

## Como rodar no computador

Requisitos: **Node.js 22.9 ou mais novo**.

1. Instale as dependências:
   ```bash
   npm install
   ```
2. Copie `.env.example` para um arquivo chamado `.env` e preencha as URLs de conexão do Neon: `DATABASE_URL` (branch `development`, usada pelo servidor e pelos testes) e `DATABASE_URL_PRODUCAO` (branch `production`, usada por `npm run banco:producao`; `npm run banco:dev` e `npm run test:neon` também a leem, só para se recusarem a rodar na produção).
3. Monte o banco (na primeira vez ou para restaurar os dados de demonstração):
   ```bash
   npm run banco:dev
   ```
4. Inicie o servidor:
   ```bash
   npm run dev
   ```
   e acesse **http://localhost:3000**. Com `npm run dev`, o servidor reinicia automaticamente a cada alteração no código.

> O arquivo `.env` contém a senha do banco e **nunca** deve ser enviado ao GitHub (ele já está no `.gitignore`).

Os scripts do banco estão em `database/` (ver [`database/README.md`](database/README.md)).

## API

O navegador busca os dados em rotas `/api/...`. Cada rota executa uma consulta de [`database/consultas/`](database/consultas/README.md) pelo nome; o SQL nunca vem do navegador.

| Rota | O que devolve |
|---|---|
| `GET /api/saude` | Situação do servidor e do banco (versão, fuso, tempo de resposta) |
| `GET /api/usuarios` | Usuários do seletor "Entrar como" |
| `GET /api/usuarios/:id` | Perfil público: reputação, números, anúncios ativos, avaliações recebidas e trocas |
| `GET /api/catalogo/filtros` | Categorias, raridades e coleções para os filtros, com quantidades |
| `GET /api/catalogo` | Busca do catálogo. Parâmetros opcionais: `busca`, `categoria`, `raridade`, `colecao`, `preco_min`, `preco_max`, `so_a_venda`, `desgaste` (`FN` `MW` `FT` `WW` `BS`), `stattrak`, `souvenir`, `com_adesivos`, `ordenar` (`menor_preco`, `maior_preco`, `mais_ofertas`, `mais_vendidas`, `nome`) |
| `GET /api/skins/:id` | Dados de uma skin (modelo): categoria, raridade, coleção, faixa de float e indicadores de preço |
| `GET /api/skins/:id/ofertas` | Ofertas ativas da skin, com float, desgaste, cosméticos aplicados, vendedor e análise do preço. Parâmetros opcionais: `desgaste`, `stattrak`, `souvenir`, `com_adesivos`, `ordenar` (`preco` ou `float`) e `usuario` (marca os anúncios do próprio usuário) |
| `GET /api/skins/:id/historico` | Vendas concluídas da skin e o resumo por mês |
| `POST /api/compras` | Compra simulada de um anúncio. Corpo: `{ "anuncio_id", "comprador_id", "metodo" }`, com `metodo` entre `pix`, `cartao_credito`, `cartao_debito`, `boleto` e `saldo_steam`. Devolve 201 com o protocolo da venda e a chave da nota fiscal |
| `GET /api/inventario?usuario=` | Itens do usuário com a situação de cada um (disponível, anunciado, aplicado...) e o resumo. Opcionais: `tipo` (`equipamento`, `cosmetico`, `consumivel`) e `negociaveis` (só os itens prontos para anunciar: disponíveis, negociáveis e sem anúncio aberto; o `resumo` sempre traz todos os itens) |
| `GET /api/anuncios/analise-preco?item=` | Menor oferta atual (sem as reservadas) e média das vendas da mesma versão do item (desgaste, StatTrak e Souvenir) ou, com menos de 2 vendas, de todo o modelo (`base_media`); com `preco`, a diferença para essa média |
| `POST /api/anuncios` | Publica um anúncio. Corpo: `{ "item_id", "usuario_id", "preco", "dias" }` (`dias`: 7, 14 ou 30). Devolve 201 |
| `POST /api/anuncios/:id/cancelar` | Cancela um anúncio aberto do próprio usuário. Corpo: `{ "usuario_id" }` |
| `GET /api/negociacoes?usuario=` | Anúncios à venda, vendas, compras e anúncios encerrados do usuário, com os números de cada aba |
| `POST /api/avaliacoes` | Avalia o vendedor de uma compra concluída. Corpo: `{ "venda_id", "autor_id", "nota", "comentario" }`. Devolve 201 com o ticket |
| `GET /api/analise` | Indicadores, vendas por mês, preço médio por raridade, volume por categoria e rankings. Opcionais: `inicio`, `fim` (`AAAA-MM-DD`) e `categoria` |

Parâmetros que se repetem aceitam vários valores (`?categoria=1&categoria=2` ou `?categoria=1,2`); valor inválido devolve 400. Erros de regra de negócio voltam como `{ "erro": "mensagem" }`, com o status adequado (400, 404, 409, 422 ou 503 se o banco estiver fora do ar).

## Testes

| Comando | O que faz |
|---|---|
| `npm test` | Monta o banco em memória, sem internet, e confere as regras de negócio, as operações (compra, anúncio, cancelamento e avaliação), as 34 consultas e os dados de demonstração |
| `npm run test:neon` | Os mesmos testes, mais os da API, na branch `development` do Neon, que é recarregada no fim. Não roda na produção |

Os anúncios de demonstração vencem a partir de 01/04/2027. Depois dessa data, os testes de compra só voltam a passar com validades novas nos dados.

## Publicação

O site roda no Render, configurado pelo [`render.yaml`](render.yaml), com o banco na branch `production` do Neon. A URL do banco fica na variável `DATABASE_URL`, definida no painel do Render (nunca no repositório), e cada commit na branch `main` publica uma nova versão.

Para recriar o banco de produção, quando os scripts de `database/` mudam ou para restaurar os dados de demonstração, use `npm run banco:producao -- --confirmo`.
