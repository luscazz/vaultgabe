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

Usuários, preços, vendas e avaliações são dados simulados para demonstração.

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
├── tests/             Testes do banco (npm test)
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
2. Copie `.env.example` para um arquivo chamado `.env` e preencha as URLs de conexão do Neon: `DATABASE_URL` (branch `development`, usada pelo servidor) e `DATABASE_URL_PRODUCAO` (branch `production`; `npm run banco:dev` a lê só para se recusar a rodar na produção).
3. Monte o banco (na primeira vez ou para restaurar os dados de demonstração). Numa branch nova do Neon, configure antes o fuso `America/Sao_Paulo`, como explica o [`database/README.md`](database/README.md):
   ```bash
   npm run banco:dev
   ```
4. Inicie o servidor:
   ```bash
   npm run dev
   ```
   e acesse **http://localhost:3000**.

## API

O navegador busca os dados em rotas `/api/...`. Cada rota executa uma consulta de [`database/consultas/`](database/consultas/README.md) pelo nome; o SQL nunca vem do navegador.

| Rota | Para que serve |
|---|---|
| `GET /api/saude` | Informar a situação do servidor e do banco |
| `GET /api/usuarios` | Listar os usuários do seletor "Entrar como" |
| `GET /api/usuarios/:id` | Mostrar o perfil público de um usuário |
| `GET /api/catalogo/filtros` | Carregar as opções dos filtros do catálogo |
| `GET /api/catalogo` | Buscar skins no catálogo |
| `GET /api/skins/:id` | Mostrar os dados de uma skin |
| `GET /api/skins/:id/ofertas` | Listar as ofertas ativas de uma skin |
| `GET /api/skins/:id/historico` | Mostrar o histórico de vendas de uma skin |
| `POST /api/compras` | Comprar um anúncio (pagamento simulado) |
| `GET /api/inventario` | Listar os itens do usuário |
| `GET /api/anuncios/analise-preco` | Analisar o preço de um item ao anunciar |
| `POST /api/anuncios` | Publicar um anúncio |
| `POST /api/anuncios/:id/cancelar` | Cancelar um anúncio aberto |
| `GET /api/negociacoes` | Listar os anúncios, as vendas e as compras do usuário |
| `POST /api/avaliacoes` | Avaliar o vendedor de uma compra concluída |
| `GET /api/analise` | Carregar os indicadores, gráficos e rankings da Análise de mercado |

## Testes

O comando `npm test` monta o banco em memória, sem internet, e confere as regras de negócio, as operações (compra, anúncio, cancelamento e avaliação), as 34 consultas e os dados de demonstração.

## Publicação

O site roda no Render, configurado pelo [`render.yaml`](render.yaml), com o banco na branch `production` do Neon.
