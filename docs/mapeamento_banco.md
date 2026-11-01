# Mapeamento do banco de dados — VaultGabe

Banco de dados usado pela aplicação: tabelas, regras de negócio, dados de demonstração e as correções feitas sobre o banco desenvolvido em Banco de Dados I.

Os números foram obtidos montando o banco com `database/01_tabelas.sql` a `03_dados.sql` (coluna "03", a base herdada de Banco de Dados I) e a `04_dados_ampliados.sql` (coluna "03 + 04", o banco completo, usado pelo site). Nos dois casos, o `05_verificacao.sql` retornou `OK` em todas as contagens e nas 25 regras de verificação.

---

## 1. Visão geral

O banco tem **20 tabelas**, organizadas em sete áreas:

| Área | Tabelas | Para que serve na aplicação |
|---|---|---|
| **Catálogo** | `categoria_item`, `raridade`, `colecao`, `item_catalogo` | Os modelos de skins (ex.: "AK-47 \| Redline") e suas classificações |
| **Inventário** | `item_instancia`, `equipamento`, `cosmetico`, `consumivel`, `aplicacao_cosmetico` | Os exemplares que cada usuário possui, com float, StatTrak, adesivos aplicados etc. |
| **Usuários** | `usuario` | Os donos, vendedores e compradores |
| **Mercado** | `anuncio`, `venda`, `pagamento`, `nota_fiscal` | Anúncios publicados e vendas realizadas |
| **Trocas** | `troca`, `troca_item` | Trocas de itens entre usuários |
| **Avaliações** | `avaliacao`, `avaliacao_venda`, `avaliacao_troca` | Reputação dos usuários após vendas e trocas |
| **Aberturas** | `abertura_recipiente` | Histórico de caixas e cápsulas abertas |

> **Conceito central:** `item_catalogo` é o **modelo** ("AK-47 | Redline"), e `item_instancia` é um **exemplar** daquele modelo, com dono, float e número de inspeção próprios. Um modelo tem vários exemplares.

As tabelas usadas por cada página estão em [`escopo.md`](escopo.md), seção 5.

---

## 2. Tabelas

**Política de chaves:** toda tabela de entidade tem `id SERIAL` como chave primária, e a chave "natural" do negócio (nome, Steam ID, protocolo...) é mantida como `UNIQUE`. Os subtipos usam a mesma chave do registro pai.

| Tabela | O que guarda | Chave primária | Chave natural (`UNIQUE`) | Chaves estrangeiras | 03 | 03 + 04 |
|---|---|---|---|---|---:|---:|
| `categoria_item` | Categoria do modelo (Rifle, Faca, Caixa...) | `id` | `nome_categoria` | — | 13 | 13 |
| `raridade` | Raridade e sua cor (`#RRGGBB`) | `id` | `nome_raridade` | — | 12 | 12 |
| `colecao` | Coleção oficial e data de lançamento | `id` | `nome_colecao` | — | 12 | 29 |
| `usuario` | Conta do usuário (Steam ID, e-mail, apelido) | `id` | `steam_id`, `email` | — | 12 | 12 |
| `item_catalogo` | Modelo de item: nome, imagem, faixa de float, descrição | `id` | `nome_item` | `categoria_id`, `raridade_id`, `colecao_id` (opcional) | 21 | 80 |
| `item_instancia` | Exemplar de um modelo: dono atual, status, negociável | `id` | `numero_inspecao` | `item_catalogo_id`, `proprietario_id` → `usuario` | 54 | 297 |
| `equipamento` | Subtipo: armas, facas e luvas (float, seed, StatTrak, Souvenir) | `item_instancia_id` | — | `item_instancia_id` | 16 | 192 |
| `cosmetico` | Subtipo: adesivos e chaveiros | `item_instancia_id` | — | `item_instancia_id` | 20 | 56 |
| `consumivel` | Subtipo: caixas, cápsulas, chaves e grafites (lacrado, cargas) | `item_instancia_id` | — | `item_instancia_id` | 18 | 49 |
| `aplicacao_cosmetico` | Cosmético aplicado em um equipamento (posição, rotação, raspagem) | `cosmetico_id` | — | `cosmetico_id`, `equipamento_id` | 7 | 19 |
| `anuncio` | Item colocado à venda: preço, publicação, expiração, status | `id` | (`item_instancia_id`, `criador_id`, `data_publicacao`) | `item_instancia_id`, `criador_id` → `usuario` | 19 | 498 |
| `venda` | Venda gerada por um anúncio | `id` | `protocolo_venda`, `anuncio_id` | `anuncio_id`, `comprador_id` → `usuario` | 12 | 396 |
| `pagamento` | Pagamento da venda (método, valor, status) | `venda_id` | — | `venda_id` | 12 | 396 |
| `nota_fiscal` | Nota fiscal da venda (chave de 44 dígitos) | `id` | `chave`, `venda_id` | `venda_id` | 10 | 394 |
| `troca` | Proposta de troca entre dois usuários | `id` | `protocolo_troca` | `proponente_id`, `destinatario_id` → `usuario` | 10 | 10 |
| `troca_item` | Itens de cada troca e o lado (oferecido ou solicitado) | (`troca_id`, `item_instancia_id`) | — | `troca_id`, `item_instancia_id` | 21 | 21 |
| `avaliacao` | Nota (1 a 5) e comentário de um usuário sobre outro | `id` | `ticket_avaliacao` | `autor_id`, `avaliado_id` → `usuario` | 10 | 158 |
| `avaliacao_venda` | Liga a avaliação a uma venda | `avaliacao_id` | — | `avaliacao_id`, `venda_id` | 5 | 153 |
| `avaliacao_troca` | Liga a avaliação a uma troca | `avaliacao_id` | — | `avaliacao_id`, `troca_id` | 5 | 5 |
| `abertura_recipiente` | Abertura de caixa/cápsula: recipiente, chave e item obtido | `id` | `recipiente_id`, `chave_id`, `item_resultado_id` | `usuario_id`, `recipiente_id`, `chave_id`, `item_resultado_id` | 5 | 5 |

### Restrições de valor e unicidade mais importantes

| Tabela | Regra |
|---|---|
| `raridade` | `cor_hexadecimal` no formato `#RRGGBB` |
| `usuario` | `email` com formato `algo@algo.algo` |
| `item_catalogo` | `float_min` e `float_max` ambos preenchidos ou ambos vazios, dentro de [0, 1] e com `min ≤ max` |
| `equipamento` | `float_value` em [0, 1]; `paint_seed` em [0, 1000]; nunca StatTrak **e** Souvenir ao mesmo tempo |
| `consumivel` | `cargas_restantes ≥ 0`; item lacrado tem pelo menos 1 carga |
| `aplicacao_cosmetico` | `nivel_raspagem` em [0, 100]; `rotacao` em [−360, 360] |
| `anuncio` | `preco > 0`; `data_expiracao > data_publicacao`; **no máximo 1 anúncio aberto (`pendente`/`ativo`) por item** (índice único parcial `anuncio_aberto_por_item_uk`) |
| `venda` / `pagamento` / `nota_fiscal` | valores `> 0`; pagamento pendente sem data, aprovado/recusado com data |
| `troca` | proponente ≠ destinatário; só troca `concluida` tem `data_efetivacao` |
| `avaliacao` | `nota` de 1 a 5; autor ≠ avaliado |
| `abertura_recipiente` | recipiente, chave e resultado são itens diferentes |

Os status são gravados sem acento (`disponivel`, `concluida`...), e a interface os exibe com acento. Um anúncio está **aberto** quando o status é `pendente` ou `ativo`, e **encerrado** quando é `vendido`, `expirado` ou `cancelado`.

---

## 3. Regras de negócio

### 3.1 Triggers (`02_regras.sql`)

O banco **recusa** a operação que viola a regra e devolve uma mensagem de erro, que a aplicação pode exibir ao usuário.

| # | Trigger | Tabela | Quando | O que faz |
|---:|---|---|---|---|
| 1 | `trg_limite_cosmeticos` | `aplicacao_cosmetico` | antes de INSERT/UPDATE | Bloqueia o 7º cosmético em um mesmo equipamento |
| 2 | `trg_vendedor_nao_compra` | `venda` | antes de INSERT/UPDATE | Bloqueia a venda em que o comprador é o próprio criador do anúncio |
| 3 | `trg_aplicar_cosmetico` | `aplicacao_cosmetico` | antes de INSERT | Exige cosmético do mesmo dono da arma, disponível, negociável e sem anúncio aberto; depois o marca como `consumido` e não negociável |
| 4 | `trg_cosmeticos_acompanham_equipamento` | `item_instancia` | depois de mudar o dono | Leva os cosméticos aplicados para o novo dono da arma |
| 5 | `trg_validar_anuncio` | `anuncio` | antes de INSERT/UPDATE | Anúncio aberto só para item **do próprio criador**, `disponivel` e negociável |
| 6 | `trg_transicao_anuncio` | `anuncio` | antes de mudar o status | Ciclo de vida: `pendente → ativo`; `ativo → vendido` só com venda concluída; cancelar ou expirar só sem venda pendente (e expirar só depois do vencimento); `vendido`, `expirado` e `cancelado` são finais |
| 7 | `trg_validar_avaliacao_venda` | `avaliacao_venda` | antes de INSERT/UPDATE | Só venda concluída; autor e avaliado são o comprador e o vendedor; não pode ser anterior à venda; uma avaliação por autor; não pode estar ligada também a uma troca |
| 8 | `trg_validar_avaliacao_troca` | `avaliacao_troca` | antes de INSERT/UPDATE | As mesmas regras do trigger 7, para trocas concluídas |
| — | `trg_registrar_abertura_recipiente` | `abertura_recipiente` | antes de INSERT | Valida recipiente e chave (sem anúncio aberto) e o resultado; marca recipiente e chave como `consumido` |
| — | `trg_proteger_abertura_recipiente` | `abertura_recipiente` | antes de UPDATE/DELETE | Impede alterar ou apagar o histórico de aberturas |

Além dos triggers, o índice `anuncio_aberto_por_item_uk` impede **dois anúncios abertos para o mesmo item**. O `05_verificacao.sql` confere ainda 25 regras sobre os dados (RS-01 a RS-25), como "todo exemplar está em exatamente um subtipo" e "pagamento e nota fiscal com o mesmo valor da venda"; várias delas também são garantidas pelos triggers acima.

### 3.2 Funções, índices e visões

Operações de várias etapas ficam no próprio banco. Cada chamada é atômica: se uma etapa falhar, nada é gravado. Todos os triggers continuam valendo para o que a função grava.

| Função | O que faz | Retorna |
|---|---|---|
| `fn_comprar_anuncio(anuncio, comprador, metodo)` | Confere o anúncio (ativo, não vencido, sem venda) e o item; cria a venda `concluida`, o pagamento `aprovado` e a nota fiscal; marca o anúncio como `vendido`; passa o item e os cosméticos aplicados ao comprador | `venda_id`, `protocolo`, `chave_nota_fiscal` |
| `fn_avaliar_venda(venda, autor, nota, comentario)` | Descobre o avaliado (a outra parte da venda) e grava a avaliação já ligada à venda | ticket (`TKT-AAAA-NNNN`) |
| `fn_expirar_anuncios()` | Marca como `expirado` os anúncios abertos já vencidos, exceto os que têm venda pendente | quantidade expirada |
| `fn_gerar_chave_nfe(numero)` | Gera a chave de 44 dígitos da nota fiscal, com dígito verificador (módulo 11) | chave |
| `fn_desgaste(float)` / `fn_desgaste_nome(float)` | Desgaste a partir do float: `FN` Factory New (< 0,07), `MW` Minimal Wear (< 0,15), `FT` Field-Tested (< 0,38), `WW` Well-Worn (< 0,45), `BS` Battle-Scarred | código / nome |
| `fn_sem_acento(texto)` | Texto em minúsculas e sem acento, para a busca e a ordem alfabética do catálogo (`buscar_catalogo`, `listar_categorias`, `listar_colecoes`) e do inventário (`inventario_usuario`) | texto |
| `fn_media_vendas_comparaveis(item)` | Média das vendas concluídas para a análise de preço: as do mesmo modelo e da mesma versão do item (desgaste, StatTrak e Souvenir) quando são 2 ou mais; senão, ou fora de equipamento, todas as vendas do modelo. A página da skin (`ofertas_do_modelo`) e o Novo anúncio (`analise_preco_anuncio`) usam a mesma conta | `preco_medio` (sem arredondar), `vendas`, `base` (`versao` ou `modelo`) |

- **Numeração sem buracos:** os protocolos (`VND-AAAA-NNNN`) e os tickets (`TKT-AAAA-NNNN`) vêm das sequências `venda_protocolo_seq` e `avaliacao_ticket_seq`, que continuam a partir dos dados de demonstração. O número só é gerado depois que todas as validações passam, então uma compra ou avaliação recusada não pula números.
- **Operações simultâneas:** `fn_comprar_anuncio` trava o anúncio e o item, o trigger 5 trava o item e `fn_avaliar_venda` trava a venda (`FOR UPDATE`): a segunda operação sobre o mesmo anúncio, item ou venda espera a primeira terminar e é validada com os dados já atualizados.
- **Índices novos:** `idx_venda_data` (histórico e estatísticas por período) e `idx_anuncio_ativo_expiracao` (vencimento dos anúncios ativos).
- **Visões de apoio** (em `01_tabelas.sql`), usadas pelas consultas de `database/consultas/`: `vw_ofertas_ativas` (anúncios ativos e não vencidos; a coluna `reservada` marca os que têm venda pendente, que continuam listados mas ficam fora do menor preço e da contagem de ofertas), `vw_vendas_concluidas` (vendas concluídas com item, modelo, vendedor e comprador) e `vw_reputacao` (nota média e número de avaliações por usuário).

---

## 4. Dados de demonstração

O `03_dados.sql` traz a base herdada de Banco de Dados I, usada também pelos testes. O `04_dados_ampliados.sql` acrescenta o volume usado pelas telas e pelos gráficos.

| | 03 | 03 + 04 |
|---|---:|---:|
| Vendas concluídas | 10 | **394**, de novembro/2025 a outubro/2026, com vendas em todos os 12 meses |
| Anúncios ativos | 6 | **80**, vencendo entre abril e setembro de 2027 |
| Anúncios cancelados / expirados | 2 / 1 | 15 / 9 |

- **Todos os 80 modelos têm 3 ou mais vendas**, o que garante dados para o gráfico de preço do Detalhe e para os rankings da Análise.
- **Os preços são simulados** (preço de referência do modelo × desgaste × StatTrak ou Souvenir × tendência mensal × variação de ±7%), e a interface avisa isso.
- **Steam Guard pesa na reputação:** a Steam segura por até 15 dias os itens enviados por contas sem o autenticador móvel. Por isso os vendedores com `steam_guard_ativo = FALSE` (dfontes, pepaa, isizinha e bruninmatador) recebem notas de 2 a 4, com comentários sobre a demora na entrega, escritos mais de 15 dias depois da venda; nesses dados, quem compra deles só anuncia o item depois desse prazo.
- **Linha do tempo de posse coerente:** cada anúncio e cada troca usam um item que pertencia ao participante naquela data, e as revendas vêm depois da compra anterior.
- **Status em aberto de propósito:** a venda `VND-2026-0011` (boleto) fica pendente, para mostrar a oferta reservada, e 3 trocas ficam abertas (2 pendentes e 1 aceita), para mostrar todos os status.

**Usuários indicados para demonstração:**
- Isabela (`isizinha`): usuária padrão e maior compradora (41 compras), com a AK-47 \| Redline com 3 adesivos aplicados.
- Diego (`dfontes`): vendedor sem Steam Guard, com 6 anúncios ativos.
- Larissa (`lari`): revendedora, com 9 anúncios ativos, entre eles a M4A4 \| Howl e a Karambit \| Doppler.

---

## 5. Correções em relação ao BD I

As correções abaixo foram feitas sobre o banco do BD I: as regras ficam em `01_tabelas.sql` e `02_regras.sql`, e os dados em `03_dados.sql` e na seção 11 do `04_dados_ampliados.sql`. Os números de trigger se referem à tabela da seção 3.1, e as regras RS são as do `05_verificacao.sql`.

| Problema | Correção |
|---|---|
| O banco aceitava anúncio de item **de outro usuário**, bloqueado ou consumido | Trigger `trg_validar_anuncio` + regra RS-24 |
| O mesmo item podia ter **dois anúncios abertos** e ser vendido duas vezes | Índice único parcial `anuncio_aberto_por_item_uk` |
| **Cosméticos aplicados** tinham dono diferente da arma (6 de 7) e continuavam negociáveis; havia chaveiro em faca | Triggers 3 e 4 + regra RS-23; as 7 aplicações agora usam cosméticos do próprio dono da arma e só armas de fogo |
| **Três trocas** usavam itens que já eram de outra pessoa na data da proposta (`TRC-2026-0006`, `0009` e `0010`) | Itens e participantes ajustados em `03_dados.sql` |
| A troca aceita `TRC-2026-0008` oferecia uma faca **bloqueada** e pedia uma cápsula que já estava em **venda pendente** | Trocada por Nova ↔ AK-47 (ambas Classified) |
| As regras RS-04 (item da venda concluída com o comprador) e RS-07 (itens da troca concluída com a outra parte) acusariam erro em qualquer **revenda** feita pela aplicação | Passaram a considerar só a transferência mais recente do item |
| Anúncio novo nascia `pendente` e não havia regra para as mudanças de status | A aplicação publica direto como `ativo`; o trigger 6 controla o ciclo de vida |
| Venda concluída não transferia o item, e a compra exigia vários comandos separados | Função `fn_comprar_anuncio`, atômica |
| Anúncio vencido continuava `ativo` | Função `fn_expirar_anuncios`, chamada pela aplicação antes de listar |
| Não havia regra para quem pode avaliar | Triggers 7 e 8, regra RS-25 e função `fn_avaliar_venda` |
| Não havia imagens (`imagem_base` apontava para arquivos `img/*.png` inexistentes) | Cada modelo recebeu o link da imagem oficial (servidor da Steam), obtido no [CSGO-API](https://github.com/ByMykel/CSGO-API); `imagem_base` virou `TEXT`, porque os links passam de 255 caracteres |
| Dois modelos não existiam no jogo | `P90 \| Dry Season` virou a skin real `P90 \| Sand Spray`. A `Capsula de Chaveiros` saiu (no CS2 chaveiros não vêm em cápsula) |
| Raridades diferentes das do jogo | 8 modelos alinhados com o CS2 (ex.: Karambit agora é Covert; Adesivo Crown (Foil) é Exotic) |
| Alguns modelos do 03 estavam em coleções diferentes das do jogo, e dois nomes de coleção eram de caixa/operação (`The Danger Zone Case`, `Operation Bravo`); 5 chaveiros tinham sido obtidos antes de existirem no jogo | Seção 11.1 do 04: coleções e datas de obtenção alinhadas com o CS2 |
| Variantes que não existem no jogo: uma Desert Eagle \| Blaze StatTrak e um AWP \| Asiimov Souvenir | Seção 11.2 do 04: os dois exemplares passam a comuns |
| Preço da Cápsula Ambush (R$ 680,00) cerca de cem vezes o das outras vendas do modelo | Seção 11.3 do 04: R$ 6,80 |
| Cor da raridade Extraordinary diferente da do CS2 (`#ffd700`) | `#eb4b4b`, a cor usada pelo jogo |
| As aberturas davam itens que não saem daqueles recipientes (Caixa Fracture → AK-47 \| Redline; Cápsula Ambush → adesivos de outras cápsulas), e a chave era a do CS:GO, que não abre a caixa | Seção 11.4 do 04: recipientes, chaves e itens obtidos trocados por combinações que existem no jogo |
| Chaves de NF-e do 03 com dígito verificador errado (9 de 10) e uma com o mês errado | Chaves recalculadas no `03_dados.sql` com o mesmo módulo 11 de `fn_gerar_chave_nfe` |
| Nomes, comentários e descrições apareciam sem acento na tela ("Capsula", "negociacao") | Seção 11.5 do 04: acentos gravados nos textos; a busca ignora acentos (`fn_sem_acento`) |
| Poucos dados para estatísticas (no máximo 1 venda por modelo, e 11 dos 21 modelos sem nenhuma) | `04_dados_ampliados.sql` (ver a seção 4 deste documento) |
