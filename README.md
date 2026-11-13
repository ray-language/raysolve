# raysolve

Un resolutor de dependencias semver para el `ray.toml` de [raylang](https://github.com/ray-language/raylang),
con el algoritmo **PubGrub** (el de `pub` de Dart y `pubgrub-rs`): busca versiones que cumplan todos
los requisitos y, cuando no las hay, explica **por qué** en frases que se pueden seguir.

```
$ raysolve resolve fixtures/projects/deep.toml --index fixtures/ecosystem
Because agent <0.2.0 depends on mcp ^0.2.0 and mcp <0.3.0 depends on net ^0.13.0, agent <0.2.0 requires net ^0.13.0.
And because bot depends on agent ^0.1.0, bot requires net ^0.13.0.
So, because bot depends on net ^0.14.0, version solving failed.
raysolve: no solution for bot (2 decisions, 6 derivations, 2 conflicts, 9 incompatibilities, 1.52 ms)
```

```
$ raysolve resolve fixtures/projects/app.toml --index fixtures/ecosystem
# app 0.1.0: 11 packages in 6.43 ms (12 decisions, 12 derivations, 0 conflicts, 18 incompatibilities)
agent    = "0.2.1"
cron     = "0.2.1"
db       = "0.7.2"
elements = "0.12.0"
llm      = "0.2.1"
mcp      = "0.3.1"
net      = "0.14.1"
oidc     = "0.3.0"
tz       = "0.2.0"
web      = "0.7.0"
yaml     = "0.1.1"
# not from the index: ui = "path:../ui"
```

Es una app de *dogfooding*: su razón de ser es ejercitar la parte de raylang que las demás apps
apenas tocan — **traits propios, genéricos con bounds, structs y enums genéricos, `dyn Trait`,
iteradores propios, `std/collections/dict` y `set` con claves de usuario, `impl Ord` a mano,
`std/sort`, alias `type`** — y anotar lo que se rompe (ver [Hallazgos](#hallazgos-de-dogfood)).

## Uso

```
raysolve resolve [ray.toml] --index RUTA [--pre] [--yanked] [--json] [--tree]
raysolve why PAQUETE [ray.toml] --index RUTA
raysolve outdated [ray.toml] --index RUTA
raysolve bench [--packages N] [--seed N] [--rounds N]
raysolve gen DIR [--packages N] [--seed N]
```

| Orden | Qué hace |
|---|---|
| `resolve` | resuelve `[dependencies]` y escribe el lock (salida 0); si no hay solución, la explicación (salida 1). `--tree` añade el árbol de derivación, `--json` da el lock en JSON |
| `why` | por qué un paquete está en la solución: los caminos desde el proyecto, del más corto al más largo, con el requisito de cada salto |
| `outdated` | por dependencia directa: requisito, versión resuelta, la más nueva compatible y la más nueva que existe (salida 1 si el requisito deja fuera la más nueva) |
| `bench` | resuelve índices generados (aleatorios y "difíciles") y mide el mejor de N |
| `gen` | escribe un índice generado como directorio de JSON + su `ray.toml`, para probar la lectura de disco |

`--index` acepta un directorio (`<paquete>.json` por paquete) o un archivo `index.json`; repetido,
apila índices (el primero que conoce un paquete responde por él). Sin `--index` se usa
`$RAYSOLVE_INDEX`. Las dependencias `path:` y `git+` no están en ningún índice: se listan aparte.

Las **pre-versiones** (`1.0.0-rc.1`) solo entran si el requisito de ese paquete en el `ray.toml`
nombra una, o con `--pre`; aun así, una versión estable gana a una pre-versión. Las versiones
**retiradas** (`"yanked": true`) solo entran con `--yanked`.

### Requisitos

| Forma | Significa |
|---|---|
| `^1.2.3`, `1.2.3`, `1.2` | caret, como Cargo: `>=1.2.3, <2.0.0`; `^0.14` es `<0.15.0`; `^0.0.3` es `<0.0.4` |
| `~1.2.3`, `~1.2`, `~1` | hasta la siguiente menor (`~1` hasta la siguiente mayor) |
| `=1.2.3`, `=1.2` | exacta, o todo `1.2.*` |
| `>=`, `>`, `<`, `<=` | comparadores; las versiones parciales se rellenan con ceros (`>1.2` es `>=1.3.0`) |
| `a, b` | los dos a la vez |
| `a \|\| b` | cualquiera de los dos |
| `1.x`, `1.2.*`, `*` | comodines |

### El índice

```json
{ "name": "web",
  "versions": {
    "0.7.0": { "deps": { "net": "^0.14.0" } },
    "0.7.1": { "deps": { "net": "^0.14.0" }, "yanked": true } } }
```

`fixtures/ecosystem/` imita el ecosistema de raylang — `net`, `web`, `rpc`, `db`, `tz`, `cron`,
`mcp`, `llm`, `agent`, `oidc`, `yaml`, `elements` — con varias versiones cada uno (**números y
dependencias inventados**, con la forma de los reales). `fixtures/ecosystem.json` es lo mismo en un
solo archivo, y `fixtures/projects/` tiene cinco proyectos: uno que resuelve, dos conflictos (directo y
a dos saltos), una pre-versión pedida por nombre y un paquete inexistente.

## Cómo está hecho

| Módulo | Qué |
|---|---|
| `version.ray` | `trait Version` (`is_prerelease`, `label`, `caret_upper`), implementado por `SemVer` y por `int` |
| `semver.ray` | `SemVer` con `@derive(Eq, Hash, Show)` e **`impl Ord` a mano** (precedencia semver 2.0.0 §11, pre-versiones incluidas) |
| `range.ray` | `Range<V>`: unión de intervalos `Seg<V>` con `Bound<V>`; intersección, complemento, unión, inclusión. **`InRange<V>`**, un iterador propio que filtra una lista ordenada por un rango |
| `req.ray` | la sintaxis de requisitos de `ray.toml` → `Range<SemVer>` |
| `pubgrub.ray` | el resolutor, **genérico** en el paquete `P` y la versión `V`: `Term<P, V>`, `Incompat<P, V>`, `Outcome<P, V>`; propagación unitaria, aprendizaje de conflictos y salto atrás; las dependencias de versiones consecutivas iguales se agrupan en una sola incompatibilidad (`web >=0.6.0 depends on net ^0.11.0`), como hace pub |
| `explain.ray` | el grafo de derivación en frases numeradas; **`TreeWalk<P, V>`**, un iterador en preorden para `--tree` |
| `index.ray` | `trait Source` usado como **`dyn Source`**: directorio, archivo, memoria y `Layered { layers: [dyn Source] }` |
| `resolve.ray` | adapta un `dyn Source` al resolutor: un `Provider<P, V>` de dos closures que comparten cachés (un `Dict<PkgVer, …>` con clave propia derivada) |
| `graph.ray` | **`Paths`**, iterador perezoso de caminos simples (para `why`) |
| `synth.ray` | índices sintéticos con un LCG propio en `u64` (mismos números en VM y nativo) |

El resolutor no sabe nada de semver: los tests lo usan con versiones `int` y paquetes `string`, y
la CLI con `SemVer`. Como raylang no tiene supertraits ni traits genéricos en los bounds, el
bound se escribe entero (`V: Ord + Hash + Eq + Show + Version`) y el índice llega como un struct
de closures en vez de un `S: Source<V>`.

## Rendimiento

`make bench` / `make bench-vm`: índices generados de 100, 200 y 400 paquetes, tres semillas por
tamaño, el mejor de 3 (raylang 1.27.95, Apple Silicon, máquina compartida con carga ~12).

| Índice | Resultado | Decisiones | Conflictos | VM | Nativo `--release` |
|---|---|---:|---:|---:|---:|
| random(100, seed 1) | resuelto (52 paquetes) | 112 | 9 | 44.6 ms | 2.13 ms |
| random(400, seed 2) | resuelto (41) | 211 | 15 | 88.7 ms | 4.18 ms |
| hard(100, seed 2) | resuelto (59) | 151 | 7 | 74.9 ms | 3.64 ms |
| hard(200, seed 1) | resuelto (112) | 793 | 34 | 564 ms | 24.6 ms |
| hard(200, seed 3) | resuelto (47) | 280 | 14 | 182 ms | 8.73 ms |
| hard(400, seed 1) | sin solución | 35 | 7 | 54.4 ms | 2.30 ms |
| **las 18** | | | | **1343 ms** | **60.4 ms** |

El nativo va **~22× más rápido**, con 13 MB de RSS; los dos motores toman exactamente las mismas
decisiones. `ray profile` sobre la VM: el 23 % del tiempo es `dict.get` + `string#hash` (el `Dict`
genérico de `std/collections` es raylang puro, y en código genérico sobre `P` no hay `Map`) y otro
21 % es `InRange#next` + `range.intersect` (contar candidatos al elegir paquete).

## Estado

| Qué | Estado |
|---|---|
| Semver, rangos, requisitos, resolutor, explicaciones, fuentes, CLI | **34 tests** en VM y nativo (`make test`, `make test-native`), raylang 1.27.95 |
| VM frente a nativo | `make diff`: 14 órdenes con la misma salida en los dos motores |
| Índices de disco | `make stress`: 600 paquetes escritos y leídos de JSON |

Pendiente: un lock en disco que se respete al re-resolver (`raysolve update PAQUETE`), dependencias
opcionales/features, y comparar contra el resolutor real de `ray update` cuando su índice tenga
historia suficiente.

## Hallazgos de dogfood

Once bugs y huecos de raylang, con su reproducción mínima (raylang 1.27.95). Los rodeos están
marcados en el código.

1. **[B]** Un `for` sobre un iterador propio cuyo `impl` lleva bounds (`impl<V: Ord>
   Iterator<V> for InRange<V>`) **rompe los dos motores**: la VM aborta con «ICE: the checker
   guarantees a function» y el nativo no compila (E0061, faltan los diccionarios del bound).
   `.next()`, `.collect()` y `.take()` sí funcionan; sin bounds, `for` también. Rodeo: un `while`
   con `next()` (y sin `while let`, ver 6).
2. **[B]** `let s: dyn Shape = square(2);` (el inicializador es una LLAMADA) y luego `s.name()`:
   ICE en la VM, y el nativo lo rechaza con «call to an expression (neither a name nor a method) is
   not supported». Con `let sq = square(2); let s: dyn Shape = sq;` funciona.
3. **[B]** Nativo: `xs.contains(x)` con `xs: [P]`, `P: Eq` no compila (E0369: `==` no aplica a
   `P`). La VM lo acepta. Rodeo: un bucle con `==`.
4. **[B]** Nativo: el tipo de los elementos que devuelve un campo `fn` de un struct genérico se
   pierde: `"${d.0}"` sobre `prov.deps("x")` da «unknown return type of '__concat'». Rodeo: `let
   name: string = d.0;`.
5. **[B]** `Map<P, int>` con `P: Hash + Eq` genérico pasa el checker y funciona en la VM, pero el
   nativo falla en cargo (E0599); con un tipo de usuario concreto el checker lo rechaza («a Map key
   must be int/string/…»). O una cosa o la otra.
6. **[E]** No hay `while let` (`while let Option.Some(x) = it.next()` → «expected '(' after
   'while'»), ni supertraits (`trait Version: Ord + Hash` → «expected '{' after the trait name»),
   ni traits genéricos en bounds o `dyn` (`S: Source<V>`, `dyn Source<V>` no parsean, aunque `trait
   Source<V>` e `impl<V> Source<V> for X<V>` sí). Ninguna de las tres cosas está documentada.
7. **[E]** La inferencia no baja del contexto a los genéricos: `Bound.Unbounded` en un campo o un
   argumento cuando el tipo esperado es `Bound<V>`, `range.empty()` como argumento, `[]` como
   elemento de `[[int]]`, o `Solution { picks: [("net", 14)] }` con `picks: [(P, V)]` («must be (P,
   V), not (string, int)») piden anotación; solo un `let x: T = …` la da, y no hay sintaxis de
   argumentos de tipo explícitos.
8. **[B]** `print(x)` ignora un `impl Show` escrito a mano (imprime `Plain { n: 1 }`), mientras
   `to_string(x)` y `"${x}"` sí lo usan. Y al revés en genéricos: `to_string(p)` y `"${p}"` con `p:
   P`, `P: Show`, no compilan («to_string only converts int/…»); hay que escribir `p.show()`.
9. **[B/D]** `@derive(Hash)` en un struct con un campo `[string]` da «no field or function 'hash'
   applicable to [string]» en una posición inventada (`50999995:1`) atribuida a otro módulo
   (`std/collections/set`, `version`…), no al `@derive`. La doc no dice que los arrays no sean
   derivables. Rodeo: `pre: string`.
10. **[B]** En un proyecto sin `src/main.ray`, `ray test tests/x_test.ray` no encuentra los
    módulos de `src/` (y la lista de rutas que muestra incluye el directorio padre y `tests` dos
    veces); `ray test` a secas sí.
11. **[D]** §9 (Iteradores) dice que `Iter<T>` está «respaldado por un closure» pero no cuenta
    cómo crear uno desde un closure, ni que un `impl Iterator<T>` propio hereda `map`, `take`,
    `collect`… (sí lo hace), ni la restricción del punto 1.

Lo que salió bien a la primera: `impl Ord` a mano usado por `sort`, `std/sort` (`binary_search`,
`dedup`, `merge`, `sort_desc`, `max`) y `sort_by`; `Dict`/`Set` con claves `@derive(Hash, Eq)`;
`[dyn Source]` en un struct y `Result<dyn Source, _>`; enums y structs genéricos anidados
(`Term<P, V>` con `Range<V>` dentro); closures que capturan un `dyn` y `Map`s y los mutan; `u64`
que envuelve igual en VM y nativo; `std/toml` con patrones anidados calificados
(`Option.Some(TomlValue.TStr(s))`); y el resolutor genérico entero, idéntico en los dos motores.

## Desarrollo

```
make            # lista las tareas
make test       # VM
make test-native
make diff       # misma salida en VM y nativo
make demo
```

## Licencia

Apache-2.0.
