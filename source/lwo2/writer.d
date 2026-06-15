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
///     VMAP .. (xN)      -- continuous per-point vertex maps (e.g. UV/TXUV)
///     POLS FACE         -- ordinary polygons
///     VMAD .. (xN)      -- per-corner maps bound to the FACE polys above
///     POLS PTCH         -- Catmull-Clark subpatches (only if any)
///     VMAD .. (xN)      -- per-corner maps bound to the PTCH polys above
///     PTAG SURF         -- polygon -> surface tag
///     SURF .. (xN)      -- COLR / DIFF / SPEC / GLOS / TRAN
///
/// A VMAD binds to the most-recent POLS chunk and uses POLS-local poly indices,
/// so each VMAD is emitted immediately after the POLS chunk of the kind it
/// references (each VMAD references exactly one kind).
///
/// The surface model mirrors the fields a LightWave/Modo-style modeller keeps
/// per material (base color + diffuse/specular/glossiness/opacity), so output
/// reads back identically through such a loader. Not yet emitted: image clips
/// (CLIP), bones.
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

/// LAYR `flags` U2 bit meaning "layer is hidden/inactive".
///
/// The LWO2 LAYR chunk's `flags` is a bitfield; bit 0 (value `0x0001`) marks the
/// layer hidden (not active/visible). We carry only this bit; every other flag
/// bit is written as 0. The reader masks the same bit back out.
enum ushort LAYR_FLAG_HIDDEN = 0x0001;

/// One layer of a multi-layer LWO2 object.
///
/// Holds the geometry that lives under a single `LAYR n` chunk: name, pivot,
/// visibility, points, polygons and vertex maps. Point indices in
/// `polygons`/`vmaps`/`vmads` are LAYER-LOCAL (0-based into THIS layer's
/// `points`); VMAD poly indices are in this layer's `polygons[]` space. The
/// surface table (`Lwo2Object.surfaces`) is GLOBAL across all layers — LWO2
/// surfaces are file-scoped, referenced by per-layer POLS/PTAG tag indices.
struct Lwo2Layer
{
    /// Layer name (LAYR S0 name).
    string        name = "";
    /// LAYR pivot (VEC12). Coordinates are written verbatim; any per-layer
    /// transform a caller wants baked must already be applied to `points`.
    float[3]      pivot = [0f, 0f, 0f];
    /// Whether the layer is hidden — sets the LAYR `flags` hidden bit.
    bool          hidden = false;
    /// Point list, one (x, y, z) per entry. Layer-local.
    float[3][]    points;
    /// Polygon list (FACE/PTCH). Indices are into THIS layer's `points`.
    Lwo2Polygon[] polygons;
    /// Continuous per-point vertex maps (VMAP); point indices are layer-local.
    Lwo2VertexMap[]  vmaps;
    /// Discontinuous per-corner vertex maps (VMAD); poly indices are into THIS
    /// layer's `polygons[]`.
    Lwo2VertexMapD[] vmads;
}

/// An LWO2 object: one or more layers sharing one global surface table.
///
/// Two ways to populate it:
///
///   * Single-layer (back-compat): set the flat `points` / `polygons` /
///     `vmaps` / `vmads` / `layerName` fields and leave `layers` empty. The
///     writer emits exactly one `LAYR 0` from these — byte-identical to the
///     historical single-layer output.
///   * Multi-layer: leave the flat fields empty and populate `layers`. The
///     writer emits one `LAYR n` per entry (n = its index) and IGNORES the flat
///     fields. The shared `surfaces` table is emitted once regardless.
struct Lwo2Object
{
    /// Point list, one (x, y, z) per entry. Used only when `layers` is empty.
    float[3][]    points;
    /// Polygon list. FACE and PTCH polys may be interleaved here; the writer
    /// groups them into the two POLS chunks and keeps PTAG indices aligned.
    /// Used only when `layers` is empty.
    Lwo2Polygon[] polygons;
    /// Surface table. TAGS/PTAG indices are positions in this array. GLOBAL —
    /// shared by every layer (single- or multi-layer).
    Lwo2Surface[] surfaces;
    /// Optional layer name (LAYR). Used only when `layers` is empty.
    string        layerName = "";
    /// Continuous per-point vertex maps (VMAP). Empty ⇒ no VMAP chunks emitted.
    /// Used only when `layers` is empty.
    Lwo2VertexMap[]  vmaps;
    /// Discontinuous per-corner vertex maps (VMAD). Empty ⇒ no VMAD chunks.
    /// Used only when `layers` is empty.
    Lwo2VertexMapD[] vmads;
    /// Multi-layer geometry. When non-empty, the writer emits THESE layers (one
    /// `LAYR n` each) and ignores the flat fields above. When empty, the writer
    /// behaves exactly as before (single `LAYR 0` from the flat fields).
    Lwo2Layer[]   layers;
}

/// Serialize `obj` to an in-memory LWO2 file image.
ubyte[] buildLwo2(in Lwo2Object obj)
{
    auto body_ = appender!(ubyte[]); // everything after the "LWO2" form type

    // Normalize to a layer list. When `layers` is empty, wrap the flat fields in
    // a single throwaway layer (name = layerName, pivot 0, not hidden) so the
    // single-layer path is exactly the N=1 case of the layered one.
    Lwo2Layer[] layers = cast(Lwo2Layer[]) obj.layers;
    if (layers.length == 0)
    {
        auto only = Lwo2Layer(obj.layerName, [0f, 0f, 0f], false);
        only.points   = cast(float[3][]) obj.points;
        only.polygons = cast(Lwo2Polygon[]) obj.polygons;
        only.vmaps    = cast(Lwo2VertexMap[]) obj.vmaps;
        only.vmads    = cast(Lwo2VertexMapD[]) obj.vmads;
        layers = [only];
    }

    const bool hasSurfaces = obj.surfaces.length > 0;

    // Emit each layer as `LAYR n` + its geometry body. The GLOBAL TAGS table is
    // emitted ONCE, right after the FIRST LAYR header and before the first
    // layer's geometry — this exactly reproduces the legacy single-layer chunk
    // order (LAYR 0, TAGS, PNTS, ...) so the N=1 output is byte-identical, while
    // remaining a valid placement for multi-layer files.
    foreach (n, ref layer; layers)
    {
        emitLayrHeader(body_, cast(ushort) n, layer);
        if (n == 0)
            emitTags(body_, obj.surfaces);
        emitLayerBody(body_, layer, hasSurfaces);
    }

    // --- SURF: one per surface (GLOBAL, shared by every layer) ------------
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
// Per-layer emission
// ---------------------------------------------------------------------------

/// Emit one `LAYR` chunk: U2 number, U2 flags, VEC12 pivot, S0 name. The
/// `flags` U2 carries the hidden bit (`LAYR_FLAG_HIDDEN`); all other bits 0.
private void emitLayrHeader(ref App body_, ushort number, in Lwo2Layer layer)
{
    auto c = appender!(ubyte[]);
    putU2(c, number);                                  // layer number
    putU2(c, layer.hidden ? LAYR_FLAG_HIDDEN : 0);     // flags (bit 0 = hidden)
    putF4(c, layer.pivot[0]); putF4(c, layer.pivot[1]); putF4(c, layer.pivot[2]);
    putS0(c, layer.name);
    putChunk(body_, "LAYR", c.data);
}

/// Emit the global TAGS surface-name table (once per file). No-op when empty.
private void emitTags(ref App body_, in Lwo2Surface[] surfaces)
{
    if (surfaces.length == 0)
        return;
    auto c = appender!(ubyte[]);
    foreach (s; surfaces)
        putS0(c, s.name);
    putChunk(body_, "TAGS", c.data);
}

/// Emit one layer's geometry body — PNTS, BBOX, VMAP*, POLS (FACE then PTCH)
/// with their bound VMADs, and the layer-local PTAG SURF. Point indices in the
/// layer's polygons/vmaps/vmads are layer-local; PTAG/VMAD poly indices reset
/// POLS-locally per THIS layer's own POLS chunks. `hasSurfaces` gates the PTAG
/// (which references the GLOBAL surface table). For a single layer this
/// reproduces the exact chunk sequence the legacy writer emitted.
private void emitLayerBody(ref App body_, in Lwo2Layer layer, bool hasSurfaces)
{
    // --- PNTS: point list -------------------------------------------------
    {
        auto c = appender!(ubyte[]);
        foreach (p; layer.points)
        {
            putF4(c, p[0]); putF4(c, p[1]); putF4(c, p[2]);
        }
        putChunk(body_, "PNTS", c.data);
    }

    // --- BBOX: bounding box -----------------------------------------------
    if (layer.points.length)
    {
        float[3] lo = layer.points[0], hi = layer.points[0];
        foreach (p; layer.points)
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

    // --- VMAP: continuous per-point vertex maps ---------------------------
    // VMAP is per-point and POLS-independent (it carries explicit point
    // indices), so it can be emitted here, before any POLS chunk. Body layout:
    //   ID4 type | U2 dimension | S0 name | per entry { VX point | F4 x dim }
    foreach (vm; layer.vmaps)
    {
        assert(vm.type.length == 4, "VMAP type must be a 4-char ID4");
        assert(vm.values.length == vm.points.length * vm.dimension,
               "VMAP values length must equal points * dimension");
        auto c = appender!(ubyte[]);
        c.put(cast(const(ubyte)[]) vm.type[]);
        putU2(c, cast(ushort) vm.dimension);
        putS0(c, vm.name);
        foreach (k, pt; vm.points)
        {
            assert(pt < layer.points.length, "VMAP point index out of range");
            putVX(c, pt);
            foreach (d; 0 .. vm.dimension)
                putF4(c, vm.values[k * vm.dimension + d]);
        }
        putChunk(body_, "VMAP", c.data);
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
    // (e.g. VMAD) single-kind handling. All numbering is layer-local.
    size_t[] emitOrder;
    emitOrder.reserve(layer.polygons.length);
    auto polyToLocal = new uint[layer.polygons.length];
    auto polyIsPtch  = new bool[layer.polygons.length];
    // Precompute the per-kind POLS-local index + kind for EVERY polygon up
    // front (one counter per kind), so the VMAD single-kind assert and the
    // POLS-local remap are valid no matter which pass is running. The emission
    // loop below reproduces the same numbering as it walks each kind.
    {
        uint[2] kindCount = [0u, 0u];
        foreach (i, poly; layer.polygons)
        {
            ubyte k = poly.subpatch ? 1 : 0;
            polyToLocal[i] = kindCount[k]++;
            polyIsPtch[i]  = poly.subpatch;
        }
    }
    foreach (kind; 0 .. 2)            // 0 = FACE, 1 = PTCH
    {
        bool wantSub = (kind == 1);
        size_t first = emitOrder.length;
        uint local = 0;               // POLS-local poly counter, reset per kind
        auto c = appender!(ubyte[]);
        c.put(cast(const(ubyte)[]) "FACE"[]); // patched to PTCH below if needed
        foreach (i, poly; layer.polygons)
        {
            if (poly.subpatch != wantSub) continue;
            assert(poly.indices.length >= 1 && poly.indices.length <= 1023,
                   "LWO2 polygon must have 1..1023 vertices");
            putU2(c, cast(ushort)(poly.indices.length & 0x3FF)); // count | flags(0)
            foreach (idx; poly.indices)
                putVX(c, idx);
            assert(polyToLocal[i] == local, "POLS-local numbering desync");
            local++;
            emitOrder ~= i;
        }
        if (emitOrder.length == first)
            continue;                  // no polys of this kind
        // Rewrite the 4-byte poly type for the PTCH pass.
        auto data = c.data;
        if (wantSub)
            data[0 .. 4] = cast(const(ubyte)[]) "PTCH"[];
        putChunk(body_, "POLS", data);

        // --- VMAD: discontinuous per-corner maps for THIS kind ------------
        // A VMAD binds to the most-recent POLS chunk and uses POLS-LOCAL poly
        // indices, so each VMAD must be emitted immediately after the POLS
        // chunk of the kind it references. We flush every VMAD whose polys
        // belong to the kind just written (D-2 single-kind constraint). Body:
        //   ID4 type | U2 dim | S0 name
        //     | per entry { VX point | VX localPoly | F4 x dim }
        // where localPoly = polyToLocal[polys[k]] (public polys[] is the
        // layer's polygons[]-space; remapped to POLS-local on emit).
        foreach (vmad; layer.vmads)
        {
            assert(vmad.type.length == 4, "VMAD type must be a 4-char ID4");
            assert(vmad.values.length == vmad.points.length * vmad.dimension,
                   "VMAD values length must equal points * dimension");
            assert(vmad.polys.length == vmad.points.length,
                   "VMAD polys length must equal points length");
            if (vmad.points.length == 0)
                continue;              // nothing to bind; skip empty VMAD

            // Single-kind assert: every entry's poly must share one kind.
            bool vmadKind = polyIsPtch[vmad.polys[0]];
            foreach (pi; vmad.polys)
            {
                assert(pi < layer.polygons.length,
                       "VMAD poly index out of range");
                assert(polyIsPtch[pi] == vmadKind,
                       "VMAD spans both FACE and PTCH kinds (single-kind only)");
            }
            if (vmadKind != wantSub)
                continue;              // belongs to the other kind's POLS

            auto c2 = appender!(ubyte[]);
            c2.put(cast(const(ubyte)[]) vmad.type[]);
            putU2(c2, cast(ushort) vmad.dimension);
            putS0(c2, vmad.name);
            foreach (k; 0 .. vmad.points.length)
            {
                uint pt = vmad.points[k];
                assert(pt < layer.points.length, "VMAD point index out of range");
                uint localPoly = polyToLocal[vmad.polys[k]];
                assert(localPoly < local,
                       "VMAD local poly index exceeds this kind's poly count");
                putVX(c2, pt);
                putVX(c2, localPoly);
                foreach (d; 0 .. vmad.dimension)
                    putF4(c2, vmad.values[k * vmad.dimension + d]);
            }
            putChunk(body_, "VMAD", c2.data);
        }
    }

    // --- PTAG SURF: polygon -> surface tag --------------------------------
    // Poly indices are POLS-LOCAL (per the LWO2 spec): FACE PTAG entries number
    // 0..N-1, PTCH PTAG entries number 0..M-1 — each local to its own POLS
    // chunk. (For a single-kind mesh there is one POLS chunk, so local == flat
    // and the bytes are identical to a flat numbering.) The `surface` index is
    // into the GLOBAL surface table, shared across layers.
    if (hasSurfaces)
    {
        auto c = appender!(ubyte[]);
        c.put(cast(const(ubyte)[]) "SURF"[]);
        foreach (polyIdx; emitOrder)
        {
            putVX(c, polyToLocal[polyIdx]);
            putU2(c, cast(ushort) layer.polygons[polyIdx].surface);
        }
        putChunk(body_, "PTAG", c.data);
    }
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

// ---------------------------------------------------------------------------
// Multi-layer additive change: byte-identity of the single-layer path.
//
// The flat single-layer object and an equivalent object that puts the SAME
// geometry into `layers[0]` (name "", pivot 0, not hidden) must produce IDENTICAL
// bytes — proving the refactor into `emitLayer*` did not perturb single-layer
// output and that the flat path is exactly the N=1 case of the layered one.
unittest
{
    Lwo2Object flat;
    flat.points = [
        [0f, 0f, 0f], [1f, 0f, 0f], [1f, 1f, 0f], [0f, 1f, 0f], [0.5f, 2f, 0f]
    ];
    flat.surfaces = [Lwo2Surface("Body"), Lwo2Surface("Roof")];
    flat.polygons = [
        Lwo2Polygon([0, 1, 2, 3], 0, false),
        Lwo2Polygon([3, 2, 4], 1, true),
    ];
    // A UV VMAP + a per-corner VMAD to exercise every per-layer chunk path.
    flat.vmaps = [Lwo2VertexMap("TXUV", "uv", 2,
                                [0, 1, 2, 3, 4],
                                [0f, 0f, 1f, 0f, 1f, 1f, 0f, 1f, 0.5f, 1f])];
    flat.vmads = [Lwo2VertexMapD("TXUV", "uv", 2, [2], [0], [0.9f, 0.1f])];

    // Equivalent object with the geometry in layers[0] and empty flat fields.
    Lwo2Object layered;
    layered.surfaces = flat.surfaces;          // surfaces stay global
    Lwo2Layer L;
    L.name     = "";                           // flat layerName default
    L.pivot    = [0f, 0f, 0f];
    L.hidden   = false;
    L.points   = flat.points;
    L.polygons = flat.polygons;
    L.vmaps    = flat.vmaps;
    L.vmads    = flat.vmads;
    layered.layers = [L];

    auto a = buildLwo2(flat);
    auto b = buildLwo2(layered);
    assert(a == b, "single-layer flat output must byte-match the N=1 layered form");
}

// Multi-layer write: two layers (a quad layer + a hidden triangle layer) sharing
// one global surface table. Asserts the layered structure shows up in the bytes:
// two LAYR chunks, two PNTS, two POLS, exactly one TAGS, and the hidden flag on
// the second layer's LAYR.
unittest
{
    import std.algorithm : count, countUntil;

    Lwo2Object obj;
    obj.surfaces = [Lwo2Surface("A"), Lwo2Surface("B")];

    Lwo2Layer quad;
    quad.name     = "quad";
    quad.points   = [[0f, 0f, 0f], [1f, 0f, 0f], [1f, 1f, 0f], [0f, 1f, 0f]];
    quad.polygons = [Lwo2Polygon([0, 1, 2, 3], 0, false)];

    Lwo2Layer tri;
    tri.name     = "tri";
    tri.hidden   = true;                       // second layer hidden
    tri.points   = [[0f, 0f, 5f], [1f, 0f, 5f], [0.5f, 1f, 5f]];
    tri.polygons = [Lwo2Polygon([0, 1, 2], 1, false)];

    obj.layers = [quad, tri];
    auto bytes = buildLwo2(obj);

    static size_t countChunks(const(ubyte)[] hay, string id)
    {
        size_t n = 0;
        const(ubyte)[] needle = cast(const(ubyte)[]) id;
        foreach (i; 0 .. (hay.length >= 4 ? hay.length - 3 : 0))
            if (hay[i .. i + 4] == needle)
                n++;
        return n;
    }

    assert(countChunks(bytes, "LAYR") == 2, "expected two LAYR chunks");
    assert(countChunks(bytes, "PNTS") == 2, "expected two PNTS chunks");
    assert(countChunks(bytes, "POLS") == 2, "expected two POLS chunks");
    assert(countChunks(bytes, "TAGS") == 1, "expected exactly one (global) TAGS");

    // Locate each LAYR chunk and read its number + flags U2 fields. Chunk layout
    // after the 4-byte id: U4 length, then body { U2 number, U2 flags, ... }.
    size_t pos = 0;
    int seen = 0;
    while (true)
    {
        auto rel = countUntil(bytes[pos .. $], cast(const(ubyte)[]) "LAYR");
        if (rel < 0) break;
        size_t at = pos + rel;
        size_t body0 = at + 4 + 4;             // skip id + U4 length
        ushort number = cast(ushort)((bytes[body0]     << 8) | bytes[body0 + 1]);
        ushort flags  = cast(ushort)((bytes[body0 + 2] << 8) | bytes[body0 + 3]);
        if (seen == 0)
        {
            assert(number == 0, "first LAYR number must be 0");
            assert((flags & LAYR_FLAG_HIDDEN) == 0, "layer 0 must not be hidden");
        }
        else if (seen == 1)
        {
            assert(number == 1, "second LAYR number must be 1");
            assert((flags & LAYR_FLAG_HIDDEN) != 0,
                   "second layer must have the hidden flag set");
        }
        seen++;
        pos = at + 4;
    }
    assert(seen == 2, "expected to locate two LAYR headers");
}
