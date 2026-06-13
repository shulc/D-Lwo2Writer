# lwo2-writer

A minimal, MIT-licensed **LWO2 (LightWave object) writer** for D.

Pure D, zero dependencies in its core. It serializes a plain geometry
description into the LightWave LWO2 IFF container — points, polygons (faces and
Catmull-Clark subpatches), surfaces with color/diffuse/specular/glossiness/
opacity, and the surface→polygon tagging that LightWave, Modo and Assimp read
back.

## Why

Open-source LWO2 *export* is scarce and the one well-known writer (DarkRadiant /
FbxToLwo) is GPL. This is a clean-room, permissively-licensed writer built from
the public [LWO2 format spec](https://docs.lightwave3d.com/2025/lightwave-object-format.html),
so it can be linked into MIT/BSL projects.

## What it writes

```
FORM .. LWO2
  LAYR            single layer 0
  TAGS            surface name table
  PNTS            float32 BE x/y/z per point
  BBOX            bounding box
  VMAP .. (xN)    continuous per-point vertex maps (e.g. UV / TXUV)
  POLS FACE       ordinary polygons
  VMAD .. (xN)    per-corner maps bound to the FACE polys above
  POLS PTCH       Catmull-Clark subpatches (emitted only if any)
  VMAD .. (xN)    per-corner maps bound to the PTCH polys above
  PTAG SURF       polygon -> surface tag
  SURF .. (xN)    COLR / DIFF / SPEC / GLOS / TRAN
```

A VMAD binds to the most-recent `POLS` chunk and uses POLS-local poly indices,
so each `VMAD` is emitted immediately after the `POLS` chunk of the kind it
references.

Not yet emitted: image clips (CLIP), bones.

## What it reads

`readLwo2` / `readLwo2File` are the inverse of the writer: they parse an LWO2
IFF image back into the same `Lwo2Object`, so `readLwo2(buildLwo2(obj))`
round-trips field-for-field (and `buildLwo2(readLwo2(bytes))` is byte-identical).

```
FORM .. LWO2
  LAYR            single layer (name; number/flags/pivot ignored)
  TAGS            surface name table
  PNTS            points
  BBOX            skipped (recomputed from PNTS on write)
  POLS FACE/PTCH  polygons; PTCH preserved as subpatch=true
  PTAG SURF       polygon -> surface tag  (POLS-local index, remapped back)
  VMAP .. (xN)    continuous per-point maps (e.g. UV / TXUV)
  VMAD .. (xN)    per-corner maps, bound to their most-recent POLS chunk
  SURF .. (xN)    COLR / DIFF / SPEC / GLOS / TRAN
```

On-disk PTAG and VMAD poly indices are **POLS-local** (0-based within the most
recent `POLS` chunk of a kind); the reader remaps them back to natural
`Lwo2Object.polygons[]` index space, so the carrier structs you read back never
hold a POLS-local index. Unknown top-level chunks and curve POLS kinds are
skipped by size; malformed or truncated input throws a typed `Lwo2ReadException`
rather than corrupting state. Multi-layer is out of scope — geometry and
surfaces accumulate into a single `Lwo2Object`.

```d
import lwo2;

Lwo2Object obj = readLwo2File("quad.lwo");
assert(obj.points.length > 0);
foreach (p; obj.polygons)
    if (p.subpatch) { /* a Catmull-Clark subpatch */ }
```

## Usage — UV maps (VMAP / VMAD)

A **VMAP** is a continuous per-point map (one value tuple per point); a **VMAD**
is a discontinuous per-corner map (one value tuple per `(point, polygon)` corner,
overriding the VMAP at that corner). Both are sparse, dim-general parallel
arrays; UV is `type = "TXUV"`, `dimension = 2`.

```d
import lwo2;

Lwo2Object obj;
obj.points   = [[0,0,0], [1,0,0], [1,1,0], [0,1,0]];
obj.surfaces = [ Lwo2Surface("Body") ];
obj.polygons = [ Lwo2Polygon([0, 1, 2, 3], /*surface*/ 0) ];

// Continuous per-point UV.
obj.vmaps ~= Lwo2VertexMap("TXUV", "Texture", 2,
        /*points*/ [0u, 1u, 2u, 3u],
        /*values*/ [0f,0f, 1f,0f, 1f,1f, 0f,1f]);

// Per-corner override on one corner of polygon 0 (polys are in obj.polygons[]
// index space — the writer/reader handle the POLS-local conversion).
obj.vmads ~= Lwo2VertexMapD("TXUV", "Texture", 2,
        /*points*/ [2u], /*polys*/ [0u], /*values*/ [0.9f, 0.9f]);

auto bytes = buildLwo2(obj);

// Read it back: UV is keyed in obj.polygons[] space on both sides.
auto back = readLwo2(bytes);
foreach (vm; back.vmaps) { /* vm.points[i] -> vm.values[i*vm.dimension .. ] */ }
foreach (vd; back.vmads) { /* vd.polys[i] is an obj.polygons[] index */ }
```

## Usage — core writer (no dependencies)

```d
import lwo2;

Lwo2Object obj;
obj.points   = [[0,0,0], [1,0,0], [1,1,0], [0,1,0]];
obj.surfaces = [ Lwo2Surface("Body") ];
obj.polygons = [ Lwo2Polygon([0, 1, 2, 3], /*surface*/ 0) ];

writeLwo2File("quad.lwo", obj);
```

`Lwo2Surface` fields (`baseColor`, `diffuse`, `specular`, `glossiness`,
`opacity`) map 1:1 to the SURF sub-chunks. Set `Lwo2Polygon.subpatch = true`
to emit a polygon into the `POLS PTCH` chunk instead of `POLS FACE`.

dub: depend on this package and pick the `core` configuration to stay
dependency-free.

```json
"dependencies": { "lwo2-writer": { "path": "../D-Lwo2Writer" } },
"subConfigurations": { "lwo2-writer": "core" }
```

## Usage — assimp adapter (optional)

The `full` configuration adds `lwo2.assimp`, which converts a
[`bindbc-assimp6`](../D-Assimp) `aiScene*` into an `Lwo2Object` — "import
anything Assimp reads, save as LWO2":

```d
import bindbc.assimp;
import lwo2.assimp;

loadAssimp();
const(aiScene)* scene = aiImportFile("model.fbx".toStringz,
        aiProcess_Triangulate | aiProcess_JoinIdenticalVertices);
exportSceneToLwo2(scene, "model.lwo");   // merges meshes, one SURF per material
```

See `examples/convert` for a complete CLI:

```sh
cd examples/convert && dub run -- input.fbx output.lwo
```

## Coordinate system

Points are written **verbatim**. LightWave is left-handed (Y up, +Z forward);
if your source data is right-handed, negate an axis (e.g. Z) and reverse
polygon winding before calling.

## Build / test

```sh
dub test --config=core      # dependency-free unit tests (reader + writer + UV)
dub build --config=full     # writer + assimp adapter
dub build                   # default config (full)
```

The unit tests cover the writer, the reader, full write→read→write byte-identity,
the UV (VMAP/VMAD) round-trip, and the format edges (VX 2-/4-byte boundary,
even-pad, unknown-chunk skip, truncation). A small committed golden cube
(`tests/fixtures/cube_uv.lwo`, embedded into the test via a string import) guards
against silent writer drift; regenerate it with
`rdmd -Isource tools/gen_cube_fixture.d` if the cube definition changes.

## License

MIT.
