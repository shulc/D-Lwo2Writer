/// Minimal but faithful LWO2 (LightWave object) writer.
///
/// Pure D, no external dependencies. Serializes a plain geometry description
/// (`Lwo2Object`) into the LightWave LWO2 IFF container. It emits the chunks a
/// real LWO2 consumer expects to round-trip a static, surfaced, optionally
/// subdivided mesh:
///
///   FORM .. LWO2
///     LAYR              -- single layer 0
///     TAGS              -- surface name table
///     PNTS              -- float32 BE x/y/z per point
///     BBOX              -- bounding box
///     POLS FACE         -- ordinary polygons
///     POLS PTCH         -- Catmull-Clark subpatches (only if any)
///     PTAG SURF         -- polygon -> surface tag
///     SURF .. (xN)      -- COLR / DIFF / SPEC / GLOS / TRAN
///
/// The surface model mirrors the fields a LightWave/Modo-style modeller keeps
/// per material (base color + diffuse/specular/glossiness/opacity), so output
/// reads back identically through such a loader. Not yet emitted: UVs/weight
/// maps (VMAP), per-corner discontinuities (VMAD), image clips (CLIP), bones.
///
/// Format reference:
///   https://docs.lightwave3d.com/2025/lightwave-object-format.html
///   https://github.com/assimp/assimp/wiki/LightWave-Modo-file-format
///
/// Coordinate note: points are written verbatim. LightWave is left-handed
/// (Y up, +Z forward); convert (e.g. negate Z + reverse winding) before
/// calling if your source is right-handed.
module lwo2.writer;

import std.array : appender, Appender;

/// One LWO2 surface (material). Fields map 1:1 to the SURF sub-chunks below.
struct Lwo2Surface
{
    /// Surface name; also the TAGS entry that PTAG references.
    string  name = "Default";
    /// Base color, linear RGB in [0, 1] (COLR).
    float[3] baseColor = [0.7f, 0.7f, 0.7f];
    /// Diffuse amount (DIFF).
    float   diffuse = 1.0f;
    /// Specular amount (SPEC).
    float   specular = 0.0f;
    /// Glossiness (GLOS); roughness ≈ 1 - glossiness.
    float   glossiness = 0.4f;
    /// Opacity in [0, 1]; written as transparency TRAN = 1 - opacity.
    float   opacity = 1.0f;
}

/// One polygon: ordered point indices, its surface, and FACE-vs-PTCH kind.
struct Lwo2Polygon
{
    /// Indices into `Lwo2Object.points`. 1..1023 entries (LWO2 poly limit).
    uint[] indices;
    /// Index into `Lwo2Object.surfaces`.
    uint   surface;
    /// When true the polygon is emitted as a Catmull-Clark subpatch (PTCH)
    /// instead of an ordinary face (FACE).
    bool   subpatch = false;
}

/// A continuous, per-point vertex map (VMAP). One value tuple per point.
///
/// Sparse and dim-general: `points[i]` is a point index into
/// `Lwo2Object.points`, and its `dimension` floats are
/// `values[i*dimension .. (i+1)*dimension]` (row-major). UV is `type = "TXUV"`,
/// `dimension = 2`. Parallel arrays (not an assoc array) so emission order is
/// deterministic and the map round-trips byte-for-byte.
struct Lwo2VertexMap
{
    /// ID4 map type (e.g. "TXUV" for UV).
    string  type = "TXUV";
    /// Map channel name.
    string  name;
    /// Floats per entry (UV = 2).
    uint    dimension = 2;
    /// Point indices, length N (into `Lwo2Object.points`).
    uint[]  points;
    /// Per-entry values, length N * dimension, row-major.
    float[] values;
}

/// A discontinuous, per-corner vertex map (VMAD). One value tuple per
/// (point, polygon) corner — overrides the continuous VMAP at that corner.
///
/// `polys[i]` is in NATURAL `Lwo2Object.polygons[]` index space (the stable
/// space a caller already has). POLS-local poly indices live on disk only: the
/// writer remaps to POLS-local on emit and the reader remaps back on parse, so
/// this struct never carries a POLS-local index.
struct Lwo2VertexMapD
{
    /// ID4 map type (e.g. "TXUV" for UV).
    string  type = "TXUV";
    /// Map channel name.
    string  name;
    /// Floats per entry (UV = 2).
    uint    dimension = 2;
    /// Point indices, length M (into `Lwo2Object.points`).
    uint[]  points;
    /// Polygon indices, length M (into `Lwo2Object.polygons`).
    uint[]  polys;
    /// Per-entry values, length M * dimension, row-major.
    float[] values;
}

/// A single-layer LWO2 object: points, polygons and the surfaces they use.
struct Lwo2Object
{
    /// Point list, one (x, y, z) per entry.
    float[3][]    points;
    /// Polygon list. FACE and PTCH polys may be interleaved here; the writer
    /// groups them into the two POLS chunks and keeps PTAG indices aligned.
    Lwo2Polygon[] polygons;
    /// Surface table. TAGS/PTAG indices are positions in this array.
    Lwo2Surface[] surfaces;
    /// Optional layer name (LAYR).
    string        layerName = "";
    /// Continuous per-point vertex maps (VMAP). Empty ⇒ no VMAP chunks emitted.
    Lwo2VertexMap[]  vmaps;
    /// Discontinuous per-corner vertex maps (VMAD). Empty ⇒ no VMAD chunks.
    Lwo2VertexMapD[] vmads;
}

/// Serialize `obj` to an in-memory LWO2 file image.
ubyte[] buildLwo2(in Lwo2Object obj)
{
    auto body_ = appender!(ubyte[]); // everything after the "LWO2" form type

    // --- LAYR: single layer 0 ---------------------------------------------
    {
        auto c = appender!(ubyte[]);
        putU2(c, 0);                 // layer number
        putU2(c, 0);                 // flags
        putF4(c, 0); putF4(c, 0); putF4(c, 0); // pivot
        putS0(c, obj.layerName);
        putChunk(body_, "LAYR", c.data);
    }

    // --- TAGS: surface name table -----------------------------------------
    if (obj.surfaces.length)
    {
        auto c = appender!(ubyte[]);
        foreach (s; obj.surfaces)
            putS0(c, s.name);
        putChunk(body_, "TAGS", c.data);
    }

    // --- PNTS: point list -------------------------------------------------
    {
        auto c = appender!(ubyte[]);
        foreach (p; obj.points)
        {
            putF4(c, p[0]); putF4(c, p[1]); putF4(c, p[2]);
        }
        putChunk(body_, "PNTS", c.data);
    }

    // --- BBOX: bounding box -----------------------------------------------
    if (obj.points.length)
    {
        float[3] lo = obj.points[0], hi = obj.points[0];
        foreach (p; obj.points)
            foreach (a; 0 .. 3)
            {
                if (p[a] < lo[a]) lo[a] = p[a];
                if (p[a] > hi[a]) hi[a] = p[a];
            }
        auto c = appender!(ubyte[]);
        putF4(c, lo[0]); putF4(c, lo[1]); putF4(c, lo[2]);
        putF4(c, hi[0]); putF4(c, hi[1]); putF4(c, hi[2]);
        putChunk(body_, "BBOX", c.data);
    }

    // --- POLS: FACE then PTCH ---------------------------------------------
    // The two poly kinds go into two SEPARATE POLS chunks (FACE then PTCH).
    // `emitOrder` is the flat emission sequence (FACE polys, then PTCH polys),
    // reused below for SURF iteration. `polyToLocal[i]` is the POLS-LOCAL index
    // of polygon `i` within its own POLS chunk: a per-kind counter that resets
    // to 0 at the start of each kind's pass. Per the LWO2 spec, PTAG poly
    // indices are local to the most-recent POLS chunk (a conformant reader
    // resets numbering per POLS), so PTAG must use `polyToLocal`, not the flat
    // `emitOrder` position. `polyIsPtch[i]` records the kind for downstream
    // (e.g. VMAD) single-kind handling.
    size_t[] emitOrder;
    emitOrder.reserve(obj.polygons.length);
    auto polyToLocal = new uint[obj.polygons.length];
    auto polyIsPtch  = new bool[obj.polygons.length];
    foreach (kind; 0 .. 2)            // 0 = FACE, 1 = PTCH
    {
        bool wantSub = (kind == 1);
        size_t first = emitOrder.length;
        uint local = 0;               // POLS-local poly counter, reset per kind
        auto c = appender!(ubyte[]);
        c.put(cast(const(ubyte)[]) "FACE"[]); // patched to PTCH below if needed
        foreach (i, poly; obj.polygons)
        {
            if (poly.subpatch != wantSub) continue;
            assert(poly.indices.length >= 1 && poly.indices.length <= 1023,
                   "LWO2 polygon must have 1..1023 vertices");
            putU2(c, cast(ushort)(poly.indices.length & 0x3FF)); // count | flags(0)
            foreach (idx; poly.indices)
                putVX(c, idx);
            polyToLocal[i] = local++;
            polyIsPtch[i]  = wantSub;
            emitOrder ~= i;
        }
        if (emitOrder.length == first)
            continue;                  // no polys of this kind
        // Rewrite the 4-byte poly type for the PTCH pass.
        auto data = c.data;
        if (wantSub)
            data[0 .. 4] = cast(const(ubyte)[]) "PTCH"[];
        putChunk(body_, "POLS", data);
    }

    // --- PTAG SURF: polygon -> surface tag --------------------------------
    // Poly indices are POLS-LOCAL (per the LWO2 spec): FACE PTAG entries number
    // 0..N-1, PTCH PTAG entries number 0..M-1 — each local to its own POLS
    // chunk. (For a single-kind mesh there is one POLS chunk, so local == flat
    // and the bytes are identical to a flat numbering.)
    if (obj.surfaces.length)
    {
        auto c = appender!(ubyte[]);
        c.put(cast(const(ubyte)[]) "SURF"[]);
        foreach (polyIdx; emitOrder)
        {
            putVX(c, polyToLocal[polyIdx]);
            putU2(c, cast(ushort) obj.polygons[polyIdx].surface);
        }
        putChunk(body_, "PTAG", c.data);
    }

    // --- SURF: one per surface --------------------------------------------
    foreach (s; obj.surfaces)
    {
        auto c = appender!(ubyte[]);
        putS0(c, s.name);
        putS0(c, "");                // parent surface (none)

        // COLR { base-color[COL12], envelope[VX]=0 }
        {
            auto sc = appender!(ubyte[]);
            putF4(sc, s.baseColor[0]); putF4(sc, s.baseColor[1]); putF4(sc, s.baseColor[2]);
            putVX(sc, 0);
            putSubChunk(c, "COLR", sc.data);
        }
        putF4SubChunk(c, "DIFF", s.diffuse);
        putF4SubChunk(c, "SPEC", s.specular);
        putF4SubChunk(c, "GLOS", s.glossiness);
        putF4SubChunk(c, "TRAN", 1.0f - s.opacity);

        putChunk(body_, "SURF", c.data);
    }

    // --- FORM wrapper -----------------------------------------------------
    auto outp = appender!(ubyte[]);
    outp.put(cast(const(ubyte)[]) "FORM"[]);
    putU4(outp, cast(uint)(4 + body_.data.length)); // "LWO2" + chunks
    outp.put(cast(const(ubyte)[]) "LWO2"[]);
    outp.put(body_.data);
    return outp.data;
}

/// Serialize `obj` and write it to `path`.
void writeLwo2File(string path, in Lwo2Object obj)
{
    import std.file : write;
    write(path, buildLwo2(obj));
}

// ---------------------------------------------------------------------------
// IFF / big-endian primitives
// ---------------------------------------------------------------------------

private alias App = Appender!(ubyte[]);

private void putU2(ref App a, ushort v)
{
    a.put(cast(ubyte)(v >> 8));
    a.put(cast(ubyte)(v & 0xFF));
}

private void putU4(ref App a, uint v)
{
    a.put(cast(ubyte)(v >> 24));
    a.put(cast(ubyte)(v >> 16));
    a.put(cast(ubyte)(v >> 8));
    a.put(cast(ubyte)(v & 0xFF));
}

private void putF4(ref App a, float v) @trusted
{
    putU4(a, *cast(uint*) &v);
}

/// Variable-length index (VX): u2 when < 0xFF00, else 4 bytes flagged 0xFF.
private void putVX(ref App a, uint idx)
{
    if (idx < 0xFF00)
        putU2(a, cast(ushort) idx);
    else
    {
        assert(idx <= 0x00FF_FFFF, "LWO2 VX index out of range (max 0xFFFFFF)");
        putU4(a, 0xFF00_0000u | idx);
    }
}

/// Null-terminated string padded to an even byte length (S0).
private void putS0(ref App a, string s)
{
    a.put(cast(const(ubyte)[]) s);
    a.put(cast(ubyte) 0);
    if (s.length % 2 == 0)        // length incl. terminator is odd -> pad
        a.put(cast(ubyte) 0);
}

/// Top-level chunk: 4-byte id, u4 length, body, even pad (pad not counted).
private void putChunk(ref App a, string id, const(ubyte)[] body_)
{
    assert(id.length == 4);
    a.put(cast(const(ubyte)[]) id);
    putU4(a, cast(uint) body_.length);
    a.put(body_);
    if (body_.length & 1)
        a.put(cast(ubyte) 0);
}

/// Sub-chunk (inside SURF etc.): 4-byte id, u2 length, body, even pad.
private void putSubChunk(ref App a, string id, const(ubyte)[] body_)
{
    assert(id.length == 4);
    a.put(cast(const(ubyte)[]) id);
    putU2(a, cast(ushort) body_.length);
    a.put(body_);
    if (body_.length & 1)
        a.put(cast(ubyte) 0);
}

/// SURF sub-chunk carrying a single F4 value + envelope-ref VX=0
/// (DIFF / SPEC / GLOS / TRAN).
private void putF4SubChunk(ref App a, string id, float v)
{
    auto sc = appender!(ubyte[]);
    putF4(sc, v);
    putVX(sc, 0);
    putSubChunk(a, id, sc.data);
}

// ---------------------------------------------------------------------------
unittest
{
    // A unit quad (FACE) + a triangle marked subpatch (PTCH), two surfaces.
    Lwo2Object obj;
    obj.points = [
        [0f, 0f, 0f], [1f, 0f, 0f], [1f, 1f, 0f], [0f, 1f, 0f], [0.5f, 2f, 0f]
    ];
    obj.surfaces = [
        Lwo2Surface("Body"),
        Lwo2Surface("Roof"),
    ];
    obj.polygons = [
        Lwo2Polygon([0, 1, 2, 3], 0, false),
        Lwo2Polygon([3, 2, 4], 1, true),
    ];

    auto bytes = buildLwo2(obj);

    // Well-formed FORM/LWO2 header.
    assert(bytes[0 .. 4] == cast(const(ubyte)[]) "FORM");
    assert(bytes[8 .. 12] == cast(const(ubyte)[]) "LWO2");
    // FORM length field matches the actual payload after it.
    uint formLen = (bytes[4] << 24) | (bytes[5] << 16) | (bytes[6] << 8) | bytes[7];
    assert(formLen == bytes.length - 8);
    // Whole image is even-length (IFF invariant).
    assert(bytes.length % 2 == 0);

    // Required chunks + both poly types are present.
    import std.algorithm : canFind;
    static bool has(const(ubyte)[] hay, string id)
    {
        return canFind(hay, cast(const(ubyte)[]) id);
    }
    foreach (id; ["LAYR", "TAGS", "PNTS", "POLS", "FACE", "PTCH", "PTAG", "SURF"])
        assert(has(bytes, id), "missing chunk " ~ id);
}
