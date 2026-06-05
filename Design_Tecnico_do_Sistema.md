# Design técnico — Esteira de Criação de Matérias

**Documento de "como o sistema deve ser".** Acompanha: `schema.sql`, `prompts/prompts.md`, `seed/fontes_rondonia.json`. Entregar tudo ao Claude Code junto com o briefing principal e o anexo do Motor de Busca.

---

## 1. Objetivo e escopo

Construir a **esteira de produção de matérias** que hoje não existe e plugá-la ao sistema de **disparo que já roda** na VPS (cidades + grupos + distribuição). A esteira:

1. **Recebe** conteúdo por três entradas: e-mail, WhatsApp e um **motor de busca** que vigia outros jornais.
2. **Identifica** o que é matéria e o que não é (nem tudo que chega vira notícia).
3. **Reescreve** com IA como matéria própria, no tom "curiosidade forte, mas séria", **sem citar a origem**.
4. **Coloca numa fila** onde **uma pessoa só** aprova, edita ou manda refazer.
5. **Entrega** o conteúdo aprovado ao **disparo existente** (via webhook) e, opcionalmente, publica no site (WordPress).

**Fora de escopo:** o disparo em grupos (já pronto), artes/vídeos e relatórios comerciais (operações separadas).

---

## 2. Encaixe no sistema atual

O sistema atual cuida da **distribuição**. Esta esteira é um **novo conjunto de módulos + dashboard** que produz o conteúdo que entra nessa distribuição. Pontos de contato:

- **Reaproveita** a tabela de **cidades** (para roteamento por município) e o cadastro de **grupos** já existentes — não recria.
- **Não altera** a lógica de envio. Quando uma matéria é aprovada, dispara um **webhook** com o pacote pronto; o disparo continua igual.
- Roda na **mesma VPS**. A IA é **chamada por API (nuvem)**, então o consumo de RAM local é baixo — a restrição de 3.8 GB (válida para rodar modelo local) **não se aplica** a chamadas de API.

---

## 3. Arquitetura

```
                 ┌─────────────────────────────────────────────┐
   ENTRADAS      │            PIPELINE (workers)               │      SAÍDAS
                 │                                             │
 [E-mail]  ─────►│ ingestão → classificação → dedup →          │──► WordPress (opcional)
 [WhatsApp]─────►│ extração de fatos → reescrita (IA) →        │
 [Motor de busca]│ QA + similaridade → FILA                    │──► Webhook do disparo
   (RSS/HTML) ──►│                                             │     (sistema existente)
                 └───────────────┬─────────────────────────────┘
                                 │
                          [ DASHBOARD WEB ]
                 Conexões · Fila de revisão · Configurações · Arquivo
                                 │
                            [ PostgreSQL ]
```

Componentes:

- **Coletores (workers):** processos que rodam por agendamento (cron/intervalo) — leitor de e-mail, receptor de WhatsApp, vigia de jornais.
- **Pipeline (fila de jobs):** cada etapa é um módulo isolado e testável que consome um job e gera o próximo.
- **API + Dashboard:** aplicação web para o revisor operar.
- **Banco:** PostgreSQL (ver `schema.sql`).
- **Camada de IA:** wrapper único da Anthropic API, com o modelo de cada etapa definido por config.

---

## 4. Stack e infraestrutura

> O Claude Code deve implementar **na mesma stack do projeto atual** (ele conhece o código existente; este documento não impõe linguagem). As recomendações abaixo valem se ele estiver criando do zero.

- **Dashboard/API:** uma aplicação web única (ex.: Next.js, ou o framework já usado no projeto).
- **Banco:** PostgreSQL (se o projeto já usa outro, adaptar o `schema.sql`).
- **Fila:** simples no início — tabela de jobs com status, ou BullMQ/Redis se já houver Redis.
- **Workers:** processos separados do web, controlados por cron/intervalo, com lock para não rodar duplicado.
- **IA:** Anthropic API. Wrapper com retry, timeout e seleção de modelo por etapa (config `modelos_ia`).
- **Segredos:** em `.env` (chave Anthropic, credenciais de e-mail/WordPress, URL do webhook). Nunca no código.

### Modelos por etapa (custo/qualidade)
| Etapa | Modelo | Por quê |
|---|---|---|
| Classificação | Haiku | alto volume, barato; pode ir na Batch API |
| Extração de fatos | Haiku | tarefa estruturada |
| **Reescrita** | **Sonnet** | qualidade do texto é crítica |
| Manchetes | Sonnet | criatividade com controle |
| QA anti-invenção | Haiku (Sonnet em editoria sensível) | checagem objetiva |
| Similaridade | Haiku | comparação simples |

Custo de IA por matéria fica em centavos; o sistema é desenhado para que **escalar volume não escale custo humano**.

---

## 5. Modelo de dados

Detalhado em `schema.sql`. Resumo: `fontes` (entradas) → `inbox` (bruto) → `cards` (classificado + fatos) → `materias` (produto, com `materia_versoes` para histórico) → `portais` (destino) → saída. `visto` controla novidade da coleta; `config` guarda prompts/critérios/webhook; `audit_log` registra toda ação humana. As tabelas reaproveitam `cidade_id` da base existente.

---

## 6. Pipeline detalhado

| # | Etapa | Entrada | Processo | Saída | Em caso de erro |
|---|---|---|---|---|---|
| 1 | Ingestão | e-mail / msg / item de feed | normaliza texto + anexos; grava `inbox` | registro `inbox` | marca `inbox.status=erro`, loga |
| 2 | Classificação | `inbox` | prompt 1 (Haiku) | `cards.classificacao` | confiança baixa → TALVEZ |
| 3 | Dedup | card novo | compara com cards recentes (assunto/tempo) | agrupa ou segue | na dúvida, não agrupa |
| 4 | Extração de fatos | texto bruto | prompt 2 (Haiku) | `cards.fatos` | lacunas marcadas |
| 5 | (opcional) Verificação | fatos sensíveis | busca fonte oficial | confirma/ajusta | marca pendência |
| 6 | Reescrita | `cards.fatos` | prompt 3 (Sonnet) + prompt 4 manchetes | `materias` (rascunho) | retry; senão pendência |
| 7 | QA + similaridade | matéria + fonte | prompt 5 e 6 (Haiku) | flags/pendências | similar demais → regenera 1x |
| 8 | Fila | matéria `em_revisao` | humano decide | aprovada/reprovada | — |
| 9 | Saída | matéria `aprovada` | WordPress + webhook | `publicada` | retry com backoff |

**Regra de ouro:** nada passa da etapa 8 sem aprovação humana. Etapas 2, 4, 7 que ficarem incertas **mandam para o humano**, nunca descartam nem publicam sozinhas.

---

## 7. Conectores de entrada

### 7.1 E-mail
- **Gmail via OAuth** (botão no dashboard) + **IMAP genérico** para outras contas.
- Filtros por remetente/etiqueta. Extrai anexos (PDF/imagem/docx) e anexa ao `inbox`.

### 7.2 WhatsApp (conector plugável)
- **Piloto:** ponte por e-mail (mensagens encaminhadas para uma caixa de captação) — zero infra nova.
- **Escala:** Evolution API / Baileys (QR no dashboard) ou Cloud API oficial da Meta.
- Toda entrada cai no **mesmo pipeline** do e-mail.

### 7.3 Motor de busca (outros jornais)
- Conector de fonte **plugável e configurável por formulário** (RSS preferencial; HTML com seletores como fallback).
- Detecção de novidade por `visto(fonte_id, hash)`; respeita `robots.txt`, intervalo civilizado e User-Agent identificável.
- Reescrita **parte dos fatos**, não do texto; **não cita** a origem; guarda a URL só para auditoria interna.
- Lista inicial em `seed/fontes_rondonia.json`.

---

## 8. Dashboard (telas e rotas)

- **/conexoes** — conectar Gmail (OAuth), IMAP, WhatsApp (com QR quando aplicável) e a aba **"Outros jornais"** (cadastrar fonte, "Testar extração", status/erros). Tudo por formulário, sem código.
- **/fila** — coração da operação. Por matéria: manchete recomendada + 4 alternativas; corpo editável inline; **fonte original lado a lado** (uso interno); pendências/`[VERIFICAR]` em destaque; editoria + cidade + portal de destino; botões **Aprovar / Editar / Refazer** (refazer aceita instrução curta); atalhos de teclado.
- **/config** — editar prompts (1–6), critérios de classificação, portais (adicionar o 20º é só preencher), templates por editoria.
- **/arquivo** — itens `NAO`, pesquisáveis e resgatáveis.

### Endpoints principais (contratos)
```
POST /api/ingest                 # recebe item bruto (usado pelos workers/webhook whatsapp)
GET  /api/fila?status=em_revisao # lista matérias para revisar
POST /api/materias/:id/aprovar   # → publica + dispara webhook
POST /api/materias/:id/editar    # salva edição humana + aprova
POST /api/materias/:id/refazer   # body: { instrucao } → regenera
POST /api/fontes                 # cadastra fonte (jornal/email/whatsapp)
POST /api/fontes/:id/testar      # "Testar extração"
GET  /api/arquivo?q=...          # busca em itens NAO
```

---

## 9. Saída e integração com o disparo

- **WordPress (opcional):** API REST, no portal certo, categorizado por `cidade_id`, como rascunho final ou publicado (config por portal).
- **Webhook do disparo (obrigatório):** ao aprovar, `POST` na URL configurada (`config.webhook_disparo`) com:
```json
{ "manchete":"...", "resumo_post":"...", "link":"https://portal/...",
  "municipio":"...", "editoria":"...", "imagem":"url_opcional" }
```
- O sistema **não** decide grupos nem cadência — isso é do disparo existente.

---

## 10. Segurança e conformidade editorial

- **Anti-invenção:** regras nos prompts + etapa de QA que confere afirmação contra a fonte; o que não tiver respaldo vira `[VERIFICAR]`.
- **Anti-cópia:** reescrita a partir de fatos + checagem de similaridade com regeneração automática.
- **Aprovação humana obrigatória** antes de qualquer saída.
- **Auditoria:** `audit_log` registra quem aprovou/editou/refez, com antes/depois.
- **Dados sensíveis:** evitar CPF, endereço de vítima, dados de menores no texto final.
- **Segredos** criptografados/fora do código; credenciais de WordPress por portal.

---

## 11. Deploy na VPS

- Processos: **web** (dashboard/API) + **worker(s)** (coletores e pipeline) + **cron** (varredura das fontes).
- Recomendado **Docker Compose** (web, worker, postgres, e redis se usar fila). Banco com backup diário.
- `.env` com: `ANTHROPIC_API_KEY`, credenciais de e-mail, credenciais WordPress por portal, `WEBHOOK_DISPARO_URL`.
- Logs por etapa do pipeline para depuração; alertas no dashboard quando uma fonte falha na extração.

---

## 12. Critérios de aceite (consolidado)

1. Conectar Gmail e WhatsApp (ao menos ponte por e-mail) pelo dashboard e ver entradas chegando.
2. Cadastrar um jornal novo por formulário e ver matérias dele entrando ("Testar extração" funciona).
3. O que **não é matéria** vai para `Arquivo`, não para a fila.
4. Matérias chegam à fila **já redigidas**, com manchete + 4 alternativas, fonte ao lado e pendências marcadas.
5. **Aprovar / Editar / Refazer** funcionam; refazer com instrução regenera em segundos.
6. Coleta não duplica a mesma notícia; mesmo fato de fontes diferentes é agrupado.
7. QA marca afirmação sem respaldo; similaridade alta regenera automaticamente.
8. Nenhuma matéria sai sem aprovação humana.
9. Aprovar publica (se configurado) e dispara o webhook correto.
10. `audit_log` preenchido; README + `.env.example` entregues; roda na VPS.

---

## 13. Fases de entrega

- **Fase 1 — Núcleo:** e-mail (Gmail) + classificação + extração + reescrita + QA + fila (3 botões) + saída como rascunho no WordPress de 1 portal-piloto. WhatsApp por ponte de e-mail.
- **Fase 2 — Volume e fontes:** motor de busca (RSS) + dedup + enriquecimento + multi-portal + tela de config completa + arquivo.
- **Fase 3 — Integração e refino:** webhook do disparo + WhatsApp por QR/Cloud API + scraping HTML + verificação cruzada em editorias sensíveis + ajuste de prompts pelas edições do revisor.

---

## 14. O que o Claude Code já recebe pronto

- **Este documento de design.**
- **`schema.sql`** — todas as tabelas novas.
- **`prompts/prompts.md`** — os 6 prompts finalizados, com modelo por etapa.
- **`seed/fontes_rondonia.json`** — fontes iniciais para semear.
- Briefing principal + anexo do Motor de Busca (documentos anteriores).

**Pedido ao Claude Code:** revisar/auditar estes artefatos, montar o **plano detalhado** (arquivos, tabelas, endpoints, fila) na stack do projeto atual, confirmar e então **executar pela ordem das fases**.
