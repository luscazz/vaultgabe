-- =====================================================================
-- VAULTGABE
-- 02 - REGRAS: funcoes e triggers das regras de negocio
--
-- Regras que envolvem mais de uma linha ou tabela precisam de trigger.
-- Execute depois de 01_tabelas.sql e ANTES de 03_dados.sql, para os
-- triggers ja validarem os dados inseridos.
-- No fim ficam as FUNCOES que a aplicacao chama (comprar, avaliar,
-- expirar anuncios). Os DROP TRIGGER permitem reexecutar o arquivo.
-- =====================================================================


-- ---------------------------------------------------------------------
-- TRIGGER 1 - RS-03: no maximo 6 cosmeticos por equipamento
--
-- Cardinalidade APLICA = COSMETICO(0,6) - EQUIPAMENTO(0,1). O lado (0,1)
-- ja vem da PK de aplicacao_cosmetico; o (0,6) precisa CONTAR linhas, o
-- que um CHECK nao faz.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_limite_cosmeticos_por_equipamento()
RETURNS TRIGGER AS $$
DECLARE
    v_qtd INTEGER;
BEGIN
    SELECT COUNT(*) INTO v_qtd
      FROM aplicacao_cosmetico
     WHERE equipamento_id = NEW.equipamento_id
       AND cosmetico_id  <> COALESCE(NEW.cosmetico_id, -1);

    IF v_qtd >= 6 THEN
        RAISE EXCEPTION
            'Limite excedido: o equipamento % ja possui 6 cosmeticos aplicados (cardinalidade (0,6) do MER).',
            NEW.equipamento_id;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_limite_cosmeticos ON aplicacao_cosmetico;
CREATE TRIGGER trg_limite_cosmeticos
    BEFORE INSERT OR UPDATE ON aplicacao_cosmetico
    FOR EACH ROW
    EXECUTE FUNCTION fn_limite_cosmeticos_por_equipamento();


-- ---------------------------------------------------------------------
-- TRIGGER 2 - RS-05: o vendedor nao pode comprar o proprio item
--
-- Nao cabe em CHECK: comprador_id esta em VENDA e criador_id em ANUNCIO.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_vendedor_nao_compra_proprio_item()
RETURNS TRIGGER AS $$
DECLARE
    v_criador_id INTEGER;
BEGIN
    SELECT criador_id INTO v_criador_id
      FROM anuncio
     WHERE id = NEW.anuncio_id;

    IF v_criador_id = NEW.comprador_id THEN
        RAISE EXCEPTION
            'Operacao invalida: o usuario % criou o anuncio % e nao pode comprar o proprio item.',
            NEW.comprador_id, NEW.anuncio_id;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_vendedor_nao_compra ON venda;
CREATE TRIGGER trg_vendedor_nao_compra
    BEFORE INSERT OR UPDATE ON venda
    FOR EACH ROW
    EXECUTE FUNCTION fn_vendedor_nao_compra_proprio_item();


-- ---------------------------------------------------------------------
-- TRIGGER 3 - RS-23: aplicar um cosmetico o incorpora ao equipamento
--
-- No CS2, um adesivo/chaveiro aplicado passa a fazer parte da arma.
-- O cosmetico precisa ser do MESMO dono do equipamento, estar
-- disponivel, negociavel e sem anuncio aberto; depois fica 'consumido'
-- e nao negociavel.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_aplicar_cosmetico()
RETURNS TRIGGER AS $$
DECLARE
    v_dono_cosmetico    INTEGER;
    v_status_cosmetico  VARCHAR(30);
    v_tradable          BOOLEAN;
    v_dono_equipamento  INTEGER;
BEGIN
    SELECT proprietario_id, status_item, tradable_flag
      INTO v_dono_cosmetico, v_status_cosmetico, v_tradable
      FROM item_instancia
     WHERE id = NEW.cosmetico_id;

    SELECT proprietario_id INTO v_dono_equipamento
      FROM item_instancia
     WHERE id = NEW.equipamento_id;

    IF v_dono_cosmetico <> v_dono_equipamento THEN
        RAISE EXCEPTION
            'O cosmetico % e o equipamento % pertencem a usuarios diferentes.',
            NEW.cosmetico_id, NEW.equipamento_id;
    END IF;

    IF v_status_cosmetico <> 'disponivel' OR NOT v_tradable THEN
        RAISE EXCEPTION 'O cosmetico % nao esta disponivel para aplicacao.',
            NEW.cosmetico_id;
    END IF;

    IF EXISTS (SELECT 1 FROM anuncio
                WHERE item_instancia_id = NEW.cosmetico_id
                  AND status_anuncio IN ('pendente', 'ativo')) THEN
        RAISE EXCEPTION 'O cosmetico % tem anuncio aberto e nao pode ser aplicado.',
            NEW.cosmetico_id;
    END IF;

    UPDATE item_instancia
       SET status_item = 'consumido', tradable_flag = FALSE
     WHERE id = NEW.cosmetico_id;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_aplicar_cosmetico ON aplicacao_cosmetico;
CREATE TRIGGER trg_aplicar_cosmetico
    BEFORE INSERT ON aplicacao_cosmetico
    FOR EACH ROW
    EXECUTE FUNCTION fn_aplicar_cosmetico();


-- ---------------------------------------------------------------------
-- TRIGGER 4 - RS-23: cosmeticos aplicados acompanham o equipamento
--
-- Quando o equipamento muda de dono (venda concluida ou troca), os
-- cosmeticos aplicados nele passam para o novo dono junto com ele.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_cosmeticos_acompanham_equipamento()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE item_instancia
       SET proprietario_id = NEW.proprietario_id
     WHERE id IN (SELECT cosmetico_id
                    FROM aplicacao_cosmetico
                   WHERE equipamento_id = NEW.id)
       AND proprietario_id <> NEW.proprietario_id;

    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_cosmeticos_acompanham_equipamento ON item_instancia;
CREATE TRIGGER trg_cosmeticos_acompanham_equipamento
    AFTER UPDATE OF proprietario_id ON item_instancia
    FOR EACH ROW
    WHEN (OLD.proprietario_id IS DISTINCT FROM NEW.proprietario_id)
    EXECUTE FUNCTION fn_cosmeticos_acompanham_equipamento();


-- ---------------------------------------------------------------------
-- TRIGGER 5 - RS-17 e RS-24: so se anuncia item proprio e negociavel
--
-- So para anuncio ABERTO ('pendente' ou 'ativo'); encerrados sao
-- historico. O limite de UM anuncio aberto por item fica no indice
-- anuncio_aberto_por_item_uk (01_tabelas.sql).
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_validar_anuncio()
RETURNS TRIGGER AS $$
DECLARE
    v_dono      INTEGER;
    v_status    VARCHAR(30);
    v_tradable  BOOLEAN;
BEGIN
    IF NEW.status_anuncio NOT IN ('pendente', 'ativo') THEN
        RETURN NEW;
    END IF;

    -- FOR UPDATE: se o item esta sendo vendido agora (fn_comprar_anuncio),
    -- espera a compra terminar e confere o dono ja atualizado.
    SELECT proprietario_id, status_item, tradable_flag
      INTO v_dono, v_status, v_tradable
      FROM item_instancia
     WHERE id = NEW.item_instancia_id
       FOR UPDATE;

    IF v_dono <> NEW.criador_id THEN
        RAISE EXCEPTION
            'O usuario % nao e dono do item % e nao pode anuncia-lo.',
            NEW.criador_id, NEW.item_instancia_id;
    END IF;

    IF v_status <> 'disponivel' OR NOT v_tradable THEN
        RAISE EXCEPTION 'O item % nao esta disponivel para negociacao.',
            NEW.item_instancia_id;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_validar_anuncio ON anuncio;
CREATE TRIGGER trg_validar_anuncio
    BEFORE INSERT OR UPDATE ON anuncio
    FOR EACH ROW
    EXECUTE FUNCTION fn_validar_anuncio();


-- ---------------------------------------------------------------------
-- TRIGGER 6 - Ciclo de vida do anuncio (inclui a RS-10)
--
-- Mudancas de status permitidas:
--   pendente -> ativo
--   ativo    -> vendido     so se ja existe venda CONCLUIDA do anuncio
--   pendente/ativo -> cancelado   so sem venda pendente
--   pendente/ativo -> expirado    so sem venda pendente e ja vencido
-- vendido, expirado e cancelado sao status FINAIS.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_transicao_anuncio()
RETURNS TRIGGER AS $$
BEGIN
    IF OLD.status_anuncio IN ('vendido', 'expirado', 'cancelado') THEN
        RAISE EXCEPTION
            'O anuncio % ja esta encerrado (%) e nao pode mudar de status.',
            OLD.id, OLD.status_anuncio;
    END IF;

    IF NEW.status_anuncio = 'pendente' THEN
        RAISE EXCEPTION 'O anuncio % nao pode voltar para pendente.', OLD.id;
    END IF;

    IF NEW.status_anuncio = 'vendido' THEN
        IF OLD.status_anuncio <> 'ativo' THEN
            RAISE EXCEPTION 'So um anuncio ativo pode ser vendido.';
        END IF;
        IF NOT EXISTS (SELECT 1 FROM venda
                        WHERE anuncio_id = NEW.id
                          AND status_venda = 'concluida') THEN
            RAISE EXCEPTION
                'O anuncio % so pode ser marcado como vendido depois de uma venda concluida.',
                NEW.id;
        END IF;

    ELSIF NEW.status_anuncio IN ('cancelado', 'expirado') THEN
        IF EXISTS (SELECT 1 FROM venda
                    WHERE anuncio_id = NEW.id
                      AND status_venda = 'pendente') THEN
            RAISE EXCEPTION
                'O anuncio % tem uma venda pendente e nao pode ser encerrado.',
                NEW.id;
        END IF;
        IF NEW.status_anuncio = 'expirado' AND NEW.data_expiracao > now() THEN
            RAISE EXCEPTION 'O anuncio % ainda nao venceu.', NEW.id;
        END IF;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_transicao_anuncio ON anuncio;
CREATE TRIGGER trg_transicao_anuncio
    BEFORE UPDATE OF status_anuncio ON anuncio
    FOR EACH ROW
    WHEN (OLD.status_anuncio IS DISTINCT FROM NEW.status_anuncio)
    EXECUTE FUNCTION fn_transicao_anuncio();


-- ---------------------------------------------------------------------
-- TRIGGER 7 - RS-25: avaliacao de VENDA
--
-- So se avalia venda CONCLUIDA; autor e avaliado sao o comprador e o
-- vendedor (em qualquer direcao); a avaliacao nao e anterior a venda;
-- cada participante avalia a mesma venda uma unica vez; e a avaliacao
-- nao pode estar ligada tambem a uma troca (parte do XOR da RS-09).
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_validar_avaliacao_venda()
RETURNS TRIGGER AS $$
DECLARE
    v_autor      INTEGER;
    v_avaliado   INTEGER;
    v_data_aval  TIMESTAMP;
    v_comprador  INTEGER;
    v_vendedor   INTEGER;
    v_status     VARCHAR(30);
    v_data_venda TIMESTAMP;
BEGIN
    SELECT autor_id, avaliado_id, data_avaliacao
      INTO v_autor, v_avaliado, v_data_aval
      FROM avaliacao
     WHERE id = NEW.avaliacao_id;

    SELECT v.comprador_id, a.criador_id, v.status_venda, v.data_venda
      INTO v_comprador, v_vendedor, v_status, v_data_venda
      FROM venda v
      JOIN anuncio a ON a.id = v.anuncio_id
     WHERE v.id = NEW.venda_id;

    IF v_status <> 'concluida' THEN
        RAISE EXCEPTION 'So e possivel avaliar uma venda concluida.';
    END IF;

    IF NOT ((v_autor = v_comprador AND v_avaliado = v_vendedor)
            OR (v_autor = v_vendedor AND v_avaliado = v_comprador)) THEN
        RAISE EXCEPTION
            'A avaliacao % deve ser entre o comprador e o vendedor da venda %.',
            NEW.avaliacao_id, NEW.venda_id;
    END IF;

    IF v_data_aval < v_data_venda THEN
        RAISE EXCEPTION 'A avaliacao nao pode ser anterior a venda.';
    END IF;

    IF EXISTS (SELECT 1
                 FROM avaliacao_venda av
                 JOIN avaliacao x ON x.id = av.avaliacao_id
                WHERE av.venda_id = NEW.venda_id
                  AND x.autor_id = v_autor
                  AND av.avaliacao_id <> NEW.avaliacao_id) THEN
        RAISE EXCEPTION 'O usuario % ja avaliou a venda %.', v_autor, NEW.venda_id;
    END IF;

    IF EXISTS (SELECT 1 FROM avaliacao_troca
                WHERE avaliacao_id = NEW.avaliacao_id) THEN
        RAISE EXCEPTION 'A avaliacao % ja esta ligada a uma troca.', NEW.avaliacao_id;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_validar_avaliacao_venda ON avaliacao_venda;
CREATE TRIGGER trg_validar_avaliacao_venda
    BEFORE INSERT OR UPDATE ON avaliacao_venda
    FOR EACH ROW
    EXECUTE FUNCTION fn_validar_avaliacao_venda();


-- ---------------------------------------------------------------------
-- TRIGGER 8 - RS-25: avaliacao de TROCA
--
-- Mesmas regras do trigger 7, para trocas CONCLUIDAS: autor e avaliado
-- sao o proponente e o destinatario.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_validar_avaliacao_troca()
RETURNS TRIGGER AS $$
DECLARE
    v_autor        INTEGER;
    v_avaliado     INTEGER;
    v_data_aval    TIMESTAMP;
    v_proponente   INTEGER;
    v_destinatario INTEGER;
    v_status       VARCHAR(30);
    v_efetivacao   TIMESTAMP;
BEGIN
    SELECT autor_id, avaliado_id, data_avaliacao
      INTO v_autor, v_avaliado, v_data_aval
      FROM avaliacao
     WHERE id = NEW.avaliacao_id;

    SELECT proponente_id, destinatario_id, status_troca, data_efetivacao
      INTO v_proponente, v_destinatario, v_status, v_efetivacao
      FROM troca
     WHERE id = NEW.troca_id;

    IF v_status <> 'concluida' THEN
        RAISE EXCEPTION 'So e possivel avaliar uma troca concluida.';
    END IF;

    IF NOT ((v_autor = v_proponente AND v_avaliado = v_destinatario)
            OR (v_autor = v_destinatario AND v_avaliado = v_proponente)) THEN
        RAISE EXCEPTION
            'A avaliacao % deve ser entre os participantes da troca %.',
            NEW.avaliacao_id, NEW.troca_id;
    END IF;

    IF v_data_aval < v_efetivacao THEN
        RAISE EXCEPTION 'A avaliacao nao pode ser anterior a troca.';
    END IF;

    IF EXISTS (SELECT 1
                 FROM avaliacao_troca avt
                 JOIN avaliacao x ON x.id = avt.avaliacao_id
                WHERE avt.troca_id = NEW.troca_id
                  AND x.autor_id = v_autor
                  AND avt.avaliacao_id <> NEW.avaliacao_id) THEN
        RAISE EXCEPTION 'O usuario % ja avaliou a troca %.', v_autor, NEW.troca_id;
    END IF;

    IF EXISTS (SELECT 1 FROM avaliacao_venda
                WHERE avaliacao_id = NEW.avaliacao_id) THEN
        RAISE EXCEPTION 'A avaliacao % ja esta ligada a uma venda.', NEW.avaliacao_id;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_validar_avaliacao_troca ON avaliacao_troca;
CREATE TRIGGER trg_validar_avaliacao_troca
    BEFORE INSERT OR UPDATE ON avaliacao_troca
    FOR EACH ROW
    EXECUTE FUNCTION fn_validar_avaliacao_troca();


-- ---------------------------------------------------------------------
-- EXTRA DE BAIXO NIVEL: ABERTURA_RECIPIENTE
--
-- Valida cada abertura (caixa exige chave e gera equipamento; capsula
-- abre sem chave e gera adesivo, chaveiro ou grafite), consome o
-- recipiente e a chave (que nao podem ter anuncio aberto) e impede
-- alterar ou apagar o historico.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_registrar_abertura_recipiente()
RETURNS TRIGGER AS $$
DECLARE
    v_tipo_recipiente            VARCHAR(80);
    v_dono_recipiente            INTEGER;
    v_status_recipiente          VARCHAR(30);
    v_tradable_recipiente        BOOLEAN;
    v_lacrado_recipiente         BOOLEAN;
    v_cargas_recipiente          INTEGER;
    v_tipo_chave                 VARCHAR(80);
    v_dono_chave                 INTEGER;
    v_status_chave               VARCHAR(30);
    v_tradable_chave             BOOLEAN;
    v_lacrado_chave              BOOLEAN;
    v_cargas_chave               INTEGER;
    v_tipo_resultado             VARCHAR(20);
    v_tipo_consumivel_resultado  VARCHAR(80);
    v_dono_resultado             INTEGER;
    v_status_resultado           VARCHAR(30);
    v_tradable_resultado         BOOLEAN;
BEGIN
    SELECT c.tipo_consumivel, i.proprietario_id, i.status_item,
           i.tradable_flag, c.lacrado, c.cargas_restantes
      INTO v_tipo_recipiente, v_dono_recipiente, v_status_recipiente,
           v_tradable_recipiente, v_lacrado_recipiente, v_cargas_recipiente
      FROM consumivel c
      JOIN item_instancia i ON i.id = c.item_instancia_id
     WHERE c.item_instancia_id = NEW.recipiente_id;

    IF NOT FOUND OR v_tipo_recipiente NOT IN ('caixa', 'capsula') THEN
        RAISE EXCEPTION 'O item % nao e uma caixa ou capsula.', NEW.recipiente_id;
    END IF;

    IF v_dono_recipiente <> NEW.usuario_id
       OR v_status_recipiente <> 'disponivel'
       OR NOT v_tradable_recipiente
       OR NOT v_lacrado_recipiente
       OR v_cargas_recipiente <= 0 THEN
        RAISE EXCEPTION 'O recipiente % nao esta disponivel para o usuario %.',
            NEW.recipiente_id, NEW.usuario_id;
    END IF;

    IF v_tipo_recipiente = 'caixa' AND NEW.chave_id IS NULL THEN
        RAISE EXCEPTION 'Uma caixa precisa de chave para ser aberta.';
    ELSIF v_tipo_recipiente = 'capsula' AND NEW.chave_id IS NOT NULL THEN
        RAISE EXCEPTION 'Capsulas sao abertas sem chave.';
    END IF;

    IF NEW.chave_id IS NOT NULL THEN
        SELECT c.tipo_consumivel, i.proprietario_id, i.status_item,
               i.tradable_flag, c.lacrado, c.cargas_restantes
          INTO v_tipo_chave, v_dono_chave, v_status_chave,
               v_tradable_chave, v_lacrado_chave, v_cargas_chave
          FROM consumivel c
          JOIN item_instancia i ON i.id = c.item_instancia_id
         WHERE c.item_instancia_id = NEW.chave_id;

        IF NOT FOUND OR v_tipo_chave <> 'chave'
           OR v_dono_chave <> NEW.usuario_id
           OR v_status_chave <> 'disponivel'
           OR NOT v_tradable_chave
           OR NOT v_lacrado_chave
           OR v_cargas_chave <= 0 THEN
            RAISE EXCEPTION 'A chave % nao esta disponivel para o usuario %.',
                NEW.chave_id, NEW.usuario_id;
        END IF;
    END IF;

    IF EXISTS (SELECT 1 FROM anuncio
                WHERE item_instancia_id IN (NEW.recipiente_id, NEW.chave_id)
                  AND status_anuncio IN ('pendente', 'ativo')) THEN
        RAISE EXCEPTION 'O recipiente ou a chave tem anuncio aberto e nao pode ser aberto.';
    END IF;

    SELECT CASE
               WHEN e.item_instancia_id IS NOT NULL THEN 'equipamento'
               WHEN co.item_instancia_id IS NOT NULL THEN 'cosmetico'
               WHEN cr.item_instancia_id IS NOT NULL THEN 'consumivel'
           END,
           cr.tipo_consumivel, i.proprietario_id, i.status_item, i.tradable_flag
      INTO v_tipo_resultado, v_tipo_consumivel_resultado, v_dono_resultado,
           v_status_resultado, v_tradable_resultado
      FROM item_instancia i
      LEFT JOIN equipamento e ON e.item_instancia_id = i.id
      LEFT JOIN cosmetico co ON co.item_instancia_id = i.id
      LEFT JOIN consumivel cr ON cr.item_instancia_id = i.id
     WHERE i.id = NEW.item_resultado_id;

    IF NOT FOUND
       OR v_dono_resultado <> NEW.usuario_id
       OR v_status_resultado <> 'disponivel'
       OR NOT v_tradable_resultado THEN
        RAISE EXCEPTION 'O item resultado % nao esta disponivel para o usuario %.',
            NEW.item_resultado_id, NEW.usuario_id;
    END IF;

    IF v_tipo_recipiente = 'caixa' AND v_tipo_resultado <> 'equipamento' THEN
        RAISE EXCEPTION 'Caixas devem gerar um item do tipo equipamento.';
    ELSIF v_tipo_recipiente = 'capsula'
          AND NOT (v_tipo_resultado = 'cosmetico'
                   OR (v_tipo_resultado = 'consumivel'
                       AND v_tipo_consumivel_resultado = 'grafite')) THEN
        RAISE EXCEPTION 'Capsulas devem gerar adesivo, chaveiro ou grafite.';
    END IF;

    UPDATE item_instancia
       SET status_item = 'consumido', tradable_flag = FALSE
     WHERE id = NEW.recipiente_id;
    UPDATE consumivel
       SET lacrado = FALSE, cargas_restantes = 0
     WHERE item_instancia_id = NEW.recipiente_id;

    IF NEW.chave_id IS NOT NULL THEN
        UPDATE item_instancia
           SET status_item = 'consumido', tradable_flag = FALSE
         WHERE id = NEW.chave_id;
        UPDATE consumivel
           SET lacrado = FALSE, cargas_restantes = 0
         WHERE item_instancia_id = NEW.chave_id;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION fn_proteger_abertura_recipiente()
RETURNS TRIGGER AS $$
BEGIN
    RAISE EXCEPTION 'O historico de abertura nao pode ser %.',
        LOWER(TG_OP);
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_registrar_abertura_recipiente ON abertura_recipiente;
CREATE TRIGGER trg_registrar_abertura_recipiente
    BEFORE INSERT ON abertura_recipiente
    FOR EACH ROW
    EXECUTE FUNCTION fn_registrar_abertura_recipiente();

DROP TRIGGER IF EXISTS trg_proteger_abertura_recipiente ON abertura_recipiente;
CREATE TRIGGER trg_proteger_abertura_recipiente
    BEFORE UPDATE OR DELETE ON abertura_recipiente
    FOR EACH ROW
    EXECUTE FUNCTION fn_proteger_abertura_recipiente();


-- =====================================================================
-- FUNCOES CHAMADAS PELA APLICACAO
--
-- Operacoes de varias etapas ficam no banco: cada chamada e atomica
-- (se qualquer etapa falhar, nada e gravado) e os triggers acima
-- continuam valendo para cada INSERT/UPDATE feito aqui dentro.
-- =====================================================================


-- ---------------------------------------------------------------------
-- fn_desgaste / fn_desgaste_nome: exterior da skin a partir do float
--
--   FN Factory New (< 0,07)    MW Minimal Wear (< 0,15)
--   FT Field-Tested (< 0,38)   WW Well-Worn (< 0,45)
--   BS Battle-Scarred (>= 0,45)
-- Retornam NULL para itens sem float (cosmeticos e consumiveis).
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_desgaste(p_float NUMERIC)
RETURNS VARCHAR(2) AS $$
    SELECT CASE
               WHEN p_float IS NULL THEN NULL
               WHEN p_float < 0.07  THEN 'FN'
               WHEN p_float < 0.15  THEN 'MW'
               WHEN p_float < 0.38  THEN 'FT'
               WHEN p_float < 0.45  THEN 'WW'
               ELSE 'BS'
           END;
$$ LANGUAGE sql IMMUTABLE;

CREATE OR REPLACE FUNCTION fn_desgaste_nome(p_float NUMERIC)
RETURNS VARCHAR(20) AS $$
    SELECT CASE fn_desgaste(p_float)
               WHEN 'FN' THEN 'Factory New'
               WHEN 'MW' THEN 'Minimal Wear'
               WHEN 'FT' THEN 'Field-Tested'
               WHEN 'WW' THEN 'Well-Worn'
               WHEN 'BS' THEN 'Battle-Scarred'
           END;
$$ LANGUAGE sql IMMUTABLE;


-- ---------------------------------------------------------------------
-- fn_media_vendas_comparaveis: media de preco para a analise de preco
--
-- Compara um item com as vendas CONCLUIDAS do mesmo modelo e da mesma
-- versao: mesmo desgaste (fn_desgaste), StatTrak e Souvenir. Com menos de
-- 2 vendas da versao, ou fora de equipamento, usa todas as vendas do
-- modelo. Retorna a media exata (sem arredondar), o numero de vendas e a
-- base usada ('versao' ou 'modelo'). A pagina da skin (ofertas_do_modelo)
-- e a janela Novo anuncio (analise_preco_anuncio) usam esta funcao, para
-- mostrarem a mesma porcentagem.
-- Uso: SELECT * FROM fn_media_vendas_comparaveis(<item>);
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_media_vendas_comparaveis(p_item_id INTEGER)
RETURNS TABLE (preco_medio NUMERIC, vendas BIGINT, base VARCHAR) AS $$
    WITH alvo AS (
        SELECT i.item_catalogo_id          AS modelo_id,
               fn_desgaste(e.float_value)  AS desgaste,
               e.stattrak_flag,
               e.souvenir_flag
          FROM item_instancia i
          LEFT JOIN equipamento e ON e.item_instancia_id = i.id
         WHERE i.id = p_item_id
    ),
    vendidos AS (
        -- mesma_versao fica NULL fora de equipamento: nao entra no FILTER
        SELECT vc.valor,
               fn_desgaste(e.float_value) = a.desgaste
               AND e.stattrak_flag = a.stattrak_flag
               AND e.souvenir_flag = a.souvenir_flag AS mesma_versao
          FROM alvo a
          JOIN vw_vendas_concluidas vc ON vc.modelo_id = a.modelo_id
          LEFT JOIN equipamento e      ON e.item_instancia_id = vc.item_id
    ),
    resumo AS (
        SELECT AVG(valor)                              AS media_modelo,
               COUNT(*)                                AS vendas_modelo,
               AVG(valor) FILTER (WHERE mesma_versao)  AS media_versao,
               COUNT(*)   FILTER (WHERE mesma_versao)  AS vendas_versao
          FROM vendidos
    )
    SELECT CASE WHEN vendas_versao >= 2 THEN media_versao  ELSE media_modelo  END,
           CASE WHEN vendas_versao >= 2 THEN vendas_versao ELSE vendas_modelo END,
           CASE WHEN vendas_versao >= 2 THEN 'versao'      ELSE 'modelo'      END
      FROM resumo;
$$ LANGUAGE sql STABLE;


-- ---------------------------------------------------------------------
-- fn_sem_acento: texto em minusculas e sem acento, para a busca do
-- catalogo ("capsula" encontra "Capsula" com acento e vice-versa) e
-- para a ordem alfabetica do catalogo e do inventario.
-- As letras acentuadas vem como escape Unicode (o script e ASCII):
-- a, e, i, o, u com acentos (minusculas e maiusculas) e c cedilha.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_sem_acento(p_texto TEXT)
RETURNS TEXT AS $$
    SELECT translate(lower(p_texto),
                     U&'\00E1\00E0\00E2\00E3\00E4\00E9\00E8\00EA\00EB\00ED\00EC\00EE\00EF\00F3\00F2\00F4\00F5\00F6\00FA\00F9\00FB\00FC\00E7\00C1\00C0\00C2\00C3\00C4\00C9\00C8\00CA\00CB\00CD\00CC\00CE\00CF\00D3\00D2\00D4\00D5\00D6\00DA\00D9\00DB\00DC\00C7',
                     'aaaaaeeeeiiiiooooouuuucaaaaaeeeeiiiiooooouuuuc');
$$ LANGUAGE sql IMMUTABLE;


-- ---------------------------------------------------------------------
-- fn_gerar_chave_nfe: chave de acesso simulada de 44 digitos
--
-- Segue o formato da NF-e: UF(2) + AAMM(4) + CNPJ(14) + modelo(2) +
-- serie(3) + numero(9) + tipo de emissao(1) + codigo(8) + digito
-- verificador(1), com o mesmo emitente das notas de 03_dados.sql.
-- O digito verificador usa modulo 11 (pesos 2 a 9, da direita para a
-- esquerda).
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_gerar_chave_nfe(p_numero BIGINT)
RETURNS VARCHAR(44) AS $$
DECLARE
    v_base  VARCHAR(43);
    v_soma  INTEGER := 0;
    v_peso  INTEGER := 2;
    v_resto INTEGER;
BEGIN
    v_base := '35' || to_char(now(), 'YYMM') || '14200166000187' || '55' || '001'
              || lpad(p_numero::TEXT, 9, '0') || '1' || lpad(p_numero::TEXT, 8, '0');

    FOR i IN REVERSE 43..1 LOOP
        v_soma := v_soma + substr(v_base, i, 1)::INTEGER * v_peso;
        v_peso := CASE WHEN v_peso = 9 THEN 2 ELSE v_peso + 1 END;
    END LOOP;

    v_resto := v_soma % 11;
    RETURN v_base || CASE WHEN v_resto < 2 THEN 0 ELSE 11 - v_resto END;
END;
$$ LANGUAGE plpgsql;


-- ---------------------------------------------------------------------
-- fn_comprar_anuncio: compra completa de um anuncio
--
-- Em uma unica operacao: confere o anuncio e o item, cria a venda
-- (concluida), o pagamento (aprovado, simulado) e a nota fiscal, marca
-- o anuncio como vendido e passa o item ao comprador. Os cosmeticos
-- aplicados acompanham o item (trigger 4), e o comprador nao pode ser o
-- vendedor (trigger 2).
-- Uso: SELECT * FROM fn_comprar_anuncio(<anuncio>, <comprador>, 'pix');
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_comprar_anuncio(
    p_anuncio_id    INTEGER,
    p_comprador_id  INTEGER,
    p_metodo        VARCHAR
)
RETURNS TABLE (venda_id INTEGER, protocolo VARCHAR, chave_nota_fiscal VARCHAR) AS $$
DECLARE
    v_anuncio  anuncio%ROWTYPE;
    v_dono     INTEGER;
    v_status   VARCHAR(30);
    v_tradable BOOLEAN;
    v_numero   BIGINT;
    v_venda    INTEGER;
    v_proto    VARCHAR(80);
    v_chave    VARCHAR(44);
BEGIN
    -- Trava o anuncio: duas compras simultaneas nao passam juntas.
    SELECT * INTO v_anuncio
      FROM anuncio
     WHERE id = p_anuncio_id
       FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'O anuncio % nao existe.', p_anuncio_id;
    END IF;

    IF v_anuncio.status_anuncio <> 'ativo' THEN
        RAISE EXCEPTION 'O anuncio % nao esta ativo (status: %).',
            p_anuncio_id, v_anuncio.status_anuncio;
    END IF;

    IF v_anuncio.data_expiracao <= now() THEN
        RAISE EXCEPTION 'O anuncio % venceu em %.',
            p_anuncio_id, to_char(v_anuncio.data_expiracao, 'DD/MM/YYYY');
    END IF;

    IF EXISTS (SELECT 1 FROM venda v WHERE v.anuncio_id = p_anuncio_id) THEN
        RAISE EXCEPTION 'O anuncio % ja tem uma venda em andamento.', p_anuncio_id;
    END IF;

    -- Trava tambem o item: um novo anuncio dele (trigger 5) espera a compra.
    SELECT proprietario_id, status_item, tradable_flag
      INTO v_dono, v_status, v_tradable
      FROM item_instancia
     WHERE id = v_anuncio.item_instancia_id
       FOR UPDATE;

    IF v_dono <> v_anuncio.criador_id OR v_status <> 'disponivel' OR NOT v_tradable THEN
        RAISE EXCEPTION 'O item do anuncio % nao esta mais disponivel.', p_anuncio_id;
    END IF;

    -- A venda entra com um protocolo provisorio: o trigger 2 confere o
    -- comprador e o CHECK de pagamento confere o metodo. So depois disso
    -- a venda recebe o numero definitivo -- assim uma compra recusada
    -- nao "queima" numero de protocolo nem de nota fiscal.
    INSERT INTO venda (protocolo_venda, anuncio_id, comprador_id, data_venda, valor_venda, status_venda)
    VALUES ('TMP-' || gen_random_uuid(), p_anuncio_id, p_comprador_id, now(), v_anuncio.preco, 'concluida')
    RETURNING id INTO v_venda;

    INSERT INTO pagamento (venda_id, metodo_pagamento, valor, data_pagamento, status_pagamento)
    VALUES (v_venda, p_metodo, v_anuncio.preco, now(), 'aprovado');

    -- Numero com pelo menos 4 digitos (0013); a partir de 10000 ele cresce
    -- (lpad sozinho cortaria os digitos a mais e repetiria protocolos).
    v_numero := nextval('venda_protocolo_seq');
    v_proto  := 'VND-' || to_char(now(), 'YYYY') || '-'
                || lpad(v_numero::TEXT, GREATEST(4, length(v_numero::TEXT)), '0');
    v_chave  := fn_gerar_chave_nfe(v_numero);

    UPDATE venda SET protocolo_venda = v_proto WHERE id = v_venda;

    INSERT INTO nota_fiscal (chave, venda_id, data_emissao, valor_total)
    VALUES (v_chave, v_venda, now(), v_anuncio.preco);

    UPDATE anuncio
       SET status_anuncio = 'vendido'
     WHERE id = p_anuncio_id;

    UPDATE item_instancia
       SET proprietario_id = p_comprador_id
     WHERE id = v_anuncio.item_instancia_id;

    RETURN QUERY SELECT v_venda, v_proto, v_chave;
END;
$$ LANGUAGE plpgsql;


-- ---------------------------------------------------------------------
-- fn_avaliar_venda: avaliacao de um participante de uma venda
--
-- Descobre o avaliado (a outra parte da venda), gera o ticket e grava
-- a avaliacao e o subtipo juntos -- assim toda avaliacao criada pela
-- aplicacao ja nasce no subtipo certo (RS-09). As demais regras ficam
-- no trigger 7.
-- Uso: SELECT fn_avaliar_venda(<venda>, <autor>, 5, 'Comentario');
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_avaliar_venda(
    p_venda_id    INTEGER,
    p_autor_id    INTEGER,
    p_nota        INTEGER,
    p_comentario  TEXT
)
RETURNS VARCHAR AS $$
DECLARE
    v_comprador  INTEGER;
    v_vendedor   INTEGER;
    v_avaliado   INTEGER;
    v_ticket     VARCHAR(80);
    v_avaliacao  INTEGER;
    v_numero     BIGINT;
BEGIN
    -- FOR UPDATE: dois pedidos simultaneos do mesmo autor sao feitos um
    -- depois do outro, e o segundo ja ve a primeira avaliacao (trigger 7).
    SELECT v.comprador_id, a.criador_id
      INTO v_comprador, v_vendedor
      FROM venda v
      JOIN anuncio a ON a.id = v.anuncio_id
     WHERE v.id = p_venda_id
       FOR UPDATE OF v;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'A venda % nao existe.', p_venda_id;
    END IF;

    v_avaliado := CASE p_autor_id
                      WHEN v_comprador THEN v_vendedor
                      WHEN v_vendedor  THEN v_comprador
                  END;

    IF v_avaliado IS NULL THEN
        RAISE EXCEPTION 'O usuario % nao participou da venda %.', p_autor_id, p_venda_id;
    END IF;

    -- Ticket provisorio ate o CHECK da nota e o trigger 7 aprovarem;
    -- so entao a avaliacao recebe o numero definitivo (sem pular numeros).
    INSERT INTO avaliacao (ticket_avaliacao, autor_id, avaliado_id, data_avaliacao, comentario, nota)
    VALUES ('TMP-' || gen_random_uuid(), p_autor_id, v_avaliado, now(),
            NULLIF(btrim(p_comentario), ''), p_nota)
    RETURNING id INTO v_avaliacao;

    INSERT INTO avaliacao_venda (avaliacao_id, venda_id)
    VALUES (v_avaliacao, p_venda_id);

    v_numero := nextval('avaliacao_ticket_seq');
    v_ticket := 'TKT-' || to_char(now(), 'YYYY') || '-'
                || lpad(v_numero::TEXT, GREATEST(4, length(v_numero::TEXT)), '0');

    UPDATE avaliacao SET ticket_avaliacao = v_ticket WHERE id = v_avaliacao;

    RETURN v_ticket;
END;
$$ LANGUAGE plpgsql;


-- ---------------------------------------------------------------------
-- fn_expirar_anuncios: encerra os anuncios vencidos
--
-- Marca como 'expirado' todo anuncio aberto cuja data de expiracao ja
-- passou (exceto os que tem venda pendente). A aplicacao chama esta
-- funcao antes de listar anuncios. Retorna quantos foram expirados.
-- Uso: SELECT fn_expirar_anuncios();
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_expirar_anuncios()
RETURNS INTEGER AS $$
DECLARE
    v_qtd INTEGER;
BEGIN
    UPDATE anuncio a
       SET status_anuncio = 'expirado'
     WHERE a.status_anuncio IN ('pendente', 'ativo')
       AND a.data_expiracao <= now()
       AND NOT EXISTS (SELECT 1 FROM venda v
                        WHERE v.anuncio_id = a.id
                          AND v.status_venda = 'pendente');

    GET DIAGNOSTICS v_qtd = ROW_COUNT;
    RETURN v_qtd;
END;
$$ LANGUAGE plpgsql;
