-- =====================================================================
-- VAULTGABE - Marketplace de skins de CS2
-- 01 - TABELAS: criacao das tabelas, chaves, restricoes, indices e
--      visoes de apoio as consultas da aplicacao
--
-- ORDEM DE EXECUCAO: 01_tabelas -> 02_regras -> 03_dados -> 04_dados_ampliados -> 05_verificacao
-- ATENCAO: este script APAGA todas as tabelas (e os dados) antes de
--          recria-las. Nunca execute em um banco com dados que importam.
--
-- Autores: Lucas Ienne, Lucas Silveira, Vinicius de Paula,
--          Gabriel Trevisoli
--
-- SGBD: PostgreSQL 18
-- Origem: Modelo Relacional (nivel logico)
--
-- POLITICA DE CHAVES
--   Cada tabela de entidade recebe id SERIAL PRIMARY KEY, e a chave
--   natural do modelo relacional vira UNIQUE NOT NULL (chave secundaria):
--   as FKs ficam com um so inteiro sem perder a unicidade original.
--   Especializacoes e entidades fracas 1:1 mantem a PK compartilhada, que
--   ja e um inteiro (o id da tabela pai).
--
-- CONVENCAO DE DADOS
--   Valores de status sao gravados SEM ACENTO, para evitar problemas de
--   encoding. Os dominios estao nos CHECKs abaixo (notas do MER).
-- =====================================================================

-- Limpeza (ordem inversa das dependencias) para permitir reexecucao.
DROP TABLE IF EXISTS abertura_recipiente CASCADE;
DROP TABLE IF EXISTS avaliacao_troca      CASCADE;
DROP TABLE IF EXISTS avaliacao_venda      CASCADE;
DROP TABLE IF EXISTS avaliacao            CASCADE;
DROP TABLE IF EXISTS troca_item           CASCADE;
DROP TABLE IF EXISTS troca                CASCADE;
DROP TABLE IF EXISTS nota_fiscal          CASCADE;
DROP TABLE IF EXISTS pagamento            CASCADE;
DROP TABLE IF EXISTS venda                CASCADE;
DROP TABLE IF EXISTS anuncio              CASCADE;
DROP TABLE IF EXISTS aplicacao_cosmetico  CASCADE;
DROP TABLE IF EXISTS consumivel           CASCADE;
DROP TABLE IF EXISTS equipamento          CASCADE;
DROP TABLE IF EXISTS cosmetico            CASCADE;
DROP TABLE IF EXISTS item_instancia       CASCADE;
DROP TABLE IF EXISTS item_catalogo        CASCADE;
DROP TABLE IF EXISTS usuario              CASCADE;
DROP TABLE IF EXISTS colecao              CASCADE;
DROP TABLE IF EXISTS raridade             CASCADE;
DROP TABLE IF EXISTS categoria_item       CASCADE;


-- ---------------------------------------------------------------------
-- 1. CATEGORIA_ITEM   (MER: entidade CATEGORIA)
--    ENQUADRA: ITEM(0,N) - CATEGORIA(1,1)
-- ---------------------------------------------------------------------
CREATE TABLE categoria_item (
    id              SERIAL,
    nome_categoria  VARCHAR(80)  NOT NULL,

    CONSTRAINT categoria_item_pk PRIMARY KEY (id),

    CONSTRAINT categoria_item_nome_uk UNIQUE (nome_categoria)
);

COMMENT ON TABLE categoria_item IS
    'Categoria do modelo de item (Rifle, Pistola, Faca...). Chave natural: nome_categoria.';


-- ---------------------------------------------------------------------
-- 2. RARIDADE
--    CLASSIFICA: ITEM(0,N) - RARIDADE(1,1)
-- ---------------------------------------------------------------------
CREATE TABLE raridade (
    id               SERIAL,
    nome_raridade    VARCHAR(80)  NOT NULL,
    cor_hexadecimal  VARCHAR(7)   NOT NULL,

    CONSTRAINT raridade_pk PRIMARY KEY (id),

    CONSTRAINT raridade_nome_uk  UNIQUE (nome_raridade),
    CONSTRAINT raridade_cor_ck   CHECK  (cor_hexadecimal ~ '^#[0-9A-Fa-f]{6}$')
);

COMMENT ON COLUMN raridade.cor_hexadecimal IS
    'Cor da raridade no formato #RRGGBB (MER: atributo COR).';


-- ---------------------------------------------------------------------
-- 3. COLECAO
--    PERTENCE: ITEM(1,N) - COLECAO(0,1)
--    O lado (0,1) vira a FK ANULAVEL item_catalogo.colecao_id.
--    O minimo 1 do lado ITEM ("uma colecao agrupa >=1 item") nao cabe
--    em FK: e a regra RS-18 de 05_verificacao.sql.
-- ---------------------------------------------------------------------
CREATE TABLE colecao (
    id               SERIAL,
    nome_colecao     VARCHAR(120)  NOT NULL,
    data_lancamento  DATE,

    CONSTRAINT colecao_pk PRIMARY KEY (id),

    CONSTRAINT colecao_nome_uk UNIQUE (nome_colecao)
);


-- ---------------------------------------------------------------------
-- 4. USUARIO
--    POSSUI: ITEM(0,N) - USUARIO(1,1)
-- ---------------------------------------------------------------------
CREATE TABLE usuario (
    id                 SERIAL,
    steam_id           VARCHAR(40)   NOT NULL,
    nome               VARCHAR(120)  NOT NULL,
    email              VARCHAR(180)  NOT NULL,
    apelido            VARCHAR(80),
    data_cadastro      DATE          NOT NULL DEFAULT CURRENT_DATE,
    steam_guard_ativo  BOOLEAN       NOT NULL DEFAULT FALSE,

    CONSTRAINT usuario_pk PRIMARY KEY (id),

    CONSTRAINT usuario_steam_id_uk UNIQUE (steam_id),
    CONSTRAINT usuario_email_uk    UNIQUE (email),
    CONSTRAINT usuario_email_ck    CHECK  (email LIKE '_%@_%._%')
);

COMMENT ON COLUMN usuario.steam_id IS
    'Chave natural do usuario (MER: identificador STEAM_ID).';


-- ---------------------------------------------------------------------
-- 5. ITEM_CATALOGO   (modelo/skin)
--    A entidade conceitual ITEM foi decomposta em ITEM_CATALOGO (o modelo)
--    e ITEM_INSTANCIA (o exemplar) para eliminar redundancia.
--
--    float_min/float_max: faixa de desgaste, so para modelos de
--    EQUIPAMENTO; em cosmeticos e consumiveis ficam NULL.
-- ---------------------------------------------------------------------
CREATE TABLE item_catalogo (
    id            SERIAL,
    nome_item     VARCHAR(150)   NOT NULL,
    categoria_id  INTEGER        NOT NULL,
    raridade_id   INTEGER        NOT NULL,
    colecao_id    INTEGER        NULL,
    imagem_base   TEXT,          -- link da imagem oficial (passa de 255 caracteres)
    float_min     NUMERIC(10,8),
    float_max     NUMERIC(10,8),
    descricao     TEXT,

    CONSTRAINT item_catalogo_pk PRIMARY KEY (id),

    CONSTRAINT item_catalogo_nome_uk       UNIQUE (nome_item),

    CONSTRAINT item_catalogo_categoria_fk  FOREIGN KEY (categoria_id)
        REFERENCES categoria_item (id),
    CONSTRAINT item_catalogo_raridade_fk   FOREIGN KEY (raridade_id)
        REFERENCES raridade (id),
    CONSTRAINT item_catalogo_colecao_fk    FOREIGN KEY (colecao_id)
        REFERENCES colecao (id),

    -- Ambos NULL ou ambos preenchidos, dentro de [0,1] e ordenados.
    -- Um CHECK "float_min <= float_max" isolado retornaria NULL (e
    -- portanto passaria) quando so um dos dois fosse NULL.
    CONSTRAINT item_catalogo_float_ck CHECK (
        (float_min IS NULL AND float_max IS NULL)
        OR (
            float_min IS NOT NULL AND float_max IS NOT NULL
            AND float_min BETWEEN 0 AND 1
            AND float_max BETWEEN 0 AND 1
            AND float_min <= float_max
        )
    )
);


-- ---------------------------------------------------------------------
-- 6. ITEM_INSTANCIA   (exemplar fisico possuido por um usuario)
--    proprietario_id e o dono ATUAL: muda quando uma venda e concluida
--    ou uma troca e efetivada (RS-04 e RS-07 em 05_verificacao.sql).
-- ---------------------------------------------------------------------
CREATE TABLE item_instancia (
    id                SERIAL,
    numero_inspecao   VARCHAR(80)  NOT NULL,
    item_catalogo_id  INTEGER      NOT NULL,
    proprietario_id   INTEGER      NOT NULL,
    tradable_flag     BOOLEAN      NOT NULL DEFAULT TRUE,
    data_obtencao     DATE,
    status_item       VARCHAR(30)  NOT NULL DEFAULT 'disponivel',

    CONSTRAINT item_instancia_pk PRIMARY KEY (id),

    CONSTRAINT item_instancia_inspecao_uk UNIQUE (numero_inspecao),

    CONSTRAINT item_instancia_catalogo_fk FOREIGN KEY (item_catalogo_id)
        REFERENCES item_catalogo (id),
    CONSTRAINT item_instancia_dono_fk     FOREIGN KEY (proprietario_id)
        REFERENCES usuario (id),

    CONSTRAINT item_instancia_status_ck   CHECK
        (status_item IN ('disponivel', 'bloqueado', 'consumido'))
);

COMMENT ON COLUMN item_instancia.tradable_flag IS
    'Equivale ao atributo NEGOCIAVEL do MER (divergencia de nome em relacao ao MER).';
COMMENT ON COLUMN item_instancia.proprietario_id IS
    'Dono ATUAL. Muda apos venda concluida / troca efetivada.';


-- ---------------------------------------------------------------------
-- 7-9. ESPECIALIZACAO DE ITEM_INSTANCIA  (TOTAL e DISJUNTA)
--
--   Toda item_instancia deve estar em EXATAMENTE UM entre cosmetico,
--   equipamento e consumivel. A PK compartilhada so impede repeticao
--   dentro de cada subtipo; NAO garante totalidade nem disjuncao.
--   Ver RS-01 e RS-02 em 05_verificacao.sql.
-- ---------------------------------------------------------------------
CREATE TABLE cosmetico (
    item_instancia_id  INTEGER,
    tipo_cosmetico     VARCHAR(80)  NOT NULL,
    arte_visual        VARCHAR(255),

    CONSTRAINT cosmetico_pk PRIMARY KEY (item_instancia_id),

    CONSTRAINT cosmetico_instancia_fk FOREIGN KEY (item_instancia_id)
        REFERENCES item_instancia (id) ON DELETE CASCADE,
    CONSTRAINT cosmetico_tipo_ck      CHECK
        (tipo_cosmetico IN ('adesivo', 'chaveiro'))
);

CREATE TABLE equipamento (
    item_instancia_id  INTEGER,
    float_value        NUMERIC(10,8)  NOT NULL,
    paint_seed         INTEGER,
    stattrak_flag      BOOLEAN        NOT NULL DEFAULT FALSE,
    souvenir_flag      BOOLEAN        NOT NULL DEFAULT FALSE,

    CONSTRAINT equipamento_pk PRIMARY KEY (item_instancia_id),

    CONSTRAINT equipamento_instancia_fk FOREIGN KEY (item_instancia_id)
        REFERENCES item_instancia (id) ON DELETE CASCADE,

    -- Mesmo tipo e faixa [0,1] de float_min/float_max do catalogo.
    CONSTRAINT equipamento_float_ck     CHECK (float_value BETWEEN 0 AND 1),
    CONSTRAINT equipamento_paint_ck     CHECK (paint_seed IS NULL OR paint_seed BETWEEN 0 AND 1000),

    -- No CS2 uma skin nunca e StatTrak e Souvenir ao mesmo tempo.
    CONSTRAINT equipamento_st_sv_ck     CHECK (NOT (stattrak_flag AND souvenir_flag))
);

CREATE TABLE consumivel (
    item_instancia_id  INTEGER,
    tipo_consumivel    VARCHAR(80)  NOT NULL,
    lacrado            BOOLEAN      NOT NULL DEFAULT TRUE,
    cargas_restantes   INTEGER      NOT NULL,

    CONSTRAINT consumivel_pk PRIMARY KEY (item_instancia_id),

    CONSTRAINT consumivel_instancia_fk FOREIGN KEY (item_instancia_id)
        REFERENCES item_instancia (id) ON DELETE CASCADE,
    CONSTRAINT consumivel_tipo_ck      CHECK
        (tipo_consumivel IN ('caixa', 'capsula', 'chave', 'grafite')),
    CONSTRAINT consumivel_cargas_ck    CHECK (cargas_restantes >= 0),
    -- Coerencia: item lacrado nao teve cargas gastas.
    CONSTRAINT consumivel_lacrado_ck   CHECK (NOT lacrado OR cargas_restantes > 0)
);


-- ---------------------------------------------------------------------
-- EXTRA DE BAIXO NIVEL: ABERTURA_RECIPIENTE
--
-- Registra aberturas ja realizadas: caixa usa chave; capsula e aberta
-- diretamente. O MER trata a abertura como operacao do inventario, nao
-- como entidade; esta tabela guarda o evento ocorrido, nao a logica de
-- sorteio.
-- ---------------------------------------------------------------------
CREATE TABLE abertura_recipiente (
    id                 SERIAL,
    usuario_id         INTEGER      NOT NULL,
    recipiente_id      INTEGER      NOT NULL,
    chave_id           INTEGER,
    item_resultado_id  INTEGER      NOT NULL,
    data_abertura      TIMESTAMP    NOT NULL,

    CONSTRAINT abertura_recipiente_pk PRIMARY KEY (id),

    -- Um recipiente, uma chave e um resultado pertencem a uma unica abertura.
    CONSTRAINT abertura_recipiente_recipiente_uk UNIQUE (recipiente_id),
    CONSTRAINT abertura_recipiente_chave_uk      UNIQUE (chave_id),
    CONSTRAINT abertura_recipiente_resultado_uk  UNIQUE (item_resultado_id),

    CONSTRAINT abertura_recipiente_usuario_fk FOREIGN KEY (usuario_id)
        REFERENCES usuario (id),
    CONSTRAINT abertura_recipiente_recipiente_fk FOREIGN KEY (recipiente_id)
        REFERENCES consumivel (item_instancia_id),
    CONSTRAINT abertura_recipiente_chave_fk FOREIGN KEY (chave_id)
        REFERENCES consumivel (item_instancia_id),
    CONSTRAINT abertura_recipiente_resultado_fk FOREIGN KEY (item_resultado_id)
        REFERENCES item_instancia (id),

    CONSTRAINT abertura_recipiente_itens_ck CHECK (
        recipiente_id <> item_resultado_id
        AND (chave_id IS NULL OR chave_id <> recipiente_id)
        AND (chave_id IS NULL OR chave_id <> item_resultado_id)
    )
);


-- ---------------------------------------------------------------------
-- 10. APLICACAO_COSMETICO   (MER: relacionamento APLICA, com atributos)
--     APLICA: COSMETICO(0,6) - EQUIPAMENTO(0,1)
--
--     PK = cosmetico_id: um cosmetico vai em no maximo um equipamento.
--     O limite de 6 por equipamento nao cabe em constraint simples:
--     trigger 1 (02_regras.sql) e RS-03 (05_verificacao.sql).
--
--     Aplicar um cosmetico o INCORPORA ao equipamento (como no CS2): mesmo
--     dono, passa a 'consumido' e acompanha o equipamento quando ele muda
--     de dono. Ver triggers 3 e 4 (02_regras.sql) e RS-23.
-- ---------------------------------------------------------------------
CREATE TABLE aplicacao_cosmetico (
    cosmetico_id    INTEGER,
    equipamento_id  INTEGER       NOT NULL,
    coord_x         NUMERIC(8,3)  NOT NULL,
    coord_y         NUMERIC(8,3)  NOT NULL,
    rotacao         NUMERIC(8,3)  NOT NULL,
    nivel_raspagem  NUMERIC(5,2),

    CONSTRAINT aplicacao_cosmetico_pk PRIMARY KEY (cosmetico_id),

    CONSTRAINT aplicacao_cosmetico_fk   FOREIGN KEY (cosmetico_id)
        REFERENCES cosmetico (item_instancia_id) ON DELETE CASCADE,
    CONSTRAINT aplicacao_equipamento_fk FOREIGN KEY (equipamento_id)
        REFERENCES equipamento (item_instancia_id) ON DELETE CASCADE,

    CONSTRAINT aplicacao_raspagem_ck    CHECK (nivel_raspagem IS NULL OR nivel_raspagem BETWEEN 0 AND 100),
    CONSTRAINT aplicacao_rotacao_ck     CHECK (rotacao BETWEEN -360 AND 360)
);

COMMENT ON COLUMN aplicacao_cosmetico.nivel_raspagem IS
    'Equivale a NIVEL_DESGASTE do MER (divergencia de nome em relacao ao MER).';


-- ---------------------------------------------------------------------
-- 11. ANUNCIO   (MER: ENTIDADE FRACA)
--     Identificada por CRIA + OFERECE + discriminador DATA_PUBLICACAO.
--     CRIA:    USUARIO(1,1) - ANUNCIO(0,N)
--     OFERECE: ITEM(1,1)    - ANUNCIO(0,N)
--
--     A PK composta de 3 colunas do modelo relacional vira chave
--     secundaria (UNIQUE) e a PK passa a ser um SERIAL.
-- ---------------------------------------------------------------------
CREATE TABLE anuncio (
    id                 SERIAL,
    item_instancia_id  INTEGER        NOT NULL,
    criador_id         INTEGER        NOT NULL,
    data_publicacao    TIMESTAMP      NOT NULL,
    preco              NUMERIC(12,2)  NOT NULL,
    data_expiracao     TIMESTAMP      NOT NULL,
    status_anuncio     VARCHAR(30)    NOT NULL DEFAULT 'pendente',

    CONSTRAINT anuncio_pk PRIMARY KEY (id),

    CONSTRAINT anuncio_identificador_uk UNIQUE (item_instancia_id, criador_id, data_publicacao),

    CONSTRAINT anuncio_item_fk    FOREIGN KEY (item_instancia_id)
        REFERENCES item_instancia (id),
    CONSTRAINT anuncio_criador_fk FOREIGN KEY (criador_id)
        REFERENCES usuario (id),

    CONSTRAINT anuncio_status_ck  CHECK
        (status_anuncio IN ('pendente', 'ativo', 'vendido', 'expirado', 'cancelado')),
    CONSTRAINT anuncio_preco_ck   CHECK (preco > 0),
    CONSTRAINT anuncio_datas_ck   CHECK (data_expiracao > data_publicacao)
);

COMMENT ON CONSTRAINT anuncio_identificador_uk ON anuncio IS
    'Identificador original da entidade fraca, preservado como chave secundaria.';

-- No maximo UM anuncio aberto ('pendente' ou 'ativo') por item, para o
-- mesmo item nao ser vendido duas vezes; anuncios encerrados sao
-- historico. Dono, disponivel e negociavel: trigger 5 em 02_regras.sql.
CREATE UNIQUE INDEX anuncio_aberto_por_item_uk
    ON anuncio (item_instancia_id)
    WHERE status_anuncio IN ('pendente', 'ativo');


-- ---------------------------------------------------------------------
-- 12. VENDA
--     GERA:   ANUNCIO(1,1) - VENDA(0,1)
--     COMPRA: USUARIO(1,1) - VENDA(0,N)
--
--     Com o SERIAL, a FK de 3 colunas para ANUNCIO (numero_inspecao +
--     steam_id_criador + data_publicacao) vira UMA coluna: anuncio_id.
--
--     Cardinalidades do MER:
--       NOT NULL -> GERA (1,1) no lado ANUNCIO: toda venda tem 1 anuncio
--       UNIQUE   -> GERA (0,1) no lado VENDA:   1 anuncio gera <=1 venda
-- ---------------------------------------------------------------------
CREATE TABLE venda (
    id               SERIAL,
    protocolo_venda  VARCHAR(80)    NOT NULL,
    anuncio_id       INTEGER        NOT NULL,
    comprador_id     INTEGER        NOT NULL,
    data_venda       TIMESTAMP      NOT NULL,
    valor_venda      NUMERIC(12,2)  NOT NULL,
    status_venda     VARCHAR(30)    NOT NULL DEFAULT 'pendente',

    CONSTRAINT venda_pk PRIMARY KEY (id),

    CONSTRAINT venda_protocolo_uk UNIQUE (protocolo_venda),
    CONSTRAINT venda_anuncio_uk   UNIQUE (anuncio_id),

    CONSTRAINT venda_anuncio_fk   FOREIGN KEY (anuncio_id)
        REFERENCES anuncio (id),
    CONSTRAINT venda_comprador_fk FOREIGN KEY (comprador_id)
        REFERENCES usuario (id),

    CONSTRAINT venda_status_ck    CHECK
        (status_venda IN ('pendente', 'concluida', 'cancelada')),
    CONSTRAINT venda_valor_ck     CHECK (valor_venda > 0)
);

COMMENT ON COLUMN venda.protocolo_venda IS
    'Numero de referencia exibido ao cliente (MER: PROTOCOLO). Chave natural.';

-- Protocolos VND-AAAA-NNNN das vendas criadas pela aplicacao
-- (fn_comprar_anuncio). OWNED BY: e apagada com a tabela e reiniciada
-- pelo TRUNCATE ... RESTART IDENTITY de 03_dados.sql.
CREATE SEQUENCE venda_protocolo_seq OWNED BY venda.protocolo_venda;


-- ---------------------------------------------------------------------
-- 13. PAGAMENTO   (MER: ENTIDADE FRACA, identificada so pela VENDA)
--     REGISTRA: VENDA(1,1) - PAGAMENTO(1,1)
--
--     A PK compartilhada garante no maximo um pagamento por venda, mas
--     NAO que toda venda tenha um (RS-06 em 05_verificacao.sql).
-- ---------------------------------------------------------------------
CREATE TABLE pagamento (
    venda_id          INTEGER,
    metodo_pagamento  VARCHAR(40)    NOT NULL,
    valor             NUMERIC(12,2)  NOT NULL,
    data_pagamento    TIMESTAMP      NULL,
    status_pagamento  VARCHAR(30)    NOT NULL DEFAULT 'pendente',

    CONSTRAINT pagamento_pk PRIMARY KEY (venda_id),

    CONSTRAINT pagamento_venda_fk  FOREIGN KEY (venda_id)
        REFERENCES venda (id) ON DELETE CASCADE,

    CONSTRAINT pagamento_status_ck CHECK
        (status_pagamento IN ('pendente', 'aprovado', 'recusado')),
    CONSTRAINT pagamento_metodo_ck CHECK
        (metodo_pagamento IN ('pix', 'cartao_credito', 'cartao_debito', 'boleto', 'saldo_steam')),
    CONSTRAINT pagamento_valor_ck  CHECK (valor > 0),

    -- Coerencia status x data: so pagamento pendente pode estar sem data.
    CONSTRAINT pagamento_data_ck   CHECK (
        (status_pagamento = 'pendente' AND data_pagamento IS NULL)
        OR (status_pagamento IN ('aprovado', 'recusado') AND data_pagamento IS NOT NULL)
    )
);


-- ---------------------------------------------------------------------
-- 14. NOTA_FISCAL
--     EMITE: VENDA(1,1) - NOTA_FISCAL(0,1)
--     venda_id UNIQUE NOT NULL: a NF pertence a 1 venda, e a venda emite
--     no maximo 1 NF (podendo nao emitir).
-- ---------------------------------------------------------------------
CREATE TABLE nota_fiscal (
    id            SERIAL,
    chave         VARCHAR(44)    NOT NULL,
    venda_id      INTEGER        NOT NULL,
    data_emissao  TIMESTAMP      NOT NULL,
    valor_total   NUMERIC(12,2)  NOT NULL,

    CONSTRAINT nota_fiscal_pk PRIMARY KEY (id),

    CONSTRAINT nota_fiscal_chave_uk UNIQUE (chave),
    CONSTRAINT nota_fiscal_venda_uk UNIQUE (venda_id),

    CONSTRAINT nota_fiscal_venda_fk FOREIGN KEY (venda_id)
        REFERENCES venda (id),

    -- Chave de acesso NF-e: exatamente 44 digitos numericos.
    CONSTRAINT nota_fiscal_chave_ck CHECK (chave ~ '^[0-9]{44}$'),
    CONSTRAINT nota_fiscal_valor_ck CHECK (valor_total > 0)
);


-- ---------------------------------------------------------------------
-- 15. TROCA
--     PROPOE:       USUARIO(1,1) - TROCA(0,N)
--     DESTINATARIO: USUARIO(1,1) - TROCA(0,N)
-- ---------------------------------------------------------------------
CREATE TABLE troca (
    id                SERIAL,
    protocolo_troca   VARCHAR(80)  NOT NULL,
    proponente_id     INTEGER      NOT NULL,
    destinatario_id   INTEGER      NOT NULL,
    data_proposta     TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    data_efetivacao   TIMESTAMP    NULL,
    status_troca      VARCHAR(30)  NOT NULL DEFAULT 'pendente',
    laudo_troca       TEXT,
    observacao        TEXT,

    CONSTRAINT troca_pk PRIMARY KEY (id),

    CONSTRAINT troca_protocolo_uk    UNIQUE (protocolo_troca),

    CONSTRAINT troca_proponente_fk   FOREIGN KEY (proponente_id)
        REFERENCES usuario (id),
    CONSTRAINT troca_destinatario_fk FOREIGN KEY (destinatario_id)
        REFERENCES usuario (id),

    CONSTRAINT troca_status_ck       CHECK
        (status_troca IN ('pendente', 'aceita', 'recusada', 'cancelada', 'concluida')),
    CONSTRAINT troca_partes_ck       CHECK (proponente_id <> destinatario_id),
    -- Coerencia status x data: so troca concluida tem data de efetivacao.
    CONSTRAINT troca_efetivacao_ck   CHECK (
        (status_troca = 'concluida' AND data_efetivacao IS NOT NULL
             AND data_efetivacao >= data_proposta)
        OR (status_troca <> 'concluida' AND data_efetivacao IS NULL)
    )
);


-- ---------------------------------------------------------------------
-- 16. TROCA_ITEM   (MER: relacionamento ENVOLVE, N:N com atributo LADO)
--     ENVOLVE: TROCA(0,N) - ITEM(1,N)
--
--     PK composta pelas duas FKs (mapeamento classico de N:N). Nenhuma
--     tabela referencia esta chave, entao nao ha chave composta
--     propagada para um SERIAL resolver.
--
--     O minimo "1 oferecido + 1 solicitado" por troca nao cabe em
--     constraint simples: ver RS-08 em 05_verificacao.sql.
-- ---------------------------------------------------------------------
CREATE TABLE troca_item (
    troca_id           INTEGER      NOT NULL,
    item_instancia_id  INTEGER      NOT NULL,
    lado_troca         VARCHAR(30)  NOT NULL,

    CONSTRAINT troca_item_pk   PRIMARY KEY (troca_id, item_instancia_id),

    CONSTRAINT troca_item_troca_fk FOREIGN KEY (troca_id)
        REFERENCES troca (id) ON DELETE CASCADE,
    CONSTRAINT troca_item_item_fk  FOREIGN KEY (item_instancia_id)
        REFERENCES item_instancia (id),

    CONSTRAINT troca_item_lado_ck  CHECK
        (lado_troca IN ('oferecido', 'solicitado'))
);


-- ---------------------------------------------------------------------
-- 17. AVALIACAO
--     ESCREVE: USUARIO(1,1) - AVALIACAO(0,N)   [autor]
--     RECEBE:  USUARIO(1,1) - AVALIACAO(0,N)   [avaliado]
-- ---------------------------------------------------------------------
CREATE TABLE avaliacao (
    id                SERIAL,
    ticket_avaliacao  VARCHAR(80)  NOT NULL,
    autor_id          INTEGER      NOT NULL,
    avaliado_id       INTEGER      NOT NULL,
    data_avaliacao    TIMESTAMP    NOT NULL,
    comentario        TEXT,
    nota              INTEGER      NOT NULL,

    CONSTRAINT avaliacao_pk PRIMARY KEY (id),

    CONSTRAINT avaliacao_ticket_uk   UNIQUE (ticket_avaliacao),

    CONSTRAINT avaliacao_autor_fk    FOREIGN KEY (autor_id)
        REFERENCES usuario (id),
    CONSTRAINT avaliacao_avaliado_fk FOREIGN KEY (avaliado_id)
        REFERENCES usuario (id),

    CONSTRAINT avaliacao_nota_ck     CHECK (nota BETWEEN 1 AND 5),
    CONSTRAINT avaliacao_partes_ck   CHECK (autor_id <> avaliado_id)
);

-- Tickets TKT-AAAA-NNNN das avaliacoes criadas pela aplicacao
-- (fn_avaliar_venda).
CREATE SEQUENCE avaliacao_ticket_seq OWNED BY avaliacao.ticket_avaliacao;


-- ---------------------------------------------------------------------
-- 18-19. SUBTIPOS DE AVALIACAO  (padrao class-table inheritance)
--     AVALIA_VENDA: VENDA(0,1) - AVALIACAO(0,N)
--     AVALIA_TROCA: TROCA(0,1) - AVALIACAO(0,N)
--
--     PK compartilhada = lado (0,1): uma avaliacao avalia no maximo uma
--     venda e no maximo uma troca. FK sem UNIQUE = lado (0,N): uma
--     venda/troca pode receber varias avaliacoes (uma de cada parte).
--     O XOR (EXATAMENTE um subtipo) nao cabe em constraint simples: ver
--     RS-09 em 05_verificacao.sql.
-- ---------------------------------------------------------------------
CREATE TABLE avaliacao_venda (
    avaliacao_id  INTEGER,
    venda_id      INTEGER  NOT NULL,

    CONSTRAINT avaliacao_venda_pk PRIMARY KEY (avaliacao_id),

    CONSTRAINT avaliacao_venda_aval_fk  FOREIGN KEY (avaliacao_id)
        REFERENCES avaliacao (id) ON DELETE CASCADE,
    CONSTRAINT avaliacao_venda_venda_fk FOREIGN KEY (venda_id)
        REFERENCES venda (id)
);

CREATE TABLE avaliacao_troca (
    avaliacao_id  INTEGER,
    troca_id      INTEGER  NOT NULL,

    CONSTRAINT avaliacao_troca_pk PRIMARY KEY (avaliacao_id),

    CONSTRAINT avaliacao_troca_aval_fk  FOREIGN KEY (avaliacao_id)
        REFERENCES avaliacao (id) ON DELETE CASCADE,
    CONSTRAINT avaliacao_troca_troca_fk FOREIGN KEY (troca_id)
        REFERENCES troca (id)
);


-- ---------------------------------------------------------------------
-- INDICES DE APOIO
-- FKs mais usadas em JOIN e agrupamento (PKs e UNIQUEs ja tem indice).
-- ---------------------------------------------------------------------
CREATE INDEX idx_item_instancia_dono      ON item_instancia (proprietario_id);
CREATE INDEX idx_item_instancia_catalogo  ON item_instancia (item_catalogo_id);
CREATE INDEX idx_item_catalogo_categoria  ON item_catalogo (categoria_id);
CREATE INDEX idx_item_catalogo_raridade   ON item_catalogo (raridade_id);
CREATE INDEX idx_anuncio_criador          ON anuncio (criador_id);
CREATE INDEX idx_anuncio_item             ON anuncio (item_instancia_id);
CREATE INDEX idx_anuncio_status           ON anuncio (status_anuncio);
CREATE INDEX idx_venda_comprador          ON venda (comprador_id);
CREATE INDEX idx_venda_status             ON venda (status_venda);
CREATE INDEX idx_troca_proponente         ON troca (proponente_id);
CREATE INDEX idx_troca_destinatario       ON troca (destinatario_id);
CREATE INDEX idx_avaliacao_avaliado       ON avaliacao (avaliado_id);
CREATE INDEX idx_avaliacao_venda_venda    ON avaliacao_venda (venda_id);
CREATE INDEX idx_avaliacao_troca_troca    ON avaliacao_troca (troca_id);

-- Historico de precos e estatisticas por periodo.
CREATE INDEX idx_venda_data               ON venda (data_venda);
-- Vencimento dos anuncios ativos (fn_expirar_anuncios e listagens).
CREATE INDEX idx_anuncio_ativo_expiracao  ON anuncio (data_expiracao)
    WHERE status_anuncio = 'ativo';


-- ---------------------------------------------------------------------
-- VISOES DE APOIO
-- Juncoes repetidas em database/consultas/. O DROP TABLE ... CASCADE do
-- inicio tambem as remove, e elas sao recriadas a cada execucao.
-- ---------------------------------------------------------------------

-- Cada venda CONCLUIDA com o item, o modelo, o vendedor e o comprador.
-- Base do historico de precos, das estatisticas e da reputacao.
CREATE OR REPLACE VIEW vw_vendas_concluidas AS
SELECT v.id               AS venda_id,
       v.protocolo_venda  AS protocolo,
       v.data_venda,
       v.valor_venda      AS valor,
       a.id               AS anuncio_id,
       a.criador_id       AS vendedor_id,
       v.comprador_id,
       i.id               AS item_id,
       i.item_catalogo_id AS modelo_id,
       ic.categoria_id,
       ic.raridade_id
  FROM venda v
  JOIN anuncio a        ON a.id  = v.anuncio_id
  JOIN item_instancia i ON i.id  = a.item_instancia_id
  JOIN item_catalogo ic ON ic.id = i.item_catalogo_id
 WHERE v.status_venda = 'concluida';

-- Anuncios ATIVOS e ainda nao vencidos (as ofertas a venda agora).
-- reservada: o anuncio tem venda pendente. A oferta continua listada,
-- mas nao pode ser comprada, entao fica fora do menor preco e da
-- contagem de ofertas a venda.
CREATE OR REPLACE VIEW vw_ofertas_ativas AS
SELECT a.id               AS anuncio_id,
       a.preco,
       a.data_publicacao,
       a.data_expiracao,
       a.criador_id       AS vendedor_id,
       i.id               AS item_id,
       i.numero_inspecao,
       i.item_catalogo_id AS modelo_id,
       EXISTS (SELECT 1 FROM venda v
                WHERE v.anuncio_id = a.id
                  AND v.status_venda = 'pendente') AS reservada
  FROM anuncio a
  JOIN item_instancia i ON i.id = a.item_instancia_id
 WHERE a.status_anuncio = 'ativo'
   AND a.data_expiracao > now();

-- Reputacao de cada usuario avaliado: nota media e numero de avaliacoes.
CREATE OR REPLACE VIEW vw_reputacao AS
SELECT avaliado_id         AS usuario_id,
       ROUND(AVG(nota), 1) AS nota_media,
       COUNT(*)            AS avaliacoes
  FROM avaliacao
 GROUP BY avaliado_id;
