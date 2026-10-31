# Consultas da aplicação

Todo o SQL que a aplicação executa fica aqui, **um arquivo por página**. O backend (Node.js) carrega estes arquivos e chama cada consulta pelo nome, sem SQL disperso pelo código.

| Arquivo | Página | Consultas |
|---|---|---|
| `comum.sql` | Todas (e `/api/saude`) | `listar_usuarios`, `saude_banco`, `expirar_anuncios` |
| `catalogo.sql` | Catálogo | `listar_categorias`, `listar_raridades`, `listar_colecoes`, `buscar_catalogo` |
| `detalhe_skin.sql` | Detalhe da skin + janela Comprar | `detalhe_modelo`, `ofertas_do_modelo`, `historico_vendas_modelo`, `precos_por_mes_modelo`, `comprar_anuncio` |
| `inventario.sql` | Inventário + janela Novo anúncio | `resumo_inventario`, `inventario_usuario`, `analise_preco_anuncio`, `publicar_anuncio` |
| `negociacoes.sql` | Negociações + janela Avaliar vendedor | `contar_negociacoes`, `anuncios_a_venda`, `anuncios_vendidos`, `compras_do_usuario`, `anuncios_encerrados`, `cancelar_anuncio`, `avaliar_vendedor` |
| `analise.sql` | Análise de mercado | `indicadores_gerais`, `vendas_por_mes`, `preco_medio_por_raridade`, `volume_por_categoria`, `mais_negociadas`, `maiores_variacoes`, `vendedores_mais_bem_avaliados` |
| `perfil.sql` | Perfil do usuário | `perfil_usuario`, `anuncios_ativos_do_usuario`, `avaliacoes_recebidas`, `trocas_do_usuario` |

São **34 consultas**: 29 de leitura e 5 que gravam dados (`expirar_anuncios`, `publicar_anuncio`, `cancelar_anuncio`, `comprar_anuncio` e `avaliar_vendedor`).

## Formato

Cada consulta começa com uma linha `-- name:`, seguida de comentários que explicam para que ela serve e quais são os parâmetros:

```sql
-- name: resumo_inventario
-- Linha de resumo do topo da pagina e numero de itens de cada aba.
--   $1 usuario  INT
SELECT ...
```

- **Parâmetros** são `$1`, `$2`, ... e sempre têm o tipo explícito (`$1::INT`). Os valores vão separados do SQL, o que impede injeção de SQL.
- **Filtros opcionais** recebem `NULL` quando estão desligados (`$4::INT IS NULL OR ...`). Assim, uma única consulta atende a qualquer combinação de filtros.
- **Erros de regra** (ex.: "o usuário não é dono do item") vêm dos triggers e funções de `02_regras.sql`. A aplicação mostra a mensagem ao usuário.

## Apoio no banco

Junções e cálculos repetidos ficam no próprio banco:

| Objeto | Arquivo | Para quê |
|---|---|---|
| `vw_ofertas_ativas` | `01_tabelas.sql` | Anúncios ativos e não vencidos, com o item, o modelo e `reservada` (venda pendente: fica fora do menor preço e da contagem de ofertas) |
| `vw_vendas_concluidas` | `01_tabelas.sql` | Vendas concluídas com item, modelo, vendedor e comprador |
| `vw_reputacao` | `01_tabelas.sql` | Nota média e número de avaliações de cada usuário |
| `fn_desgaste` / `fn_desgaste_nome` | `02_regras.sql` | Desgaste a partir do float (`FN` Factory New … `BS` Battle-Scarred) |
| `fn_media_vendas_comparaveis` | `02_regras.sql` | Média das vendas da mesma versão do item (ou de todo o modelo, se houver menos de 2), usada na análise de preço do Detalhe e do Novo anúncio |
| `fn_sem_acento` | `02_regras.sql` | Texto em minúsculas e sem acento, para a busca e a ordem alfabética do Catálogo, dos filtros e do Inventário ("capsula" encontra "Cápsula") |
