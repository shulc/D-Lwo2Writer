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
dub test --config=core      # dependency-free unit tests
dub build --config=full     # writer + assimp adapter
```

## License

MIT.
