# Resposta para o Claude Code (cole isto)

Respondendo às suas duas perguntas e já te entregando material pronto para acelerar.

## Suas 2 perguntas

1. **A esteira de e-mail/WhatsApp + reescrita por IA já existe?**
   Não — ela **faz parte do mesmo pacote a construir**. O sistema atual é só distribuição/disparo. O Motor de Busca depende dessa esteira, então construa a esteira primeiro e o Motor de Busca como a 3ª entrada dela.

2. **Tenho a chave da Anthropic API?**
   Sim, tenho a chave. Use a Anthropic API para todas as etapas de IA (classificação, extração de fatos, reescrita, manchete, QA, similaridade). Como são chamadas de API na nuvem, **não há o problema de RAM da VPS** (aquilo era para rodar modelo local). Os modelos por etapa estão definidos no arquivo de prompts.

## Material pronto que estou te entregando (revise, audite e use)

- `Design_Tecnico_do_Sistema.md` — como o sistema deve ser (arquitetura, pipeline, endpoints, deploy, aceite).
- `schema.sql` — todas as tabelas novas, prontas, convivendo com cidades/grupos existentes.
- `prompts/prompts.md` — os 6 prompts finalizados, com o modelo recomendado por etapa.
- `seed/fontes_rondonia.json` — fontes iniciais do Motor de Busca para semear.
- (Já entreguei antes: o briefing principal e o anexo do Motor de Busca.)

## Como quero que você toque

1. **Revise e audite** estes artefatos contra o código atual do projeto (stack, banco, convenções). Aponte qualquer ajuste antes de codar.
2. **Implemente na stack que o projeto já usa.** Adapte o `schema.sql` se o banco não for PostgreSQL.
3. **Monte o plano detalhado** (arquivos, tabelas, endpoints, fila/worker) e me mostre para aprovação.
4. **Execute pela ordem das fases** do design (Fase 1 = núcleo da esteira com e-mail + reescrita + fila; depois Motor de Busca; depois integração com o disparo).
5. Entregue **README de instalação** e **`.env.example`** com todas as chaves.

## Detalhe da memória que você perguntou

Sobre "Nova Brasilândia d'Oeste → Zona da Mata": **vou confirmar a divisão editorial e te respondo** — não assuma ainda; deixe como está e marque para revisão.

Pode registrar o briefing + este pacote como **roadmap salvo na VPS** (não só na memória).
