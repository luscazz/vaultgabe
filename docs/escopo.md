# Escopo da aplicação — VaultGabe

Telas, funcionalidades, operações no banco e prioridades da aplicação.

---

## 1. Resumo

O **VaultGabe** é um marketplace de skins de Counter-Strike 2 construído sobre o banco de dados PostgreSQL modelado em Banco de Dados I (ver [`mapeamento_banco.md`](mapeamento_banco.md)).

O usuário escolhe um perfil de demonstração e, a partir dele:
- **pesquisa** skins com filtros combinados (categoria, raridade, coleção, preço, desgaste, StatTrak);
- **consulta** o detalhe de cada skin, com os anúncios ativos, o histórico de vendas e a reputação dos vendedores;
- **gerencia o inventário** e vê o que pode ser anunciado;
- **publica e cancela anúncios** e **compra** itens, com o pagamento simulado.

As regras de negócio (só anunciar item próprio e disponível, não comprar o próprio item, um anúncio aberto por item...) são garantidas **pelo próprio banco**, com triggers e restrições.

Os dados de demonstração têm 80 modelos reais do CS2, com as imagens oficiais, e 394 vendas simuladas distribuídas em 12 meses.

### Como cada requisito do enunciado é atendido

| Requisito | Como o VaultGabe atende |
|---|---|
| Aplicação web integrada a um banco na nuvem | Node.js + Express no Render, conectado ao PostgreSQL no Neon |
| Exibir dados de buscas com junções e condições, não só `SELECT *` | Catálogo, detalhe, inventário e análise juntam de 4 a 10 tabelas, com filtros, agregações e cálculo de desgaste |
| Motivo lógico e real para existir | Comprar e vender skins com transparência de preço e reputação |
| Buscas complexas de forma simplificada | Filtros combináveis em formulário, em vez de SQL |
| Inserir dados | Publicar anúncio (INSERT), cancelar anúncio (UPDATE), comprar (INSERT de venda, pagamento e nota fiscal + UPDATE do anúncio e do dono do item) e avaliar o vendedor (INSERT de avaliação) |
| Hospedada em servidor | Render (aplicação) + Neon (banco) |
| Um dos dois temas | Buscas complexas de forma simplificada e inserção de dados. Os gráficos (Análise de mercado e gráfico de preço do Detalhe) são um extra |

---

## 2. Telas

São **6 páginas** (cada uma com seu endereço) e **3 janelas** (abrem sobre uma página, sem tirar o usuário dela). O menu do topo leva ao Catálogo, ao Inventário, às Negociações e à Análise; o seletor "Entrar como" tem o link "Meu perfil". No Catálogo, cada skin abre o Detalhe, onde é feita a compra e de onde se chega ao perfil do vendedor.

### Páginas

| # | Página | Endereço | Para que serve | Prioridade |
|---:|---|---|---|---|
| 1 | Catálogo | `/` | Pesquisar skins e ofertas com filtros e ver o preço "a partir de" | **Essencial** |
| 2 | Detalhe da skin | `/skin/:id` | Comparar as ofertas de um modelo, o histórico de preços e a reputação dos vendedores | **Essencial** |
| 3 | Inventário | `/inventario` | Ver os itens do usuário e anunciar | **Essencial** |
| 4 | Negociações | `/negociacoes` | Acompanhar e cancelar anúncios; ver vendas e compras | **Essencial** |
| 5 | Análise de mercado | `/analise` | Indicadores, gráficos e rankings do mercado | Complementar |
| 6 | Perfil do usuário | `/usuario/:id` | Reputação, avaliações e histórico de um usuário | Complementar |

### Janelas

| # | Janela | Abre em | Para que serve | Prioridade |
|---|---|---|---|---|
| A | Novo anúncio | Inventário | Publicar um item à venda, com análise de preço | **Essencial** |
| B | Comprar | Detalhe da skin | Comprar uma oferta com pagamento simulado | **Essencial** |
| C | Avaliar vendedor | Negociações › Comprados | Dar nota e comentário depois da compra | Complementar |

---

## 3. Elementos comuns a todas as telas

- **Seletor "Entrar como":** lista os 12 usuários como "apelido (Nome)". A escolha fica salva no navegador e define de quem são o inventário, os anúncios e as compras. Substitui o login, já que o banco não tem senha. Padrão: Isabela (`isizinha`). O mesmo menu tem o link "Meu perfil".
- **Valores:** sempre em R$ (`R$ 1.950,00`). Datas no formato `26/10/2026`.
- **Status com acento na tela:** `disponivel` → "Disponível", `concluida` → "Concluída" etc.
- **Raridade com a cor do banco** (`raridade.cor_hexadecimal`) na borda do card e no rótulo.
- **Desgaste calculado a partir do float:** Factory New (< 0,07), Minimal Wear (< 0,15), Field-Tested (< 0,38), Well-Worn (< 0,45), Battle-Scarred (≥ 0,45).
- **Erros do banco viram mensagem para o usuário.** Por exemplo: "Você não é dono deste item" ou "Este item já tem um anúncio aberto".
- **Estados de tela:** carregando; lista vazia com orientação (ex.: "Nenhuma skin encontrada. Tente outra busca ou limpe os filtros."); erro de conexão com o banco.
- **Rodapé:** aviso de que usuários, preços, vendas e avaliações são dados de demonstração, créditos das imagens (Valve) e do CSGO-API, e a identificação do projeto acadêmico.

---

## 4. Telas em detalhe

### 4.1 Catálogo — `/` (essencial)

**Objetivo:** encontrar uma skin rapidamente e ver por quanto ela está à venda.

- **Busca:** por nome (parcial, sem diferenciar maiúsculas nem acentos).
- **Filtros do modelo:** categoria (várias), raridade (várias), coleção, faixa de preço, "só com anúncio ativo".
- **Filtros da oferta** (valem para armas, facas e luvas): desgaste, StatTrak, Souvenir e "com adesivos". Mostram só os modelos com pelo menos uma oferta ativa com essas características, e o "a partir de" passa a considerar só essas ofertas.
- **Ordenação:** menor preço, maior preço, mais ofertas, mais vendidas, nome.
- **Cada card:** imagem, nome, raridade (cor), categoria, menor preço ativo, número de ofertas.
- **Ofertas reservadas:** um anúncio ativo com venda pendente não pode ser comprado. Ele continua listado no Detalhe, marcado como reservado, mas não entra no menor preço, no número de ofertas nem nos filtros do Catálogo.
- **Ação:** clicar no card abre o Detalhe **com os mesmos filtros de oferta já aplicados** (ex.: `/skin/12?desgaste=FN&stattrak=1`).

**Banco:** `item_catalogo` + `categoria_item` + `raridade` + `colecao` (LEFT JOIN) + `item_instancia` + `anuncio` + `equipamento` + `aplicacao_cosmetico` + `venda` (vendas concluídas, para "mais vendidas"), com `GROUP BY` por modelo. O menor preço e o número de ofertas são agregados (`MIN` e `COUNT`, numa CTE sobre `vw_ofertas_ativas` já filtrada) só sobre anúncios ativos, não vencidos, sem venda pendente e que atendem aos filtros da oferta. O desgaste sai das faixas do float, e "com adesivos" usa `EXISTS` em `aplicacao_cosmetico`.

### 4.2 Detalhe da skin — `/skin/:id` (essencial)

**Objetivo:** decidir a compra comparando ofertas, preço histórico e reputação do vendedor.

- **Cabeçalho:** imagem, nome, raridade, categoria, coleção, faixa de float, descrição; indicadores de menor preço ativo, preço médio vendido (todas as versões do modelo), número de vendas e ofertas à venda.
- **Anúncios ativos:** float, desgaste, StatTrak/Souvenir, adesivos e chaveiros aplicados, vendedor com nota média, preço e um selo de **análise de preço** (ex.: "12,0% abaixo da média"). O selo compara com a média das vendas comparáveis e mostra a base usada. Ofertas com venda pendente aparecem como "Reservado", sem o botão Comprar. Filtros por desgaste, StatTrak e adesivos, vindos do Catálogo ou escolhidos aqui; ordenação por preço ou float.
- **Botão "Comprar"** em cada anúncio. Não aparece nos anúncios do próprio usuário selecionado.
- **Histórico de vendas concluídas:** data, preço, float, de quem para quem, mais um gráfico simples de preço ao longo do tempo (extra).
- **Ações:** comprar; clicar no vendedor abre o Perfil.
- **Colunas conforme o tipo do item:** armas, facas e luvas mostram float, desgaste, seed, StatTrak/Souvenir e cosméticos aplicados; adesivos e chaveiros mostram o tipo; caixas, cápsulas, chaves e grafites mostram lacrado e cargas. A faixa de float do cabeçalho só aparece para equipamentos.
- **Sem ofertas:** a página mostra "Nenhuma oferta no momento" e mantém o histórico de vendas.

**Banco:** `anuncio` + `item_instancia` + `equipamento`/`cosmetico`/`consumivel` (conforme o tipo) + `aplicacao_cosmetico` (+ `item_catalogo` dos cosméticos) + `usuario` + média de `avaliacao` do vendedor. O histórico usa `venda` + `anuncio` + `item_instancia` + `usuario` (vendedor e comprador). O desgaste vem de `fn_desgaste`. A média de cada oferta vem de `fn_media_vendas_comparaveis` (ver seção 6).

### 4.3 Comprar — janela sobre o Detalhe (essencial)

- **Resumo da oferta:** versão do item (desgaste, StatTrak™ ou Souvenir) e float, vendedor com nota média e número de avaliações (e um aviso quando ele não tem Steam Guard) e preço.
- **Pagamento:** Pix, cartão de crédito, cartão de débito, boleto ou saldo Steam, simulado e aprovado na hora.
- **Ao confirmar:** numa única transação, o banco cria a **venda** (`concluida`, com protocolo novo), o **pagamento** (`aprovado`) e a **nota fiscal**; marca o anúncio como `vendido`; e passa o item ao comprador. Os adesivos aplicados vão junto, pelo trigger `trg_cosmeticos_acompanham_equipamento`.
- **Resultado:** a janela mostra "Compra concluída", o protocolo da venda (ex.: VND-2026-0397) e a chave da nota fiscal, com links para o Inventário e para Negociações › Comprados.
- **Bloqueios do banco:** comprar o próprio item, anúncio já vendido ou vencido.

**Banco:** função `fn_comprar_anuncio` (ver seção 6).

### 4.4 Inventário — `/inventario` (essencial)

**Objetivo:** ver o que o usuário tem e colocar itens à venda.

- **Resumo:** total de itens, negociáveis, anunciados e prontos para anunciar.
- **Abas por tipo:** Todos, equipamentos, cosméticos e consumíveis (os três subtipos do banco), cada uma com o número de itens. A caixa "Só os que posso anunciar" deixa na lista, e nos números das abas, só os itens que podem ser anunciados.
- **Cada item:** imagem, nome, raridade, float e desgaste (equipamentos), StatTrak/Souvenir, adesivos aplicados, cargas (consumíveis) e um **status calculado**:
  - **Disponível** → mostra o botão "Anunciar";
  - **Anunciado (R$ X)** → link para o anúncio;
  - **Bloqueado**, **Aplicado em [arma]** ou **Consumido** → sem ação.
- **Origem e uso em aberturas** (complementar): a caixa aberta mostra "Aberta em 20/06/2026 → AK-47 | Redline"; a chave, "Usada em 20/06/2026"; e o item obtido, "Obtido ao abrir Caixa Phoenix".

**Banco:** `item_instancia` + `item_catalogo` + `raridade` + `categoria_item` + `LEFT JOIN` nos três subtipos + `aplicacao_cosmetico` + `anuncio` aberto + `abertura_recipiente`. Um item pode ser anunciado se estiver `disponivel`, for negociável e não tiver anúncio aberto. O tipo e "só os que posso anunciar" são filtrados no SQL (`inventario_usuario`), e `resumo_inventario` traz os indicadores do topo e o número de itens de cada aba.

### 4.5 Novo anúncio — janela sobre o Inventário (essencial)

- **Campos:** preço (maior que zero) e validade (7, 14 ou 30 dias).
- **Análise de preço** (complementar): menor preço entre as outras ofertas do mesmo modelo que podem ser compradas, média das vendas comparáveis e quanto o preço digitado está acima ou abaixo dela. A tela indica a base usada.
- **Publicar:** o anúncio é gravado **direto como `ativo`**. Como não há perfil de administrador para aprovar anúncios, o status `pendente` não é usado.

**Banco:** `INSERT INTO anuncio`. O trigger `trg_validar_anuncio` e o índice `anuncio_aberto_por_item_uk` garantem dono certo, item disponível e um anúncio aberto por item. A análise de preço usa `vw_ofertas_ativas` e a função `fn_media_vendas_comparaveis` (ver seção 6).

### 4.6 Negociações — `/negociacoes` (essencial)

**Objetivo:** acompanhar tudo o que o usuário vendeu, está vendendo e comprou.

- **À venda:** anúncios ativos, com o botão cancelar (pede confirmação). Não é permitido cancelar anúncio com venda pendente.
- **Vendidos:** comprador, data, valor e protocolo da venda.
- **Comprados:** item, vendedor, data, valor, método de pagamento e chave da nota fiscal, com o botão "Avaliar vendedor" (complementar).
- **Encerrados:** anúncios cancelados e expirados.
- **Em todas as abas,** armas, facas e luvas mostram o desgaste e o float; os outros itens, o número de inspeção.
- **"Anunciar um item"** leva ao Inventário, já filtrado nos itens negociáveis.

**Banco:** `anuncio` + `item_instancia` + `item_catalogo` + `equipamento` (desgaste e float) + `venda` + `usuario` (comprador); compras: `venda` + `pagamento` + `nota_fiscal` + `anuncio` + `usuario` (vendedor) + `avaliacao`/`avaliacao_venda` (se já avaliou). Cancelar: `UPDATE anuncio SET status_anuncio = 'cancelado'`.

#### Janela Avaliar vendedor (complementar)

- Nota de 1 a 5 e comentário opcional, disponível nas compras concluídas que o usuário ainda não avaliou.
- Depois de enviada, a nota passa a contar na reputação do vendedor (Detalhe e Perfil).

**Banco:** função `fn_avaliar_venda`, que grava `avaliacao` + `avaliacao_venda` de uma vez. O trigger `trg_validar_avaliacao_venda` garante uma avaliação por participante em cada venda.

### 4.7 Análise de mercado — `/analise` (complementar)

- **Indicadores:** volume vendido (R$), número de vendas, ticket médio e ofertas à venda.
- **Gráficos:** volume vendido por mês (com o número de vendas), ticket médio por mês, preço médio por raridade e volume por categoria.
- **Rankings:** skins mais negociadas; maiores variações de preço; vendedores mais bem avaliados.
- **Filtros:** período e categoria. Os atalhos de período ("Últimos 30 dias", "Últimos 90 dias", "Últimos 12 meses") terminam na última venda concluída quando ela é anterior a hoje, e a página avisa isso; senão, terminam hoje.
- **Avisos:** dados simulados para demonstração e, quando o filtro tem poucas vendas, amostra pequena.

**Banco:** agregações (`SUM`, `AVG`, `COUNT`, `date_trunc('month', ...)`) sobre `venda` + `anuncio` + `item_instancia` + `item_catalogo` + `raridade` + `categoria_item`; o ranking de vendedores usa `avaliacao` + `avaliacao_venda` + `usuario`.

### 4.8 Perfil do usuário — `/usuario/:id` (complementar)

- **Cabeçalho:** apelido, membro desde, Steam Guard ativo, nota média e número de avaliações.
- **Números:** vendas, compras e trocas concluídas.
- **Seções:** anúncios ativos do usuário; avaliações recebidas (autor, nota, comentário, se foi venda ou troca); histórico de trocas (somente consulta).

**Banco:** `usuario` + `avaliacao` + `avaliacao_venda`/`avaliacao_troca` + `venda` + `troca` + `troca_item`; os anúncios ativos e os itens das trocas usam `anuncio` + `item_instancia` + `item_catalogo` + `raridade` + `equipamento`.

---

## 5. Operações no banco

O SQL de cada operação está em [`database/consultas/`](../database/consultas/README.md), com um arquivo por página.

| Operação | Tipo | Tabelas envolvidas | Tela |
|---|---|---|---|
| Listar usuários para o seletor | Consulta | `usuario` | Todas |
| Pesquisar catálogo com filtros | Consulta + agregação | `item_catalogo`, `categoria_item`, `raridade`, `colecao`, `item_instancia`, `anuncio`, `equipamento`, `aplicacao_cosmetico`, `venda` | Catálogo |
| Detalhe do modelo | Consulta + agregação | `item_catalogo`, `categoria_item`, `raridade`, `colecao`, `cosmetico`, `venda`, `anuncio`, `item_instancia` | Detalhe |
| Anúncios ativos de um modelo | Consulta | `anuncio`, `item_instancia`, `equipamento`, `cosmetico`, `consumivel`, `aplicacao_cosmetico`, `item_catalogo`, `usuario`, `avaliacao` | Detalhe |
| Histórico de vendas de um modelo | Consulta | `venda`, `anuncio`, `item_instancia`, `equipamento`, `usuario` (×2) | Detalhe |
| Inventário do usuário | Consulta | `item_instancia`, `item_catalogo`, `categoria_item`, `raridade`, `equipamento`, `cosmetico`, `consumivel`, `aplicacao_cosmetico`, `anuncio`, `abertura_recipiente` | Inventário |
| **Publicar anúncio** | **Inserção** | `anuncio` (validado por trigger e índice) | Novo anúncio |
| Anúncios, vendas e compras do usuário | Consulta | `anuncio`, `venda`, `pagamento`, `nota_fiscal`, `item_instancia`, `item_catalogo`, `equipamento`, `usuario`, `avaliacao`, `avaliacao_venda` | Negociações |
| **Cancelar anúncio** | **Atualização** | `anuncio` | Negociações |
| **Expirar anúncios vencidos** | **Atualização** (`fn_expirar_anuncios`) | `anuncio`, `venda` | Todas, antes de listar anúncios |
| **Comprar** | **Inserção + atualização** (transação) | `venda`, `pagamento`, `nota_fiscal`, `anuncio`, `item_instancia` | Comprar |
| Análise de preço | Consulta + agregação | `anuncio`, `venda`, `item_instancia`, `equipamento` | Novo anúncio, Detalhe |
| Indicadores e rankings | Consulta + agregação | `venda`, `anuncio`, `item_instancia`, `item_catalogo`, `raridade`, `categoria_item`, `avaliacao`, `avaliacao_venda`, `usuario` | Análise |
| Perfil e reputação | Consulta + agregação | `usuario`, `avaliacao`, `avaliacao_venda`, `avaliacao_troca`, `venda`, `troca`, `troca_item`, `anuncio`, `item_instancia`, `item_catalogo`, `raridade`, `equipamento` | Perfil |
| **Avaliar vendedor** | **Inserção** (transação) | `avaliacao`, `avaliacao_venda` | Negociações › Comprados |

Com essas operações, **as 20 tabelas do banco são usadas pela aplicação**.

---

## 6. Alterações no banco feitas para a aplicação

Estão nos próprios scripts de `database/` e são conferidas pelos testes. Detalhes em [`mapeamento_banco.md`](mapeamento_banco.md), seção 3.

| # | Alteração | Por quê |
|---:|---|---|
| 1 | Função `fn_comprar_anuncio(anuncio, comprador, metodo)` | Faz a compra inteira numa transação: confere se o anúncio está ativo e não vencido, cria venda, pagamento e nota fiscal, marca o anúncio como vendido e transfere o item |
| 2 | Sequências do protocolo de venda (`VND-AAAA-NNNN`) e do ticket de avaliação (`TKT-AAAA-NNNN`) e geração da chave da nota fiscal (44 dígitos) | Necessário para a compra e a avaliação |
| 3 | Regra de cancelamento (trigger `trg_transicao_anuncio`): não cancelar anúncio com venda pendente | Evita cancelar um negócio em andamento |
| 4 | Função `fn_expirar_anuncios()` | Marca como `expirado` os anúncios abertos já vencidos, exceto os que têm venda pendente. A API a executa antes de listar |
| 5 | Regra de avaliação (triggers `trg_validar_avaliacao_venda` e `trg_validar_avaliacao_troca` + `fn_avaliar_venda`): só quem participou de uma venda concluída avalia, uma vez por venda | Necessário para "Avaliar vendedor" |
| 6 | `imagem_base` como `TEXT` | Os links das imagens oficiais passam de 255 caracteres |
| 7 | Índices `idx_venda_data` e `idx_anuncio_ativo_expiracao` | Desempenho do histórico, das estatísticas e da expiração dos anúncios |
| 8 | Função `fn_media_vendas_comparaveis(item)` | Média da análise de preço: vendas da mesma versão do item (desgaste, StatTrak e Souvenir) quando há 2 ou mais, senão todo o modelo |
| 9 | Visões `vw_ofertas_ativas` (com a coluna `reservada`), `vw_vendas_concluidas` e `vw_reputacao`; funções `fn_desgaste`, `fn_desgaste_nome` e `fn_sem_acento` | Junções e cálculos repetidos ficam no banco, e a busca do catálogo ignora acentos |

---

## 7. Prioridades

| Nível | O que entra |
|---|---|
| **Essencial** (atende o enunciado) | Seletor de usuário · Catálogo com busca, filtros e ordenação · Detalhe da skin · Inventário · Publicar e cancelar anúncio · Negociações (anúncios, vendas e compras) · Compra simulada · Publicação no Render + Neon |
| **Complementar** (além do exigido pelo enunciado) | Análise de mercado · Análise de preço no anúncio e nas ofertas · Perfil com reputação · Avaliar vendedor após a compra · Origem e uso de aberturas no Inventário |
| **Fora do escopo** | Login com senha · Pagamento real · Criar trocas (só consulta, no Perfil) · Abrir caixas (só consulta, no Inventário) · Integração com a Steam · Painel de administrador (o banco não tem esse papel) |
