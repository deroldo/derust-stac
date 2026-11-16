# Recuperacao e repeticao de request guiada pelo servidor (Stac) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** O runtime Flutter do Stac reconhece, na resposta de erro de qualquer request, uma instrucao de recuperacao montada pelo servidor (`recovery`: `recover`, `retry`, `onFailure`, `onUnavailable`), executa-a, repete o request original uma vez e, quando falha, mostra/executa o erro final do servidor (ou um erro generico), sem telas em branco. Em paralelo, a web ganha uma pilha local de navegacao (F5, voltar, avancar) via `StacRouter`.

**Architecture:** Um interceptor no Dio unico (`StacNetworkService`) detecta o envelope (`Content-Type: application/vnd.stac.error+json` + `version`), guarda o "molde" do request (JSON com bindings + escopo capturado + vida) em `RequestOptions.extra`, roda `recover` (action Stac) coalescida por identidade, repete o request com bindings reavaliados e `retry.overrides`, e entrega ao chamador o ultimo erro observado (`StacRecoveryException`). A lib nao conhece token, refresh, sessao nem status.

**Tech Stack:** Dart ^3.12.0 / Flutter >=3.44.0, `dio`, `json_serializable` + `build_runner` (stac_core), `flutter_test`, Mintlify `.mdx` em `docs/`.

**Spec:** Plano de negocio aprovado no vault Obsidian: `Projects/derust-stac/plans/sessao_expirada_renovacao_e_navegacao.md` (citado como "Plano N"). Companheiro (fora deste escopo): `Projects/derust/plans/sessao_expirada_renovacao_e_navegacao.md`. Worktree/branch: `/Users/deroldo/workspace/derust-stac-recuperacao`, branch `recuperacao_e_repeticao_de_request_guiada_pelo_servidor`.

**Escopo:** so este repo (derust-stac), tarefas T0 a T8 e T10 do plano. T9 (derust, Rust), T11 e T12 (aplicacao no Tapbook/customer-app) ficam fora. Nao e issue `transversal`.

## Global Constraints

- Pacotes: logica em `packages/stac` (runtime), modelos/DSL de action em `packages/stac_core`; docs em `docs/`; exemplo em `stac_playground`. Convencoes do `CLAUDE.md` da raiz (Melos, `melos run build/analyze/format`; `.g.dart` commitados; `melos run format` nao pode alterar arquivos).
- Nada de regra de dominio: a lib nao sabe o que e token, refresh, `Authorization`, `WWW-Authenticate`, sessao. Sem configuracao de recuperacao no app, sem lista de status, sem regra/match no front.
- Opt-in total: sem envelope em nenhuma resposta, o comportamento atual nao muda (exceto o erro generico da T5, que substitui a tela em branco, e `onError` honrado, R7 do Plano).
- Reconhecimento: apenas resposta nao-2xx + `Content-Type: application/vnd.stac.error+json` + corpo JSON objeto + `version` inteira suportada (1). Qualquer outra coisa = erro comum, com log; nunca executa nada. Envelope em 2xx e ignorado. Corpo RFC 7807 sem marcador nao e confundido.
- Uma unica repeticao por request; qualquer verbo; URL e metodo nunca mudam. A repeticao e os requests feitos pela action `recover` **e os requests emitidos por `onFailure`/`onUnavailable`** (G7 opcao B) sao isentos de recuperacao (marca por `Zone` copiada para `RequestOptions.extra['stac.recovery.exempt']` ao montar o request).
- A recuperacao pertence ao request corrente: tela descartada ou request cancelado (`alive()` falso) = para (nao repete, nao roda `onFailure` para ele).
- Valores em `request`/`failure` passam por `StacGlobalState.redact` nos logs.
- Commits `<type>: <subject>` com corpo explicando o porque.

## Decisoes de negocio (todas fechadas pelo usuario; nenhuma nova no refinamento)

Modelo = instrucao na resposta de erro (G4/G10); G1, G3, G5, G6, G8 conforme Plano 9.1. Fechadas agora: **G7 = opcao B** (trava na lib); **G2** tres estados + `recoveryOutcome` explicito + deducao padrao; **G6b** o chamador nao renderiza o erro final se `onFailure` rodou (erro final segue em `response` do `onError`); **G9b** `StacRecoveryInstruction` (runtime) / `Recovery` (DSL, campo `recovery`); **G11** marcador por `Content-Type`; **G12** coalescencia por `key` (hash do JSON canonico de `recover` como padrao, `key: null` desliga); **G13** `action` do envelope roda depois do `onError`; **G14** widget minimo embutido como erro generico padrao. **N2 a N5** (base do `StacRouter`, avancar no v1, nome, onde guardar a pilha) so se fecham com o spike S1 (T6).

## Decisoes de mecanica (o "como")

- **M1 Molde.** `StacRequestTemplate` = JSON do request antes de `resolveBindings` + `StacCapturedScope` + `requestKey` + `alive()`; guardado em `RequestOptions.extra['stac.template']`. Request sem molde (Dio do app) repete as `RequestOptions` originais + overrides.
- **M2 Headers por chamada.** `StacNetworkService.request` passa `Options(headers, contentType)` por chamada; nunca mutar `_dio.options` (T0).
- **M3 Isencao por Zone.** Valor de `Zone` lido ao montar o `RequestOptions` (nao no interceptor), copiado para `extra`.
- **M4 Coalescencia.** Mapa em memoria `identidade -> StacRecoveryRun` (Future compartilhado) + `lastSuccessAt` por identidade (geracao). Request disparado antes de `lastSuccessAt` e que falha depois so repete.
- **M5 Lider.** Executa o primeiro request ainda vivo, no escopo dele; se morrer, a execucao termina pela cadeia capturada; acoes que exigem tela montada sao puladas com log; `onFailure` roda uma vez no escopo do primeiro request vivo; nenhum vivo = nada roda.
- **M6 Resultado.** `recoveryOutcome {result, condition?}` (primeira emitida vence); padrao pelos `networkRequest` diretos de `recover` (5xx/timeout/rede = `unavailable`; senao 4xx = `failure`; senao `success`; excecao = `failure` com log); `timeoutMs` default 20 s = `unavailable`.
- **M7 Erro final.** `StacRecoveryException extends DioException` carrega o ultimo erro observado (resposta da repeticao, ou do ultimo request falho em `recover`, ou o original se nao houve).
- **M8 `fromNetwork`.** Vira `StacNetworkView` (StatefulWidget) com `CancelToken` cancelado no `dispose`; fornece `alive()`.
- **M9 Corpo nao reutilizavel** (stream/`FormData`): nao repete, log claro.

## Dependencias e paralelismo

```
T0 ──> T2 ──> T3 ──> T4 ──> T10
T1 ──────────^  └──> T5
T6 (spike + StacRouter) independente ──> T7 (opcional)
T8 (docs/playground) depende de T4 e T5 (e T6 para a parte de router)
```
Em paralelo ao inicio: T0, T1, T6. Sequenciais: T2 depois de T0; T3 depois de T1 e T2; T4 e T5 depois de T3 (T4 e T5 podem rodar em paralelo entre si); T10 depois de T4 (e do schema do envelope; fixtures escritas a mao neste repo).

Contexto de codigo (ler antes de qualquer tarefa): `packages/stac/lib/src/services/stac_network_service.dart` (Dio unico), `framework/stac_service.dart` (`fromJson`, `resolveBindings`, `_resolveActionJson`, `onCallFromJson`), `framework/stac.dart` (`fromNetwork`, `initialize`), `state/stac_scope.dart` (`StacCapturedScope`), `parsers/actions/stac_network_request/stac_network_request_parser.dart`, `stac_navigate_action_parser.dart`, `stac_dialog_action_parser.dart`, `stac_modal_bottom_sheet_action_parser.dart`, `parsers/widgets/stac_network_widget/stac_network_widget_parser.dart`, `packages/stac/lib/src/state/`.

---

## Task 0 — Corrida de headers no StacNetworkService (SIMPLES) — CONCLUIDA

**Depende de:** nada. **Atende:** pre-requisito de qualquer repeticao confiavel (Plano 2 achado 1, 5.5).

**Contexto:** `StacNetworkService.request` faz `_dio.options.headers = headers` (estado global do Dio) e, no POST, `await _updateBody(...)` antes de `_dio.post`; outro request pode sobrescrever headers/`contentType` no intervalo.

**Passos:**
- [x] Escrever teste com `HttpClientAdapter` fake: dois requests simultaneos com headers/contentType diferentes, com `await` no meio (body assincrono no primeiro); cada request deve chegar ao adapter com os proprios headers. Deve falhar antes do conserto.
- [x] Trocar a mutacao de `_dio.options` por `Options(headers: ..., contentType: ...)` passado em cada chamada `get/post/put/delete/patch`. Nao alterar `_dio.options` por chamada.
- [x] Rodar `cd packages/stac && flutter test`, `melos run analyze`, `melos run format`.

**Testes e revisao:** teste concorrente acima; regressao: requests existentes mantem headers padrao do Dio do app. Revisor confere que nenhum outro ponto muta `_dio.options.*` por request.

---

## Task 1 — Envelope, instrucao e reconhecimento (MEDIO)

**Depende de:** nada. **Atende:** Plano 4.1, 5.1, 5.2, 6 (item 4).

**Arquivos (novos):** `packages/stac/lib/src/recovery/stac_error_envelope.dart`, `stac_recovery_instruction.dart`, `stac_envelope_recognizer.dart`; export em `packages/stac/lib/stac.dart` (conferir barrel). Em `framework/stac.dart`: parametro `genericErrorBuilder: Widget Function(BuildContext, Object error)?` em `Stac.initialize`.

**Contrato do envelope v1:** `{version:int, code?:String, message?:String, screen?:Map(widget), action?:Map(action), recovery?:{key?:String|null (ausente != null explicito), recover:action|List, retry?:{overrides?:{headers?,queryParameters?,body?}, removeHeaders?:List<String>}, onFailure?:action|List, onUnavailable?:action|List, timeoutMs?:int}}`. Modelos Dart simples com `fromJson` (mantem `screen`/`action`/`recover` como JSON cru `Map`/`List`; sem `json_serializable` obrigatorio). Distinguir `key` ausente de `key: null` explicito (flag `keyDisabled`).

**Reconhecedor puro** `StacEnvelopeRecognizer.recognize(Response)` -> `StacErrorEnvelope?`: nao-2xx, content-type (ignorar parametros `; charset`), corpo ja decodificado como `Map` (ou String JSON), `version` int == 1. Versao desconhecida/JSON invalido/campo mal formado = null + log.

**Passos:**
- [ ] Testes de tabela do reconhecedor: marcador ok; sem marcador; content-type com charset; versao 2; versao string; JSON invalido; corpo lista; envelope em 200; corpo RFC 7807 (`type`) sem marcador; `key` ausente vs `null`.
- [ ] Implementar modelos + reconhecedor.
- [ ] Adicionar `genericErrorBuilder` a `Stac.initialize` (apenas guardar; uso na T5).
- [ ] analyze/format/test.

**Revisao:** nada no reconhecedor pode olhar status, URL ou corpo de terceiros; nunca lanca.

---

## Task 2 — Molde do request, vida do request e repeticao (COMPLEXO)

**Depende de:** T0. **Atende:** Plano 5.3, achados 2 e 3, G3, R2 (alto risco de regressao).

**Contexto:** bindings sao resolvidos antes de chegar ao Dio (`_resolveActionJson`, `resolveBindings`). Para reavaliar na repeticao e preciso carregar o JSON do request ainda com bindings + escopo capturado (`StacCapturedScope`, em `state/stac_scope.dart`).

**Passos:**
- [ ] Definir `StacRequestTemplate` (M1) e `StacRequestAlive` (`bool Function()`; combina `CancelToken.isCancelled` + tela viva).
- [ ] `_resolveActionJson` / `StacNetworkRequestParser` passam o JSON nao resolvido junto do resolvido; `StacNetworkService.request` recebe `template` opcional e o coloca em `RequestOptions.extra['stac.template']`. `fromNetwork`/`navigate.request`/dialog/sheet resolvem em `resolveBindings`: ajustar localmente para tambem entregar o molde.
- [ ] `StacNetworkService.retryRequest(template | RequestOptions, overrides, removeHeaders)`: reavalia bindings no escopo capturado; aplica `overrides` (merge por chave, `null` remove; valores aceitam bindings, resolvidos apos a recuperacao no mesmo escopo); `removeHeaders`; reenvia com mesmo `CancelToken`, `requestKey`, `contentType`; marca `extra['stac.recovery.exempt']=true`. Nunca reexecuta `onStart`; `onSuccess`/`onError`/`onFinally` do chamador rodam com a resposta final.
- [ ] M8: `Stac.fromNetwork` passa a `StacNetworkView` (StatefulWidget) cancelando o `CancelToken` no `dispose`; expor `alive()`.
- [ ] Corpo nao reutilizavel (M9): detectar (`Stream`, `FormData` ja consumido) e marcar `extra['stac.retry.unsafe']`.
- [ ] Testes: retry reavalia header `{"$state":"global.x"}` com valor novo; override merge/remove; URL/metodo inalterados; sem molde (RequestOptions) repete original; `alive()` falso depois de `dispose` da tela; `onStart` nao reexecuta.
- [ ] Rodar toda a suite de `packages/stac` (regressao: network request, navigate.request, dialog, sheet, networkWidget) + analyze/format.

**Revisao:** o ponto mais delicado do runtime; revisor confere que o caminho sem molde/sem envelope e byte a byte o atual.

---

## Task 3 — Interceptor e execucao da recuperacao (COMPLEXO)

**Depende de:** T1, T2. **Atende:** Plano 3, 4.2, 4.4, 4.5, 4.6, 5.1.

**Arquivos (novos):** `recovery/stac_recovery_interceptor.dart`, `recovery/stac_recovery_run.dart`, `recovery/stac_recovery_exception.dart`; instalar o interceptor em `StacNetworkService.initialize` sobre o Dio do app.

**Passos:**
- [ ] `onError` do interceptor: se request isento (M3) ou sem envelope reconhecido ou envelope sem `recovery` ou `alive()` falso -> passa adiante (erro comum; se havia envelope, fica anexado ao erro para a T5).
- [ ] Com `recovery`: obter/criar `StacRecoveryRun` por identidade (M4; `key`, senao hash do JSON canonico de `recover` com chaves ordenadas; `keyDisabled` = sem coalescencia). Geracao: se `request.startedAt < lastSuccessAt`, so repete.
- [ ] Executar `recover` (action ou lista em sequencia, como `multiAction`) no escopo do request lider (M5), sob `Zone` de isencao; variaveis somente-leitura `request` e `failure`; timeout (`timeoutMs`, default 20 s = `unavailable`).
- [ ] `success` -> repete via `retryRequest` (T2); sucesso da repeticao resolve normalmente; falha da repeticao -> `StacRecoveryException` com o erro da repeticao, SEM nova recuperacao. `failure`/`unavailable` -> resultados entregues a T4 para rodar `onFailure`/`onUnavailable`; chamador recebe `StacRecoveryException` com o ultimo erro (M7).
- [ ] Cancelamento: request cancelado durante a recuperacao nao e repetido; a execucao compartilhada continua. Lider morre: M5. Corpo nao reutilizavel: nao repete, log.
- [ ] Testes (adapter fake): 1 recuperacao + repeticao com header novo; 5 requests concorrentes mesma identidade = 1 `recover`, cada um repete o proprio; geracao; repeticao que falha = erro da repeticao e nenhuma nova recuperacao; requests do `recover` e a repeticao com envelope `recovery` na resposta nao recuperam; qualquer verbo; cancelamento; lider morre; `key: null` desliga; sem envelope = comportamento atual; erro de rede sem resposta nunca recuperado.

**Revisao:** garantir ausencia de recursao e de espera circular (run esperando a si mesmo); logs com `redact`.

---

## Task 4 — Action `recoveryOutcome`, resultado e trava G7-B (MEDIO)

**Depende de:** T3. **Atende:** Plano 4.3, G2, G7 (opcao B).

**Arquivos:** tipo em `packages/stac_core/lib/foundation/specifications/action_type.dart` (`recoveryOutcome`), modelo `packages/stac_core/lib/actions/stac_recovery_outcome/stac_recovery_outcome.dart` (`result: success|failure|unavailable`, aceita `condition` como as demais actions), export, `melos run build`; parser em `packages/stac/lib/src/parsers/actions/stac_recovery_outcome/`, registrado em `_actionParsers` de `stac_service.dart`; DSL no `stac_core`.

**Passos:**
- [ ] Modelo + parser + registro; o parser emite o resultado no contexto do `StacRecoveryRun` corrente (via `Zone`); fora de uma recuperacao: log e no-op. Primeira emissao vence.
- [ ] Deducao padrao (M6) pelos `networkRequest` executados diretamente por `recover` quando nenhuma emissao explicita.
- [ ] Rodar `onFailure` (resultado `failure`) e `onUnavailable` (resultado `unavailable`, nao roda `onFailure`; nada e apagado) uma vez, no escopo do primeiro request vivo; `success` nao roda nenhum.
- [ ] **G7-B:** `onFailure` e `onUnavailable` rodam sob a mesma `Zone` de isencao: requests emitidos por eles (inclusive `navigate.request`) nao sao recuperados. Teste: `onFailure` navega para tela cujo GET responde envelope com `recovery` -> nenhuma nova recuperacao, nenhum laco.
- [ ] Testes: primeira emissao vence; `condition`; deducao nos tres casos (5xx/rede, 4xx, 2xx); excecao = `failure`; timeout = `unavailable`.

---

## Task 5 — Chamadores, erro final e erro generico (MEDIO)

**Depende de:** T3 (pode rodar em paralelo a T4). **Atende:** Plano 5.4, 6, G6b, G8, G13, G14, R7.

**Passos:**
- [ ] `fromNetwork`, `navigate.request`, dialog, sheet e `networkWidget` entendem `StacRecoveryException` e o envelope do erro final: envelope com `screen` -> renderiza o widget; so com `action` -> executa a action no escopo do request; sem envelope (rede, parse, outro servico) -> `genericErrorBuilder` ou widget minimo embutido (icone + "Nao foi possivel carregar"); `genericErrorBuilder: (_,__)=>SizedBox()` desliga. Remover o comportamento "erro vira `SizedBox` em release".
- [ ] G6b: se `onFailure` rodou, o chamador nao renderiza o erro final (continua em `response` do `onError`).
- [ ] `onError`/`onFinally` do `StacNetworkRequest` carregado por `fromNetwork`/`navigate` passam a ser honrados.
- [ ] `networkRequest`: roda o `onError` do proprio request com `response` = erro final (nunca no meio da recuperacao), sempre `onFinally`, e **depois** executa a `action` do envelope (G13); `screen` nao se aplica. `onSuccess` roda apos a repeticao bem sucedida.
- [ ] Testes de widget: `fromNetwork` recuperavel renderiza a tela; irrecuperavel renderiza o `screen` do erro final ou o generico, nunca branco; `networkRequest` `onSuccess` apos repeticao, nunca `onError` intermediario, `onFinally` sempre; `onError` do model em `navigate.request`; ordem `onError` -> `action` (G13).

**Revisao:** R7 — mudar o comportamento de telas existentes; conferir testes existentes e playground.

---

## Task 6 — Spike S1 e `StacRouter` (COMPLEXO)

**Depende de:** nada. **Atende:** Plano 7, N1 a N5, R1. **Nao fixar a base antes do spike.**

**Passos:**
- [ ] Spike S1 em Chrome real com o app web de referencia (backoffice, no repo do Tapbook, ou um app minimo em `stac_playground`/`examples/`): comparar tres variantes: **A** Navigator 1.0 atual (reproduzir o relato: voltar limitado apos F5, avancar nao funciona); **B** Router API com a pilha em `RouteInformation.state`/`history.state`; **C** Router API com a pilha em `sessionStorage`. Matriz de cenarios (Plano 7.3): F5 em profundidade 3; voltar 2x pos-F5; avancar apos voltar; voltar+navegar trunca o futuro; `pushReplacement` sem entrada extra e `pushAndRemoveAll` + voltar nao reabre telas anteriores (epoch); URL com query em F5/voltar/avancar; aba nova e aba duplicada (sem/com `state`); recuperacao (T3) durante voltar/avancar. Registrar o resultado em `docs/` (nota curta) e medir o custo (muda o `MaterialApp`, como `navigate` abre rotas).
- [ ] Se o ambiente nao permitir navegador real, **parar e reportar** ao coordenador; nao fixar a base por hipotese.
- [ ] Decidir A/B/C com o resultado e **registrar a decisao (N2, N3, N5) para o usuario confirmar** antes de implementar a opcao escolhida.
- [ ] Implementar `StacRouter` (pacote `stac`): `/screens/x?q=1` -> `GET <base><backendPrefix>/screens/x?q=1`, sem splash; config `baseUrl`, `screensPrefix`, `backendPrefix`, `loading`, `initialFallback`; pilha local por aba, reconstruida no F5, `epoch` para `pushAndRemoveAll`; no mobile deve comportar-se como a pilha nativa. Dialogs/sheets fora da pilha de URLs. A URL reconstroi a tela; `navigate.params`/`onResult` nao sobrevivem ao F5. Pilha sem segredos.
- [ ] Testes: unidade da pilha (push/replace/truncar futuro/epoch/limite de profundidade) e a matriz do spike automatizada (Chrome/Playwright) quando viavel.

---

## Task 7 — `restorationScopeId` no mobile (SIMPLES, opcional)

**Depende de:** T6. Expor `restorationScopeId` opcional no `StacApp`/`StacRouter` para reabrir a mesma tela apos o SO matar o processo; nunca estado no back. Teste: widget test com restauracao simulada. Pular se o usuario nao quiser.

---

## Task 8 — Docs e playground (MEDIO)

**Depende de:** T4, T5 (parte de router depende de T6). **Atende:** Plano 10 T8.

- [ ] `docs/concepts/` (ingles, Mintlify): pagina de recuperacao e erro (contrato do envelope v1, reconhecimento, `recover`/`retry`/`onFailure`/`onUnavailable`, `recoveryOutcome`, coalescencia, isencao, G7-B, erro final, `genericErrorBuilder`); `docs/actions/recovery_outcome.mdx` no formato de `docs/actions/set_value.mdx`; pagina do `StacRouter` apos T6; navegacao em `docs/docs.json`.
- [ ] `stac_playground`: DSL + JSON + entrada em `lib/data/component_entries.dart` para `recoveryOutcome`; manter `dsl_to_json.dart` e `test/dsl_to_json_test.dart` em sincronia (`cd stac_playground && flutter test`, `flutter build web`).
- [ ] Exemplo do envelope generico (nao o do Tapbook) como referencia.

---

## Task 10 — Harness de compatibilidade do envelope (MEDIO)

**Depende de:** T4. **Atende:** Plano 10 T10, restrito a este repo.

- [ ] Fixtures JSON do envelope e da instrucao em `packages/stac/test/recovery/fixtures/` (as mesmas que o derust deve produzir: marcador, `version`, `recovery` completo, `screen`-so, `action`-so, versao desconhecida) e teste que as parseia com o runtime real (reconhecedor + modelos + `recoveryOutcome` via parser) e executa um ciclo completo 401 -> recover -> repeticao. Documentar em `docs/` onde o repo derust deve consumir as mesmas fixtures (T9 fora de escopo).

---

## Checklist final (gates do projeto, Flutter)

- `melos run analyze` limpo; `melos run format` sem alterar arquivos; `cd packages/stac && flutter test`; `cd stac_playground && flutter test` e `flutter build web`.
- Requisitos: cada tarefa confere com o que pediu este documento e com o Plano de negocio.
