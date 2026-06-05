-- =====================================================================
-- Esteira de Criação de Matérias — Schema do banco (PostgreSQL)
-- Convive com as tabelas já existentes do sistema de disparo
-- (ex.: cidades, grupos). Ajuste tipos se o banco atual for outro.
-- =====================================================================

-- ---------- FONTES DE ENTRADA -----------------------------------------
-- E-mail, WhatsApp e cada jornal vigiado são "fontes".
CREATE TABLE IF NOT EXISTS fontes (
    id              BIGSERIAL PRIMARY KEY,
    nome            TEXT NOT NULL,
    tipo            TEXT NOT NULL CHECK (tipo IN ('email','whatsapp','jornal_rss','jornal_html','oficial')),
    config          JSONB NOT NULL DEFAULT '{}',   -- url, rss_url, seletores, filtros, intervalo_min, editoria_padrao
    ativo           BOOLEAN NOT NULL DEFAULT TRUE,
    ultima_coleta   TIMESTAMPTZ,
    ultimo_erro     TEXT,
    criado_em       TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ---------- CONTROLE DE NOVIDADE (anti-duplicata da coleta) ------------
CREATE TABLE IF NOT EXISTS visto (
    id              BIGSERIAL PRIMARY KEY,
    fonte_id        BIGINT REFERENCES fontes(id) ON DELETE CASCADE,
    hash            TEXT NOT NULL,                 -- hash(url_canonica + titulo_normalizado)
    url             TEXT,
    primeira_vez_em TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (fonte_id, hash)
);
CREATE INDEX IF NOT EXISTS idx_visto_hash ON visto(hash);

-- ---------- INBOX (tudo que chega, bruto) -----------------------------
CREATE TABLE IF NOT EXISTS inbox (
    id              BIGSERIAL PRIMARY KEY,
    fonte_id        BIGINT REFERENCES fontes(id) ON DELETE SET NULL,
    recebido_em     TIMESTAMPTZ NOT NULL DEFAULT now(),
    remetente       TEXT,
    url_origem      TEXT,                          -- guardada p/ auditoria (NÃO publicada)
    titulo_origem   TEXT,
    texto_bruto     TEXT NOT NULL,
    anexos          JSONB NOT NULL DEFAULT '[]',   -- [{nome, tipo, caminho}]
    imagem_origem   TEXT,
    status          TEXT NOT NULL DEFAULT 'novo'
                    CHECK (status IN ('novo','classificado','arquivado','processando','erro')),
    criado_em       TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_inbox_status ON inbox(status);

-- ---------- CARDS (assunto curado, pós-classificação) -----------------
CREATE TABLE IF NOT EXISTS cards (
    id              BIGSERIAL PRIMARY KEY,
    inbox_ids       BIGINT[] NOT NULL DEFAULT '{}',-- pode agrupar várias entradas do mesmo fato
    classificacao   TEXT NOT NULL
                    CHECK (classificacao IN ('MATERIA','TALVEZ','NAO','DUPLICADO')),
    motivo          TEXT,
    editoria        TEXT,                          -- Política | Polícia | Cidades | Economia/Agro | Outro
    cidade_id       BIGINT,                        -- FK p/ tabela de cidades existente (ajuste o nome)
    municipio_txt   TEXT,                          -- fallback textual
    confianca       NUMERIC(3,2) DEFAULT 0,
    agrupado_em     BIGINT REFERENCES cards(id) ON DELETE SET NULL, -- se DUPLICADO
    fatos           JSONB,                         -- saída da extração de fatos
    criado_em       TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_cards_classificacao ON cards(classificacao);

-- ---------- MATÉRIAS (produto final, pré e pós-aprovação) -------------
CREATE TABLE IF NOT EXISTS materias (
    id                  BIGSERIAL PRIMARY KEY,
    card_id             BIGINT REFERENCES cards(id) ON DELETE CASCADE,
    manchete            TEXT,
    manchetes_alt       JSONB NOT NULL DEFAULT '[]',
    linha_fina          TEXT,
    corpo               TEXT,
    resumo_post         TEXT,
    titulo_seo          TEXT,
    meta_descricao      TEXT,
    tags                JSONB NOT NULL DEFAULT '[]',
    editoria            TEXT,
    cidade_id           BIGINT,
    pendencias          JSONB NOT NULL DEFAULT '[]', -- [VERIFICAR: ...] e alertas de QA
    similaridade_flag   BOOLEAN NOT NULL DEFAULT FALSE,
    status              TEXT NOT NULL DEFAULT 'rascunho'
                        CHECK (status IN ('rascunho','em_revisao','aprovada','reprovada','publicada')),
    versao              INT NOT NULL DEFAULT 1,
    editada_por_humano  BOOLEAN NOT NULL DEFAULT FALSE,
    portal_ids          BIGINT[] NOT NULL DEFAULT '{}', -- destino(s)
    criado_em           TIMESTAMPTZ NOT NULL DEFAULT now(),
    atualizado_em       TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_materias_status ON materias(status);

-- Histórico de versões quando o revisor manda refazer/editar
CREATE TABLE IF NOT EXISTS materia_versoes (
    id              BIGSERIAL PRIMARY KEY,
    materia_id      BIGINT REFERENCES materias(id) ON DELETE CASCADE,
    versao          INT NOT NULL,
    snapshot        JSONB NOT NULL,                -- cópia completa da matéria naquela versão
    origem          TEXT,                          -- 'ia' | 'edicao_humana' | 'refazer'
    instrucao       TEXT,                          -- instrução do revisor no "refazer"
    criado_em       TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ---------- PORTAIS DE DESTINO (os 19 sites) --------------------------
CREATE TABLE IF NOT EXISTS portais (
    id              BIGSERIAL PRIMARY KEY,
    nome            TEXT NOT NULL,
    wordpress_url   TEXT,                          -- base da API REST
    auth            JSONB NOT NULL DEFAULT '{}',   -- app password / token (criptografar)
    editorias       JSONB NOT NULL DEFAULT '[]',
    ativo           BOOLEAN NOT NULL DEFAULT TRUE,
    criado_em       TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ---------- CONFIG (prompts, critérios, webhook do disparo) -----------
CREATE TABLE IF NOT EXISTS config (
    chave           TEXT PRIMARY KEY,
    valor           JSONB NOT NULL,
    atualizado_em   TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ---------- AUDITORIA (rastreabilidade jornalística) ------------------
CREATE TABLE IF NOT EXISTS audit_log (
    id              BIGSERIAL PRIMARY KEY,
    materia_id      BIGINT,
    acao            TEXT NOT NULL,                 -- aprovar | editar | refazer | reprovar | publicar
    autor           TEXT,                          -- usuário revisor
    antes           JSONB,
    depois          JSONB,
    em              TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_audit_materia ON audit_log(materia_id);

-- ---------- SEEDS DE CONFIG (exemplos) --------------------------------
INSERT INTO config (chave, valor) VALUES
  ('webhook_disparo', '{"url":"", "ativo": false}'),
  ('modelos_ia', '{"classificacao":"haiku","extracao_fatos":"haiku","reescrita":"sonnet","manchete":"sonnet","qa":"haiku","similaridade":"haiku"}'),
  ('criterios_classificacao', '{"sempre_materia":["decisão oficial","operação policial","obra pública","dado econômico novo"],"sempre_lixo":["convite","agradecimento","corrente","propaganda","mensagem pessoal"]}')
ON CONFLICT (chave) DO NOTHING;
