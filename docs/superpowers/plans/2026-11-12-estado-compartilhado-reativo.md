# Estado compartilhado e reativo (Stac) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Permitir que o JSON de uma tela declare estado (por tela e global), bindings reativos em qualquer propriedade de widget, actions de mutacao, estado em requests HTTP e passagem/retorno de valores entre telas, tudo no runtime Flutter do Stac, sem codigo por tela no app.

**Architecture:** Store proprio (`StacStateStore`, `ValueNotifier` por chave) em dois niveis (tela e global). Bindings (`{"$state": "k"}` / `{"$expr": "..."}`) sao resolvidos no nivel de `StacService.fromJson` ANTES de `parser.getModel`: um widget `StacReactive` observa as chaves citadas, re-resolve o JSON proprio do widget (sem descer em filhos, que resolvem a si mesmos) e reexecuta o parser normal. Actions resolvem seus bindings no momento da execucao (`StacService.onCallFromJson`). Variaveis locais (`item`, `index`, `params`, `result`, `response`, `event`) vem de `InheritedWidget` (widgets) e de uma `Zone` (actions).

**Tech Stack:** Dart ^3.12.0 / Flutter >=3.44.0, `json_serializable` + `build_runner` (stac_core), `dio`, `shared_preferences` (ja dependencia de `stac`), `flutter_secure_storage` (unica dependencia nova, apenas na Task 19), `flutter_test`, Mintlify `.mdx` em `docs/`.

**Spec:** Plano de negocio aprovado no vault Obsidian: `Projects/derust-stac/plans/estado_compartilhado_reativo.md` (secoes citadas como "Plano 5.x"). Worktree/branch: `/Users/deroldo/workspace/derust-stac/.worktrees/estado_compartilhado_reativo`, branch `estado_compartilhado_reativo`.

## Global Constraints

- Tudo em `packages/` e `docs/`; nada de regra de dominio especifica: so mecanica generica (Plano 14, 16).
- `setValue`, `{{var}}` (`resolveVariablesInJson`), `getFormValue` e `ExpressionResolver` legado **nao mudam** (Plano decisao 6). O sistema novo vive em `packages/stac/lib/src/state/` com sintaxe propria (`$state`/`$expr`).
- Sem Riverpod e sem dependencia nova, exceto `flutter_secure_storage` na Task 19 (Plano decisao 1, 12). Sem `StreamController` para estado (Plano 5.8).
- Expressoes: nunca executar codigo arbitrario; `null` em aritmetica = resultado `null` + log; divisao por zero = `null` + log; `3 != "3"` (sem coercao em `==`) (Plano 5.3).
- Namespaces reservados: `global`, `params`, `result`, `response`, `event`. Chave de tela com esses nomes e invalida (erro logado, chave ignorada).
- Listas e mapas do estado sao imutaveis: sempre gravar copia nova (Plano 5.4/5.8).
- Chave nao declarada: leitura `null`; escrita = erro tratado e logado, sem crash.
- Docs: Mintlify `.mdx`, **ingles**, mesmo formato das paginas existentes (`docs/actions/set_value.mdx`: frontmatter `title`/`description`, tabela `Properties`, bloco `<CodeGroup>` Dart/JSON); navegacao em `docs/docs.json`. Sem JSON Schema. Fase so fecha com a doc dela (Plano 7).
- Commits `<type>: <subject>` com corpo explicando o porque. `melos run format` nao pode alterar arquivos; `melos run analyze` limpo. Arquivos `.g.dart` sao commitados (`melos run build` apos mudar qualquer `@JsonSerializable`).
- Acoes do framework usam a chave `actionType`; widgets usam `type` (os exemplos do Plano usam `type` por ilustracao; o contrato real usa `actionType` para actions).

## Review Focus

1. Digitar num textField com `bind` nao pode perder foco/cursor nem reescrever o texto (Task 9: teste de cursor no meio do texto).
2. Resposta de request atrasada/fora de ordem nao pode sobrescrever estado mais novo; nem apos a tela fechar (Task 12).
3. Tipos e bordas na expressao: `null` em aritmetica, divisao por zero, `3` vs `"3"`, referencia a chave inexistente, expressao invalida em `visible`/`enabled`/`condition` (Task 1 e Task 4).
4. `pop` quando a tela de origem ja nao existe, voltar sem escolher, e `pop` com `result: null` explicito (Task 13).
5. Rebuild do pai (ex.: troca de tema) nao pode reinicializar o estado da tela; so recarga do servidor reinicializa (Task 6).

## Decisoes de mecanica (o "como"; nenhuma e regra de negocio nova)

- **D1 Ponto de interceptacao.** `StacWidget.fromJson` guarda o JSON cru (`jsonData`), entao cada widget filho chega ao proprio `StacService.fromJson` com todas as propriedades. Bindings do widget sao resolvidos ali, antes de `getModel`; filhos nao sao tocados pelo pai.
- **D2 Regra "o que e filho".** Ao resolver o JSON proprio de um widget, um sub-mapa e **pulado** se tem `actionType` (action, resolvida na execucao) ou `type` registrado em `StacRegistry` (widget filho). Em **actions**, as chaves de dado `values`, `value`, `result`, `params`, `body`, `queryParameters`, `headers`, `initial` sao resolvidas por inteiro (sem regra de pulo), pois sao dados.
- **D3 Binding.** Mapa com exatamente uma chave, `$state` ou `$expr`, valor String. `$state: "a.b[0]"` e atalho para uma expressao que e so um caminho.
- **D4 Nomes.** Resolucao de identificador: variaveis locais (mais interna primeiro) > prefixo `global.` > chave do estado da tela. `params` e `result`/`response`/`event` sao variaveis locais.
- **D5 Dependencias.** Cada identificador raiz vira dependencia no nivel da chave de topo (`global.usuario.nome` depende de `global.usuario`). Granularidade por chave de topo.
- **D6 Fallback de expressao invalida/`null`.** `visible`, `enabled` e `condition` com resultado `null`/nao-bool (expressao invalida, chave inexistente, erro) valem `false`, com log. Em `Text`, resultado `null` vira texto vazio.
- **D7 Concatenacao.** `+` com ao menos um texto concatena; numeros inteiros-valorados imprimem sem `.0`; bool vira `true`/`false`; `null`, lista ou mapa como operando de concatenacao = invalido (`null` + log).
- **D8 `incrementState`/`decrementState`.** `by` padrao 1; `min`/`max` fazem clamp.
- **D9 Eventos de entrada.** `onChanged` continua sendo uma unica `StacAction` (varias = `multiAction`), igual aos models atuais. O valor novo fica disponivel como `event.value` durante a action. `bind` e reescrito pelo runtime para `value-prop: {"$state": k}` + `onChanged = multiAction(sync: true)[setState {k: {"$state": "event.value"}}, onChanged original]` (garante gravar antes do `onChanged`). `onInit` e callbacks `onStart/onSuccess/onError/onFinally`: aceitam uma action ou uma lista (lista = `multiAction` sync).
- **D10 `pop`.** Nao ha action nova: `navigate` com `navigationStyle: pop` e `result` (qualquer JSON, com bindings). Pop com resultado envia `StacPopResult(value)` (classe interna) ao Navigator; `onResult` so roda se o Future resolver para `StacPopResult`; `null` puro (botao voltar/gesto/pop sem `result`) = cancelamento (`onCancel`). A chamada que aguardava o push recebe o valor desembrulhado (compatibilidade).
- **D11 Reload.** O estado de tela vive num `StatefulWidget` (`StacStateScope`) com chave de conteudo (hash do JSON dos blocos `state`+`onInit`), e os pontos de entrada de tela (`Stac(routeName)`) embrulham o resultado em `KeyedSubtree(key: ObjectKey(response))`: nova resposta do servidor = estado reinicializado; rebuild do pai com a mesma resposta = estado mantido. `_StacView` passa a buscar a tela uma vez (hoje refaz o fetch a cada build).
- **D12 `globalState`.** Valor por chave: valor direto, ou objeto de declaracao se so tiver chaves de `{initial, persist, secure}` e contiver `initial`. Declaracao idempotente.
- **D13 `secure: true` com `persist: false`.** Aviso logado, `persist` ignorado (vale persist). Web sem armazenamento seguro: nao grava, loga aviso.
- **D14 Hidratacao.** `Stac.initialize` (que o app aguarda antes de `runApp`) carrega as chaves persistidas; a primeira tela nunca espera nem le `null` por causa disso.
- **D15 Sem `emptyTemplate`** (usar `visible` sobre `length(lista) == 0`). Identidade de item de lista por indice no v1.
- **D16 DSL Dart.** `stac_core` ganha modelos para as actions novas, campos novos tipados e o helper `StacBinding.state(k)`/`StacBinding.expr(e)` (serializa para `$state`/`$expr`). Propriedades de envelope (`visible`, `enabled`, `bind`, `state`, `globalState`, `onInit`) sao autoradas como JSON no v1 (derust emite JSON); nao entram na DSL Dart. Campos tipados que precisam aceitar binding (ex.: `StacConditional.condition`, `StacNavigateAction.result`) passam a `dynamic`/`Object?`.
- **D17 Nomes finais de campos** estao nas Interfaces de cada task e na Task 20 (pagina de referencia). O backend (derust) fica fora deste repo.

## Grafo de dependencias e paralelismo

```
Fase 1: T1 ─┐
        T2 ─┴─> T3 ─> T4 ─┬─> T5 ─┐
                          └─> T6 ─┴─> T7(docs)
Fase 2: (T4,T5,T6) ─> T8 ┐
                     T9  ├ paralelas ─> T11(docs)
                     T10 ┘
Fase 3: T12 (apos T8,T9) ; T13 (apos T6; paralela a T12) ─> T14(docs)
Fase 4: T15 (apos T6) ; T16 (apos T5,T13,T15) ─> T17(docs)
Fase 5: T18 (apos T15)
Fase 6: T19 (apos T2,T6,T12)
Fase 7: T20 (apos tudo)
```
Paralelas: T1||T2; T5||T6; T8||T9||T10; T12||T13; T15 pode comecar junto de T12/T13. Sequenciais obrigatorias: T3 depois de T1+T2; T4 depois de T3; docs sempre em sequencia (editam `docs/docs.json`).

## File Structure (novos arquivos principais)

`packages/stac/lib/src/state/`
- `expression/stac_expression.dart` (+ `lexer.dart`, `parser.dart`, `evaluator.dart`, `functions.dart`): linguagem de expressoes.
- `stac_state_store.dart` (interface), `stac_memory_state_store.dart`, `stac_global_state.dart`.
- `stac_scope.dart` (`StacScope`, `StacLocalScope`, `StacStateScope`), `stac_action_vars.dart` (Zone).
- `stac_binding.dart` (deteccao/resolucao), `stac_reactive.dart`, `stac_envelope.dart` (`visible`/`enabled`/`bind`).
- `stac_state_exports.dart` exportado de `packages/stac/lib/stac.dart`.

`packages/stac_core/lib/actions/<set_state|increment_state|...>/`: modelos + `.g.dart`. Testes em `packages/stac/test/state/`.

---

### Task 1: Linguagem de expressoes [CONCLUIDA]

**Dificuldade:** complexo. **Depende de:** nada. **Paralela com:** T2.

**Files:**
- Create: `packages/stac/lib/src/state/expression/stac_expression.dart` (+ `lexer.dart`, `parser.dart`, `evaluator.dart`, `functions.dart`)
- Test: `packages/stac/test/state/expression_test.dart`

**Contexto:** o `ExpressionResolver` legado (`lib/src/utils/expression_resolver.dart`) quebra strings com `split` e NAO deve ser usado nem alterado. Escrever tokenizer + parser de precedencia (Pratt) + avaliador puro em Dart, sem `dart:mirrors`/eval.

**Interfaces:**
- Produces:
```dart
abstract class StacEvalContext { Object? lookup(String root); } // raiz: 'total', 'global', 'params', 'item'...
class StacExpression {
  static StacExpression parse(String source);        // lanca StacExpressionException se sintaxe invalida
  Set<String> get dependencies;                      // caminhos de topo: 'total', 'global.usuario' (D5)
  bool get isPurePath;                               // so identificador/campo/indice (para $state)
  Object? evaluate(StacEvalContext ctx);             // nunca lanca: invalido => null + Log.w
}
```
- Gramatica/precedencia (menor para maior): ternario `?:`, `||`, `&&`, `== !=`, `< <= > >=`, `+ -`, `* / %`, unarios `! -`, chamada/campo/indice. Literais: numero, texto `'..'`/`".."` com `\\` de escape, `true/false/null`. Funcoes: `length(x)` (texto/lista; `null`=0), `trim(texto)`, `contains(lista, valor)`, `contains(lista, objeto, 'campo')` (igualdade por campo). Funcao desconhecida = invalida.
- Semantica: D7 para `+`; aritmetica com `null`/nao-numero = `null`+log; `/` e `%` por zero = `null`+log; `==`/`!=` sem coercao, aceitam `null`; `<,<=,>,>=` so numeros (senao `null`+log); `&&`,`||`,`!` so bool (senao `null`+log), com curto-circuito; ternario exige condicao bool.

- [ ] **Step 1:** Escrever `expression_test.dart` com tabela de casos (expressao, contexto, esperado): `'Total: ' + total` com total=3 -> `'Total: 3'`; `total == 10` -> bool; `total >= 10 ? 'max' : 'ok'`; `null + 1` -> `null`; `1/0` -> `null`; `3 == '3'` -> `false`; `x == null` com x inexistente -> `true`; `lista[0].nome`; `length(null) == 0`; `length(trim('  ')) > 0` -> `false`; `contains(sel, item, 'id')`; `a && b` curto-circuito (rhs invalido nao e avaliado); precedencia `1 + 2 * 3 == 7`; `1.5 + 1.5` -> `3.0` (soma numerica) e `'x' + 3.0` -> `'x3'` (D7); `dependencies` de `global.usuario.nome == null && total > 1` = `{global.usuario, total}`; `parse('1 +')` lanca `StacExpressionException`.
- [ ] **Step 2:** Rodar `cd packages/stac && flutter test test/state/expression_test.dart` -> FAIL (arquivo inexistente).
- [ ] **Step 3:** Implementar lexer, parser (AST imutavel) e avaliador conforme a Interface; `dependencies` coletado do AST (inclui ramos nao executados).
- [ ] **Step 4:** Rodar o teste -> PASS. `melos run analyze` e `melos run format` limpos.
- [ ] **Step 5:** `git commit -m "feat: add state expression language"` (corpo: por que um parser proprio em vez do ExpressionResolver legado).

**Plano de testes:** unitario puro (acima) + teste de nao-lancamento (fuzz curto: 200 strings aleatorias nunca lancam em `evaluate`). **Revisao:** conferir que nenhum caminho usa `ExpressionResolver`, que erros logam via `Log.w` (stac_logger) e que a precedencia bate com a tabela.

---

### Task 2: Stores de estado (tela e global) [CONCLUIDA]

**Dificuldade:** medio. **Depende de:** nada. **Paralela com:** T1.

**Files:**
- Create: `packages/stac/lib/src/state/stac_state_store.dart`, `stac_memory_state_store.dart`, `stac_global_state.dart`
- Test: `packages/stac/test/state/state_store_test.dart`

**Interfaces:**
- Produces:
```dart
abstract class StacStateStore {
  bool has(String key);
  Object? read(String key);                       // chave de topo; ausente => null
  ValueListenable<Object?>? listenable(String key); // null se nao declarada
  void declare(String key, Object? initial);      // idempotente: se ja existe, mantem valor
  bool write(String key, Object? value);          // false + Log.e se nao declarada/reservada; grava copia profunda imutavel
  void batch(void Function() body);               // notificacoes adiadas ate o fim do body
  void reset(String key);                         // volta ao inicial declarado
  void resetAll();
  Object? initialOf(String key);
  void dispose();
}
class StacMemoryStateStore implements StacStateStore { StacMemoryStateStore(); }
class StacGlobalState { static final StacGlobalState instance; StacStateStore get store; } // singleton; sem dispose
```
- Regras: `declare` rejeita nomes `global/params/result/response/event` (Log.e, retorna sem declarar). Valores gravados/declarados sao copiados em profundidade e envolvidos em colecoes nao modificaveis (`List.unmodifiable`/`Map.unmodifiable`) para que `ValueNotifier` (compara por `==`) notifique sempre que a colecao e substituida. Gravar valor igual (escalar) nao notifica. `batch` aninhado notifica uma unica vez ao sair do mais externo.
- Futuro (T19): `StacGlobalState` expora `declareWithFlags(key, initial, {persist, secure})` — nesta task so deixar o ponto de extensao (`StacKeyFlags`), sem persistencia.

- [ ] **Step 1:** Testes: `declare` idempotente (segundo `declare` com outro inicial mantem valor atual); `write` em chave nao declarada retorna `false` sem lancar; escrita notifica listener 1x; `batch` com 3 escritas dispara 1 notificacao por chave; lista gravada e imutavel (`add` lanca) e mutar a lista original depois nao altera o store; `reset` restaura inicial; nome reservado rejeitado; `StacGlobalState.instance` compartilha valor entre dois leitores.
- [ ] **Step 2:** Rodar `flutter test test/state/state_store_test.dart` -> FAIL.
- [ ] **Step 3:** Implementar com `Map<String, ValueNotifier<Object?>>`; `batch` coleta chaves sujas e notifica ao fim.
- [ ] **Step 4:** Teste -> PASS; analyze/format.
- [ ] **Step 5:** `git commit -m "feat: add screen and global state stores"`.

**Plano de testes:** unitario. **Revisao:** nenhuma mutacao in-place possivel; sem dependencia de Flutter widgets alem de `ValueNotifier`; singleton resetavel em testes (`StacGlobalState.instance.store.resetAll()` + metodo `@visibleForTesting clear()`).

---

### Task 3: Escopos (estado de tela, variaveis locais, variaveis de action) e harness de teste [CONCLUIDA]

**Dificuldade:** medio. **Depende de:** T1, T2.

**Files:**
- Create: `packages/stac/lib/src/state/stac_scope.dart`, `stac_action_vars.dart`, `stac_state_exports.dart`
- Create: `packages/stac/test/state/harness.dart`
- Test: `packages/stac/test/state/scope_test.dart`
- Modify: `packages/stac/lib/stac.dart` (exportar `stac_state_exports.dart`)

**Interfaces:**
- Consumes: `StacStateStore`, `StacGlobalState`, `StacExpression`/`StacEvalContext`.
- Produces:
```dart
class StacLocalScope extends InheritedWidget {          // variaveis lexicais; mescla com o escopo pai
  const StacLocalScope({required Map<String, Object?> vars, required Widget child, super.key});
  static Map<String, Object?> varsOf(BuildContext c);   // pai + proprias (proprias sombreiam)
}
class StacStateScope extends StatefulWidget {           // dono do store de tela
  const StacStateScope({required Map<String, Object?> initialState, Object? onInit,
      required Widget child, super.key});
  static StacStateStore? storeOf(BuildContext c);       // sem criar dependencia de rebuild
  static StacRequestRegistry requestsOf(BuildContext c); // CancelToken por requestKey (T12)
}
class StacScope {                                       // fachada de leitura usada por bindings e actions
  static StacScope of(BuildContext c);                  // le StacLocalScope + StacStateScope + zone vars
  Object? lookup(String root);                          // D4
  List<Listenable> listenablesFor(Set<String> dependencies); // so chaves de store; locais nao tem
  StacEvalContext get evalContext;
  bool write(String path, Object? value);               // 'k' -> tela; 'global.k' -> global
  StacStateStore? storeFor(String path);
}
Future<T> runWithStacActionVars<T>(Map<String, Object?> vars, FutureOr<T> Function() body); // Zone; vars visiveis por StacScope.of dentro do body e continuacoes async
```
- `onInit` e `initialState` sao avaliados/executados na Task 6; aqui `StacStateScope` apenas cria o store (declarando `initialState` resolvido), expoe e faz `dispose()` no `State.dispose`.
- `harness.dart`: `Future<void> pumpStac(WidgetTester t, Map<String,dynamic> json, {Dio? dio})` — chama `StacService.initialize(...)` uma unica vez (`setUpAll`), monta `MaterialApp(home: Scaffold(body: Builder(builder: (c) => StacService.fromJson(json, c)!)))` e `pump()`. Inclui `FakeDioAdapter` (HttpClientAdapter com respostas enfileiradas e atraso configuravel) para as tasks de rede.

- [ ] **Step 1:** Testes: `StacLocalScope` interno sombreia externo e ve o externo (`as` aninhado); `StacScope.lookup('x')` le chave da tela; `lookup('global')` retorna um `StacGlobalView` (objeto de leitura que delega a `store.read`, nao uma copia do mapa); variaveis de zone (`event`) visiveis dentro de `runWithStacActionVars` mesmo apos `await`; store de tela e descartado ao remover o widget (`listenable` deixa de notificar).
- [ ] **Step 2:** Rodar -> FAIL. **Step 3:** Implementar. **Step 4:** PASS + analyze/format.
- [ ] **Step 5:** `git commit -m "feat: add state scopes and action variables"`.

**Plano de testes:** widget tests com `harness.dart`. **Revisao:** `StacScope.of` nao pode registrar dependencia no InheritedWidget do estado (so nos locais se necessario); sem vazamento de notifiers apos dispose.

---

### Task 4: Camada de binding, widget reativo, envelope e execucao de actions [CONCLUIDA]

**Dificuldade:** complexo (nucleo do plano). **Depende de:** T3.

**Files:**
- Create: `packages/stac/lib/src/state/stac_binding.dart`, `stac_reactive.dart`, `stac_envelope.dart`
- Modify: `packages/stac/lib/src/framework/stac_service.dart` (`fromJson`, `fromStacWidget`, `onCallFromJson`)
- Test: `packages/stac/test/state/binding_test.dart`, `reactive_widget_test.dart`

**Interfaces:**
- Consumes: T1, T2, T3.
- Produces:
```dart
class StacBinding {
  static bool isBinding(Object? v);                                  // D3
  static bool hasBindings(Map<String, dynamic> json, {required bool isAction}); // respeita D2
  static Set<String> dependenciesOf(Map<String, dynamic> json, {required bool isAction});
  static dynamic resolve(dynamic json, StacScope scope, {required bool isAction}); // copia com bindings trocados por valores; D2 decide o que pular; resolucao profunda em chaves de dado de action
}
class StacReactive extends StatelessWidget { // ListenableBuilder(Listenable.merge(...)) + build(context, resolvedJson)
  const StacReactive({required Map<String, dynamic> json, required Widget Function(BuildContext, Map<String, dynamic>) build});
}
```
- Comportamento em `StacService.fromJson(json, context)` (e `fromStacWidget`, que deve delegar ao mesmo caminho): (1) legacy `resolveVariablesInJson` continua primeiro; (2) `StacEnvelope.apply(json)`: se o tipo nao for `visibility`/`sliverVisibility`, `visible` (bool ou binding) false -> `SizedBox.shrink()`; chave `bind` e reescrita conforme D9 para a propriedade de valor do widget (tabela `bindTarget`: `checkBox/switch/slider -> value`, `radioGroup -> groupValue`, `radio -> groupValue` do grupo (ver T8), `textField/textFormField -> initialValue`, `dropdownMenu -> initialSelection`; tipo fora da tabela: `bind` ignorado + log); (3) se `StacBinding.hasBindings(json)` -> `StacReactive`, senao fluxo atual. `enabled` por envelope: ponto de extensao `StacEnvelope.disableStrategy[type]` (preenchido na T10); avalie `enabled` aqui apenas passando adiante.
- Comportamento em `onCallFromJson`: (1) se houver `condition` (bool ou binding): avalia agora; falsa/invalida (D6) -> nao executa, retorna `null`; (2) `StacBinding.resolve(..., isAction: true)` com `StacScope.of(context)`; (3) segue para `getModel`/`onCall`. Remover `condition` do JSON antes do model (models ignoram campo desconhecido; ok).
- Rebuild: dependencia declarada so por chaves de store; chave inexistente -> sem listenable, valor `null`.

- [ ] **Step 1:** Testes unitarios de `StacBinding`: `isBinding`; widget `{"type":"column","children":[{"type":"text","data":{"$state":"a"}}]}` -> `hasBindings(column)==false` (filho pulado), `hasBindings(text)==true`; action `setValue`-like com `values` contendo `{"type":"x"}` literal em chave de dado e resolvido por inteiro; resolucao profunda de `{"n":{"$state":"a"},"l":[{"$expr":"1+1"}]}` -> `{"n":..,"l":[2]}`.
- [ ] **Step 2:** Testes de widget (harness; estado da tela injetado via `StacStateScope` manual ate a T6): texto com `$expr` redesenha quando `store.write` muda a chave (um `pump`, uma unica reconstrucao com `batch`); `visible: {"$expr":"total == 10"}` esconde/mostra; `visible` com expressao invalida -> escondido + log; `condition` falsa impede action (usar action stub registrada no teste); mudanca de tema (`ThemeData` trocado) com binding ativo continua resolvendo cores (CLAUDE.md: reparse com `context` atual).
- [ ] **Step 3:** Rodar -> FAIL. **Step 4:** Implementar. **Step 5:** PASS; rodar tambem os testes existentes (`cd packages/stac && flutter test`) e `cd stac_playground && flutter test` (regressao). analyze/format.
- [ ] **Step 6:** `git commit -m "feat: resolve state bindings and rebuild widgets reactively"`.

**Plano de testes:** unitario + widget (acima) + regressao completa. **Revisao:** garantir que JSON sem bindings segue exatamente o caminho antigo (nenhum custo/efeito colateral); `StacReactive` nao copia filhos; sem `setState` durante build; revisar a regra D2 contra widgets com sub-mapas que tem `type` (ex.: modelos de foundation) para evitar pular dados legitimos.

---

### Task 5: Actions de mutacao (fase 1)

**Dificuldade:** medio. **Depende de:** T4. **Paralela com:** T6.

**Files:**
- Create (stac_core, cada uma com `.g.dart`): `packages/stac_core/lib/actions/{set_state,increment_state,toggle_state,reset_state,append_state}/stac_*.dart`; `ActionType` ganha `setState, incrementState, decrementState, toggleState, resetState, appendState` (exportar em `actions.dart`).
- Create (stac): `packages/stac/lib/src/parsers/actions/stac_{set_state,increment_state,decrement_state,toggle_state,reset_state,append_state}/..._parser.dart` (+ barrel) e registrar em `_actionParsers` de `stac_service.dart`.
- Test: `packages/stac/test/state/mutation_actions_test.dart`

**Interfaces (JSON, chaves aceitam prefixo `global.`):**
- `{"actionType":"setState","values":{"k":<valor|binding>, ...}}` — todas as chaves gravadas dentro de `store.batch` (um rebuild).
- `{"actionType":"incrementState","key":"k","by":1,"min":null,"max":null}` e `decrementState` idem (D8).
- `{"actionType":"toggleState","key":"k"}` (nao-bool -> log, no-op).
- `{"actionType":"resetState","keys":["a","global.b"]}`; sem `keys` = estado inteiro da tela. (Apagar persistido: ponto de extensao `StacGlobalState.onReset(key)` usado na T19.)
- `{"actionType":"appendState","key":"k","value":<valor>}` grava lista nova (chave `null` ou nao-lista -> log e no-op).
- Cada parser delega a `StacScope.of(context).write(...)`/`storeFor`; modelos DSL em stac_core com `Object?` para campos bindaveis (D16) e `StacBinding` helper em `packages/stac_core/lib/core/stac_binding.dart`.

- [ ] **Step 1:** Testes (harness): contador (`incrementState` com `max:10` clampa e texto `$expr` acompanha); `setState` com varias chaves = 1 rebuild (contar builds com um widget probe); `toggleState`; `appendState` cria copia (lista antiga referenciada nao muda); `resetState` por chaves e total; escrita em `global.x` reflete em widget que le `global.x`; escrita em chave nao declarada nao lanca e loga; `condition` em sequencia dentro de `multiAction` (segunda action ve valor da primeira).
- [ ] **Step 2:** Rodar -> FAIL. **Step 3:** Criar modelos, `melos run build`, parsers, registro. **Step 4:** PASS. **Step 5:** `git commit -m "feat: add state mutation actions"`.

**Plano de testes:** widget tests acima + `melos run analyze`. **Revisao:** `.g.dart` gerados e commitados; nomes de campo conferidos contra este plano; nenhum parser muta lista in-place.

---

### Task 6: Ligacao com a tela (blocos `state`/`globalState`/`onInit`, reload, `conditional`, `text`)

**Dificuldade:** medio. **Depende de:** T4. **Paralela com:** T5.

**Files:**
- Modify: `packages/stac/lib/src/framework/stac_service.dart` (em `fromJson`: no com chave `state`/`globalState`/`onInit` -> envolver em `StacStateScope`); `packages/stac/lib/src/framework/stac.dart` (`_StacView` vira `StatefulWidget` que busca uma vez, `didUpdateWidget` refaz se `routeName` mudar; `KeyedSubtree(key: ObjectKey(snapshot.data))` ao redor do resultado — D11).
- Modify: `packages/stac_core/lib/widgets/conditional/stac_conditional.dart` (`condition` passa a `dynamic`; regenerar) e `packages/stac/.../stac_conditional_parser.dart` (bool -> usa direto; String -> `ExpressionResolver` legado como hoje).
- Modify: `StacStateScope` (T3) para: declarar `initialState` (valores podem ter bindings sobre `params`/`global`, resolvidos uma vez), declarar `globalState` via `StacGlobalState` (D12, idempotente), executar `onInit` uma vez em `addPostFrameCallback` (action ou lista -> `multiAction` sync).
- Test: `packages/stac/test/state/screen_state_test.dart`

**Contexto:** `fromJson` e chamado para todo widget e `resolveVariablesInJson` copia mapas a cada chamada, por isso a chave do `StacStateScope` e por **conteudo** (D11). O no que declara `state` e tipicamente o root da tela (scaffold); `state` aninhado cria sub-store (Plano 9). Nao ha colisao: nenhum model existente tem campo `state`/`globalState`/`onInit` (verificado).

- [ ] **Step 1:** Testes: tela com `state:{total:0}`, botao `incrementState`, texto `$expr 'Total: ' + total`, conditional `{"$expr":"total == 10"}` + botao `enabled`... (enabled so na T10; aqui usar `visible`); `globalState` idempotente (montar duas telas, valor mudado na primeira sobrevive ao `globalState` inicial da segunda); `onInit` roda 1x e roda de novo apos recarga; rebuild do pai (trocar `ThemeData`) **nao** reinicializa `total`; nova resposta do servidor (novo `ObjectKey`) reinicializa; `_StacView` busca uma unica vez em varios rebuilds (contar chamadas do `Dio` fake); chave de tela chamada `global` e rejeitada.
- [ ] **Step 2:** Rodar -> FAIL. **Step 3:** Implementar. **Step 4:** PASS + regressao completa. **Step 5:** `git commit -m "feat: wire screen state blocks and onInit"` (corpo: porque `_StacView` deixou de refazer fetch a cada build).

**Plano de testes:** widget + regressao dos exemplos do playground (`cd stac_playground && flutter test`). **Revisao:** mudanca de comportamento de `_StacView` (fetch unico) deve ser conferida contra a estrategia de cache (`networkFirst`) e documentada no commit; chave de conteudo nao pode colidir entre dois `state` identicos em telas diferentes (escopos distintos por posicao na arvore, ok).

---

### Task 7: Docs e playground da Fase 1

**Dificuldade:** simples. **Depende de:** T5, T6.

**Files:**
- Create: `docs/concepts/state.mdx` (estado de tela, global em memoria, ciclo de vida), `docs/concepts/bindings_and_expressions.mdx` (sintaxe `$state`/`$expr`, gramatica, precedencia, funcoes, regras de tipo/null, fallbacks D6), `docs/concepts/reactivity.mdx` (o que redesenha e quando; convivio com `setValue`/`{{var}}`/`getFormValue`), `docs/actions/{set_state,increment_state,decrement_state,toggle_state,reset_state,append_state}.mdx`
- Modify: `docs/docs.json` (grupos Concepts e Actions), `docs/widgets/{text,conditional}.mdx` (bindings, `visible`)
- Create: playground `stac_playground/lib/dsl/state_counter.dart`, `assets/json/state_counter_example.json`, entrada em `lib/data/component_entries.dart`; `dsl_to_json.dart` so se o DSL usar construcoes ainda nao suportadas (manter `test/dsl_to_json_test.dart` verde).
- Test: `packages/stac/test/state/docs_examples_test.dart` (cria o helper reutilizado na T20: extrai blocos ` ```json ` das paginas novas, `jsonDecode`, e para os que tem `type` renderiza com o harness sem erros logados).

- [ ] **Step 1:** Escrever paginas no padrao de `docs/actions/set_value.mdx` (ingles, tabela de propriedades, `<CodeGroup>` Dart/JSON). **Step 2:** helper de teste de exemplos -> FAIL ate exemplos validos. **Step 3:** Corrigir exemplos -> PASS. **Step 4:** `cd stac_playground && flutter test && flutter build web`. **Step 5:** `git commit -m "docs: document state, bindings and mutation actions"`.

**Plano de testes:** teste de exemplos + playground. **Revisao:** cada campo documentado existe no codigo (conferir contra as Interfaces das T5/T6).

---

### Task 8: `bind`/`value`/`onChanged` em checkBox, switch, slider, radio, radioGroup

**Dificuldade:** medio. **Depende de:** T4, T5, T6. **Paralela com:** T9, T10.

**Files:**
- Modify: parsers de `stac_check_box`, `stac_switch`, `stac_slider`, `stac_radio`, `stac_radio_group` em `packages/stac/lib/src/parsers/widgets/`; `StacEnvelope.bindTarget` (T4) para radio/radioGroup.
- Test: `packages/stac/test/state/inputs_toggle_test.dart`

**Contexto:** todos tem `StatefulWidget` interno com estado proprio e fazem `Stac.onCallFromJson(model.onChanged...)` sem passar o valor. Mudar para `runWithStacActionVars({'event': {'value': novoValor}}, () => Stac.onCallFromJson(...))` (D9). `didUpdateWidget` ja resincroniza `value`; manter. Com `bind`, o store e a unica fonte da verdade: ao reescrever o JSON (T4) o `value` chega via binding e o `didUpdateWidget` aplica. Para `radio` dentro de `radioGroup`, `bind` fica no `radioGroup` (`groupValue`); `radio` individual com `bind` e erro logado.

- [ ] **Step 1:** Testes: checkbox `bind:"aceito"` + botao com `visible` por `aceito` (Plano caso 1); toque no checkbox grava `aceito` antes do `onChanged` (a action do `onChanged` le o valor novo — usar `setState` que copia `aceito` para `copia`); alteracao externa (`setState`) atualiza o checkbox sem disparar `onChanged`; switch mostra/esconde bloco; slider; radioGroup escolhe qual formulario aparece; `value` somente leitura + `onChanged` com `toggleItem`-like stub.
- [ ] **Step 2:** FAIL. **Step 3:** Implementar. **Step 4:** PASS + regressao. **Step 5:** `git commit -m "feat: bind state to toggle and choice inputs"`.

**Plano de testes:** widget tests acima. **Revisao:** nenhum parser deixa estado interno divergir do store (dupla fonte de verdade, Plano 10); `onChanged` nao dispara por mudanca externa.

---

### Task 9: `bind`/`onChanged` em textField, textFormField, dropdownMenu

**Dificuldade:** complexo (controller, foco, cursor). **Depende de:** T4, T5, T6. **Paralela com:** T8, T10.

**Files:**
- Modify: `stac_text_field`, `stac_text_form_field`, `stac_dropdown_menu` parsers; `packages/stac_core/lib/widgets/text_field/stac_text_field.dart` (verificar `maxLength`, `keyboardType`, `inputFormatters`/so-digitos; `maxLength` e `keyboardType` ja existem; se faltar `inputFormatters`, adicionar reutilizando `lib/src/utils/input_formatters.dart` como no `dropdownMenu`; regenerar).
- Test: `packages/stac/test/state/inputs_text_test.dart`

**Contexto:** o texto digitado deve gravar na chave a cada mudanca (`event.value` = texto) e a escrita externa so atualiza o `TextEditingController` quando `controller.text != novoValor` (preservando selecao). `didUpdateWidget` compara `initialValue` anterior x novo (CLAUDE.md: resync em `didUpdateWidget`). Dropdown: `event.value` = valor selecionado (`onSelected` do model).

- [ ] **Step 1:** Testes: digitar "abc" grava `busca`; cursor no meio do texto e foco permanecem apos a gravacao (digitar no meio, conferir `selection.baseOffset`); `setState` externo muda o texto exibido; `onChanged` com `condition` `length(busca) >= 3` so dispara a partir de 3 caracteres; `enabled` nativo por binding desabilita; `maxLength`/so-digitos respeitados; dropdown `bind` troca selecao.
- [ ] **Step 2:** FAIL. **Step 3:** Implementar. **Step 4:** PASS + regressao. **Step 5:** `git commit -m "feat: bind state to text and dropdown inputs"`.

**Plano de testes:** widget tests (inclui o caso de cursor, Review Focus 1). **Revisao:** nenhum loop gravar->rebuild->gravar; `TextEditingController` descartado.

---

### Task 10: `enabled` e acao de toque por binding

**Dificuldade:** medio. **Depende de:** T4. **Paralela com:** T8, T9.

**Files:**
- Modify: `packages/stac/lib/src/state/stac_envelope.dart` (preencher `disableStrategy`), possivel ajuste nos parsers que nao tratam `onPressed == null`.
- Test: `packages/stac/test/state/enabled_test.dart`

**Contexto:** widgets com `enabled` nativo (textField, textFormField, dropdownMenu, radio, listTile, backdropFilter, toolTip) apenas recebem o valor resolvido. Para os demais com acao de toque, `enabled: false` remove do JSON as chaves de acao do tipo toque, o que desabilita visualmente botoes Flutter (callback `null`): `elevatedButton, filledButton, outlinedButton, textButton, iconButton, floatingActionButton, inkwell, gestureDetector, chip, checkBox, switch, slider` -> chaves `onPressed, onTap, onLongPress, onDoubleTap, onChanged, onChangeEnd, onSelected, onDeleted`. Widget sem nenhuma dessas chaves: `enabled` ignorado + `Log.d`. `visible` em `visibility`/`sliverVisibility` continua sendo o campo nativo.

- [ ] **Step 1:** Testes: botao `enabled:{"$expr":"aceito"}` fica desabilitado ate o checkbox marcar (Plano caso 1) — `tester.widget<ElevatedButton>().onPressed == null`; contador: "+" desabilitado com `total >= 10`; `enabled: false` literal; `inkwell` inerte; `enabled` com expressao invalida -> desabilitado (D6).
- [ ] **Step 2:** FAIL. **Step 3:** Implementar. **Step 4:** PASS. **Step 5:** `git commit -m "feat: enable and disable tappable widgets by binding"`.

**Plano de testes:** widget tests. **Revisao:** conferir cada widget da lista acima contra seu model (`grep "final StacAction? on" stac_core/lib/widgets/<w>/`) e que o estilo "desabilitado" aparece.

---

### Task 11: Docs da Fase 2

**Dificuldade:** simples. **Depende de:** T8, T9, T10.

**Files:**
- Modify: `docs/widgets/{check_box,switch,slider,radio,radio_group,text_field,text_form_field,dropdown_menu,elevated_button,...}.mdx` (secao `bind`, `value`, `onChanged`, `event.value`, `visible`, `enabled`), `docs/concepts/reactivity.mdx`, `docs/concepts/bindings_and_expressions.mdx` (tabela de variaveis em escopo: `event`).
- Create: `docs/guides/state_recipes.mdx` (receitas: contador, habilitar botao por checkbox, mostrar/esconder por switch, radio escolhe formulario); registrar em `docs/docs.json`.
- Test: estender `docs_examples_test.dart` para as paginas novas.

- [ ] Steps: escrever, rodar `docs_examples_test.dart`, `flutter build web` do playground se tocar nele, `git commit -m "docs: document input bindings and enabled"`.

**Revisao:** receitas executaveis no teste.

---

### Task 12: `networkRequest` com estado

**Dificuldade:** complexo. **Depende de:** T8, T9 (cenario 14.1). **Paralela com:** T13.

**Files:**
- Modify: `packages/stac_core/lib/actions/network_request/stac_network_request.dart` (+ `.g.dart`): novos campos `onStart`, `onSuccess`, `onError`, `onFinally` (`List<Map<String,dynamic>>?`), `requestKey` (`String?`), `bodyFromState` (`List<String>?`); `ActionType.cancelRequest` + `packages/stac_core/lib/actions/cancel_request/`.
- Modify: `packages/stac/lib/src/parsers/actions/stac_network_request/stac_network_request_parser.dart`, `packages/stac/lib/src/services/stac_network_service.dart` (aceitar `CancelToken`), `StacStateScope` (`StacRequestRegistry`, T3).
- Create: `packages/stac/lib/src/parsers/actions/stac_cancel_request/...` e registrar.
- Test: `packages/stac/test/state/network_state_test.dart`, `scenario_input_request_test.dart`

**Interfaces/semantica:**
- `url`, `queryParameters`, `headers`, `body` ja chegam resolvidos (T4, avaliados no disparo, resolucao profunda).
- Ordem: `onStart` -> request -> (2xx: `onSuccess`; senao/falha/timeout: `onError`) -> `onFinally`. Em cada uma dessas listas a variavel `response` = `{body, statusCode, headers}` (`body` decodificado de JSON quando for String JSON) via `runWithStacActionVars`. Listas executadas em sequencia aguardando (sync true). O mecanismo legado `results[statusCode]` + `{{response.x}}` continua funcionando e roda **apos** as listas novas se ambos estiverem presentes.
- `requestKey`: nova request com a mesma chave cancela o `CancelToken` anterior; resposta de token cancelado e descartada (nenhuma lista executa, `onFinally` da request antiga tambem nao). `cancelRequest {requestKey}` cancela. Request pendente cuja tela foi descartada (`!context.mounted`) e descartada.
- `bodyFromState`: body = mapa `{chave: valor}` das chaves listadas, **excluindo** chaves `secure` (consulta `StacGlobalState.store.isSecure(key)`; adicionar `bool isSecure(String)` na interface, default `false` ate a T19) e ignorando body explicito conflitante (se ambos, body explicito vence + log).

- [ ] **Step 1:** Testes com `FakeDioAdapter`: ciclo completo atualiza varias chaves com 1 rebuild (`onSuccess` com `setState` de varias chaves via `response.body`); 200 com `{"erro":true}` tratado por `condition` sobre `response.body.erro`; status 500 -> `onError`; `onFinally` sempre; **resposta atrasada nao sobrescreve** a mais nova (duas requests com `requestKey`, a primeira responde depois); `cancelRequest`; tela descartada antes da resposta nao lanca; `bodyFromState` exclui chave `secure` (stub de `isSecure`).
- [ ] **Step 2:** Cenario 14.1 (`scenario_input_request_test.dart`, generico, sem dominio): textField `bind` -> `onChanged` com `condition length(campo) >= 3` -> request com `requestKey` -> preenche 2 campos `bind` com `enabled` por flag `veioDoServidor` -> indicador `visible` por `carregando`, erro `visible` por `erro` -> alterar o input limpa (`resetState`), cancela e refaz.
- [ ] **Step 3:** FAIL. **Step 4:** Implementar (`melos run build`). **Step 5:** PASS + regressao. **Step 6:** `git commit -m "feat: add state-aware networkRequest lifecycle"`.

**Plano de testes:** unitario/widget acima. **Revisao:** `results` legado intacto (teste existente ou novo de regressao); sem vazamento de tokens; Review Focus 2 coberto.

---

### Task 13: Navegacao com parametros e retorno de resultado

**Dificuldade:** complexo. **Depende de:** T6. **Paralela com:** T12.

**Files:**
- Modify: `packages/stac_core/lib/actions/navigate/stac_navigate_action.dart` (+ `.g.dart`): `params` (`Map<String,dynamic>?`), `onResult`, `onCancel` (`Map<String,dynamic>?` = action), `result` vira `Object?`, `bool hasResult` derivado de `json.containsKey('result')` (override de `getModel` no parser).
- Modify: `packages/stac/lib/src/parsers/actions/stac_navigate_action/stac_navigate_action_parser.dart`; `stac_dialog_action` e `stac_modal_bottom_sheet_action` parsers.
- Create: `packages/stac/lib/src/state/stac_pop_result.dart` (`class StacPopResult { final Object? value; }`).
- Test: `packages/stac/test/state/navigation_state_test.dart`

**Semantica (D10):**
- `params` (resolvido no toque, snapshot por copia profunda) -> a rota destino e embrulhada em `StacLocalScope(vars: {'params': snapshot})`; vale para `widgetJson/request/assetPath/routeName` e `pushNamed*` (neste caso via `arguments` ja existentes: `params` e entregue embrulhando o builder quando o widget e conhecido; para `pushNamed` o params entra em `arguments['__stacParams']` e o `StacApp`/rota do app e responsabilidade do app — documentar a limitacao).
- `pop` (`navigationStyle: pop`): `result` presente -> `Navigator.pop(context, StacPopResult(valorResolvido))`; ausente -> `Navigator.pop(context)`.
- Origem: se `onResult`/`onCancel` existem, aguardar o Future do push; `StacPopResult` -> se `context.mounted` e escopo vivo, `runWithStacActionVars({'result': value}, () => run(onResult))` com o `context` da origem; `null` -> `onCancel` (se houver). Origem descartada -> descartar sem erro. Retorno do `onCall` para chamadores legados = valor desembrulhado.
- `dialog` e `modalBottomSheet`: conteudo e construido sob o Navigator, fora do escopo da tela; capturar `StacScope` da origem e reprovisionar (`StacStateScope.value`/`StacLocalScope`) em volta do conteudo para bindings dentro do dialog/sheet enxergarem estado da tela.

- [ ] **Step 1:** Testes: A seleciona produto e navega com `params`; B mostra nome/preco via `params.*` sem HTTP; mudar estado de A depois nao altera B; `pop` com `result` objeto literal com bindings -> A `appendState`/`setState` via `onResult` e observadores redesenham; voltar pelo botao do sistema (`tester.pageBack()`) nao executa `onResult` (executa `onCancel`); `pop` com `result: null` executa `onResult`; fluxo repetido 3x sem sobras (estado novo em B a cada abertura); A descartada antes do pop do B (usar `pushReplacement` na origem) nao lanca; reatividade global entre telas empilhadas (`global.x` alterado em B atualiza texto em A por baixo); dialog le `visible` de estado da tela.
- [ ] **Step 2:** FAIL. **Step 3:** Implementar (`melos run build`). **Step 4:** PASS + regressao. **Step 5:** `git commit -m "feat: pass params and results between screens"`.

**Plano de testes:** widget tests (acima). **Revisao:** Review Focus 4; compatibilidade de `navigate` legado (`result` Map continua funcionando); dialog scope sem vazar listeners.

---

### Task 14: Docs da Fase 3

**Dificuldade:** simples. **Depende de:** T12, T13.

**Files:** Modify `docs/actions/{network_request,navigate}.mdx`; Create `docs/actions/cancel_request.mdx`; Modify `docs/concepts/{state,navigation_in_stac}.mdx` (params, `onResult`, `onCancel`, estado global entre telas); add receitas em `docs/guides/state_recipes.mdx` (input que dispara request, estado global compartilhado, lista alimentada por navegacao com resultado); `docs/docs.json`.
- [ ] Escrever, `docs_examples_test.dart`, `git commit -m "docs: document network state and navigation results"`.

---

### Task 15: Templates de lista (`items`/`as`/`indexAs`/`itemTemplate`)

**Dificuldade:** complexo (maior risco, Plano 10). **Depende de:** T4, T6. **Paralela com:** T12, T13.

**Files:**
- Modify (stac_core, regenerar): `stac_list_view.dart`, `stac_grid_view.dart`, `stac_page_view.dart`, `stac_sliver_list.dart`, `stac_sliver_grid.dart`: novos campos `items` (`Object?`/`List<dynamic>?`), `as` (`String?`, padrao `item`), `indexAs` (`String?`, padrao `index`), `itemTemplate` (`StacWidget?`). `children` legado continua valido; com `itemTemplate`+`items`, o template vence.
- Modify: parsers correspondentes em `packages/stac/lib/src/parsers/widgets/`.
- Test: `packages/stac/test/state/list_template_test.dart`

**Semantica:** `items` chega resolvido (binding no widget pai, T4) como lista (nao-lista/`null` -> lista vazia + log). Para cada indice: `Builder` -> `StacLocalScope(vars: {as: item, indexAs: index}, child: itemTemplate.parse(context))` (mesma tecnica de CLAUDE.md: parse no contexto do proprio item para temas). Escopo lexico: listas aninhadas usam `as` distintos; repetir nome sombreia. Identidade por indice (D15). Itens snapshot do instante do rebuild.

- [ ] **Step 1:** Testes: lista do estado renderiza N itens; `appendState` redesenha; `removeFromState`-stub (setState com lista nova) remove; lista aninhada com `as:"pai"` e `as:"filho"` ve ambos; `visible` sobre `length(lista) == 0` mostra irmao vazio; rolagem de lista longa nao reconstroi tudo (builder lazy: contar chamadas do `itemBuilder`); troca de tema atualiza itens.
- [ ] **Step 2:** FAIL. **Step 3:** Implementar. **Step 4:** PASS + regressao. **Step 5:** `git commit -m "feat: render list items from state with item templates"`.

**Plano de testes:** widget. **Revisao:** `ListView.separated` legado intacto; sem descer em `itemTemplate` durante a resolucao do pai (D2, o template resolve com o escopo do item).

---

### Task 16: `removeFromState`, `toggleItem` e cenario 14.2

**Dificuldade:** medio. **Depende de:** T5, T13, T15.

**Files:**
- Create (stac_core + `.g.dart`): `actions/remove_from_state/`, `actions/toggle_item/`; `ActionType.removeFromState, toggleItem`; parsers em `packages/stac/lib/src/parsers/actions/` e registro.
- Test: `packages/stac/test/state/collection_actions_test.dart`, `scenario_list_result_test.dart`

**Interfaces:** `{"actionType":"removeFromState","key":"k","index":<n|binding>}` ou `"value":<v>` (igualdade profunda, primeira ocorrencia); indice fora do intervalo = log + no-op. `{"actionType":"toggleItem","key":"k","value":<v>,"by":"campo"}`: adiciona se ausente, remove se presente; `by` define identidade quando itens sao objetos.

- [ ] **Step 1:** Testes unitarios das duas actions (copia nova; `by`; fora do intervalo). **Step 2:** Cenario 14.2 generico: A (lista + `visible` vazio) -> `navigate` com `onResult appendState` -> B (campo `bind`, opcoes com `value contains(selecionados, item, 'id')` e `onChanged toggleItem`, botao `enabled length(trim(campo)) > 0`, `pop` com objeto literal com bindings) -> A mostra item com lista aninhada -> repetir 2x -> remover por `index` -> botao de envio faz `networkRequest` com `body` = lista, desabilitado durante a chamada, limpa em sucesso e mantem em erro; voltar sem confirmar nao altera A. **Step 3:** FAIL. **Step 4:** Implementar, PASS. **Step 5:** `git commit -m "feat: add collection mutation actions and list-result scenario"`.

**Revisao:** o teste de cenario usa so nomes genericos (nenhuma regra de dominio).

---

### Task 17: Docs da Fase 4

**Dificuldade:** simples. **Depende de:** T16.
**Files:** Create `docs/actions/{remove_from_state,toggle_item}.mdx`; Modify `docs/widgets/{list_view,grid_view,page_view,sliver_list,sliver_grid}.mdx` (templates, `as`/`indexAs`, escopo lexico, identidade por indice), `docs/guides/state_recipes.mdx`, `docs/docs.json`.
- [ ] Escrever, `docs_examples_test.dart`, `git commit -m "docs: document list templates and collection actions"`.

---

### Task 18: Fase 5 — auditoria de propriedades e widgets restantes

**Dificuldade:** medio. **Depende de:** T15.

**Files:**
- Test: `packages/stac/test/state/binding_audit_test.dart`
- Modify: models/parsers que falharem na auditoria (regenerar).

**Contexto:** o mecanismo e generico (D1), entao a tarefa e provar a garantia "nenhuma propriedade deixa de reagir" e corrigir excecoes: propriedades cujo model decodifica o JSON de forma que descarta o valor resolvido (ex.: enums, cores tema vs `#hex`, `double` com `DoubleConverter`, campos `int`), widgets que leem `jsonData` bruto de filhos em estruturas especiais (tabs, bottom navigation, table, navigation view), e parsers que fazem `parse` de filho no `context` errado.

- [ ] **Step 1:** Teste de auditoria parametrizado: para cada tipo em `WidgetType` que o playground exemplifica (`stac_playground/assets/json/*_example.json`), escolher 1 propriedade escalar do exemplo, substituir por `{"$state":"p"}` com `p` igual ao valor original, renderizar, alterar `p` e conferir rebuild sem erro logado; lista de excecoes explicitas (com motivo) no proprio teste.
- [ ] **Step 2:** FAIL em ao menos alguns tipos; corrigir cada um (menor mudanca). **Step 3:** PASS + regressao + playground. **Step 4:** `git commit -m "feat: make remaining widget properties bindable"`.

**Revisao:** lista de excecoes revisada e documentada em `docs/concepts/reactivity.mdx`.

---

### Task 19: Fase 6 — persistencia e dados sensiveis

**Dificuldade:** complexo. **Depende de:** T2, T6, T12.

**Files:**
- Modify: `packages/stac/pubspec.yaml` (`flutter_secure_storage`), `stac_global_state.dart` (flags `persist`/`secure`, `isSecure`, `hydrate()`, gravacao agrupada por microtask, `onReset`), `stac_service.dart` (`initialize` aguarda `hydrate()` — D14), logging (mascarar valores `secure`), `StacStateScope` (declaracao com flags, D12/D13).
- Create: `packages/stac/lib/src/state/stac_state_persistence.dart` (`abstract class StacStatePersistence { Future<Map<String,String>> readAll(); Future<void> write(String k,String v); Future<void> delete(String k); }` + `SharedPrefsPersistence` com prefixo `stac_state.` e `SecurePersistence` sobre `flutter_secure_storage`, `NoopSecurePersistence` na web com `Log.w`).
- Test: `packages/stac/test/state/persistence_test.dart` (impls fake em memoria + `SharedPreferences.setMockInitialValues`).

**Semantica (Plano 5.1.2):** ordem de valor: memoria > persistido > inicial; valor persistido de chave nao declarada fica em `pending` e so aparece ao declarar; tipo incompativel com o inicial declarado -> descarta + usa inicial + log; gravacao em JSON a cada mudanca (rajadas coalescidas); `resetState` global restaura inicial e apaga persistido/seguro; `secure` implica `persist`; `secure+persist:false` -> aviso, ignora (D13); valores `secure` nunca em logs (mascarados `***`), nunca em `bodyFromState` (usa `isSecure` da T12) e nunca em `params` automaticamente; so chaves globais persistem (`persist` em chave de tela = log + ignorado).

- [ ] **Step 1:** Testes: reidratacao antes do primeiro frame (hydrate no `initialize`); prevalencia memoria>persistido>inicial; orfao nao exposto; tipo incompativel; reset apaga; `secure` vai para a impl segura e nao para SharedPreferences; log mascarado (capturar `Log`); `bodyFromState` exclui chave `secure`; header `Authorization` com `$expr 'Bearer ' + global.token` funciona; web (impl noop) nao grava.
- [ ] **Step 2:** FAIL. **Step 3:** Implementar. **Step 4:** PASS + `cd stac_playground && flutter build web` (CI) + `melos bootstrap`. **Step 5:** docs: Modify `docs/concepts/state.mdx` (persist/secure, ordem, limites), `docs/actions/reset_state.mdx`. **Step 6:** `git commit -m "feat: persist and secure global state keys"`.

**Revisao:** nenhuma via de vazamento de `secure` (logs, erros do Stac error widget que imprimem JSON — conferir `StacError.json`); dependencia nova aprovada para este fim.

---

### Task 20: Fase 7 — fechamento da documentacao

**Dificuldade:** medio. **Depende de:** todas.

**Files:**
- Create: `docs/concepts/state_reference.mdx` (pagina de referencia do contrato JSON): para cada elemento (`state`, `globalState`, `$state`, `$expr`, `bind`, `visible`, `enabled`, `condition`, `onInit`, `onChanged`, cada action nova, `networkRequest` estendido, `navigate`/`pop`, templates de lista): campos, tipo, obrigatorio/opcional, padrao, valores aceitos, semantica, ordem de avaliacao, erros e fallbacks (D6/D7/D8), exemplo JSON completo; gramatica e precedencia das expressoes; tabela de namespaces/variaveis em escopo (`global`, `params`, `result`, `response`, `event`, variaveis de template); secao "Limitacoes do v1" (DSL Dart so para actions/campos tipados; `pushNamed` e `params`; identidade de item por indice).
- Modify: `docs/docs.json` (navegacao), `docs/changelog.mdx`.
- Test: `docs_examples_test.dart` cobrindo todas as paginas novas.

- [ ] **Step 1:** Conferir cada campo documentado contra o codigo (`grep` nos models/parsers) e corrigir divergencias. **Step 2:** Rodar `docs_examples_test.dart` em todas as paginas -> PASS. **Step 3:** `melos run analyze && melos run format && cd packages/stac && flutter test && cd ../../stac_playground && flutter test && flutter build web`. **Step 4:** `git commit -m "docs: close state documentation with contract reference"`.

**Revisao:** o backend (derust) so precisa desta pagina para emitir o contrato; nenhuma regra de dominio nos exemplos.

---

## Self-Review

- Cobertura do Plano: 5.1 (T2,T6), 5.1.1 (T2,T6,T13), 5.1.2 (T19), 5.2 (T4,T8-T10,T18), 5.3 (T1), 5.4 (T5,T16), 5.5 (T12), 5.6 (T13), 5.7 (T6,T8,T9), 5.9 (T15), 7 fases e docs (T7,T11,T14,T17,T19,T20), cenarios 14.1 (T12) e 14.2 (T16). Itens abertos do Plano 11 fechados em D6, D13, D14, D15, D16/D17, e propriedades de textField na T9.
- Tipos: `StacScope`, `StacStateStore`, `StacExpression`, `runWithStacActionVars`, `StacPopResult`, `StacRequestRegistry` usados com a mesma assinatura nas tasks consumidoras; `isSecure` introduzido na T12 e preenchido na T19.
- Risco conhecido: D1/D2 (regra de pulo de filhos) e a task T18 (auditoria) sao os pontos que mais podem revelar excecoes em widgets com models especiais.
