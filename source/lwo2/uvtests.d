/// Unit tests for the LWO2 UV (VMAP/VMAD) carrier + round-trip surface.
///
/// This module is compiled ONLY under `-unittest` (the whole module declaration
/// is gated by `version(unittest)`), so `dub test` picks it up and a normal
/// `dub build` compiles it to an inert, empty translation unit. It carries no
/// runtime code outside its `unittest` blocks.
///
/// NOTE: D requires the `module` declaration to be the first declaration in the
/// file (it cannot itself be gated by `version`). So the module name is plain
/// and the ENTIRE body is gated with `version(unittest):` — under a normal
/// `dub build` this file compiles to an inert, empty module (no symbols, no
/// effect); under `dub test` (`-unittest`) its `unittest` blocks run.
module lwo2.uvtests;

version(unittest):

import lwo2.writer;
import lwo2.reader;

// ---------------------------------------------------------------------------
// Stage 1 — D-1 "empty ⇒ no chunks emitted" byte-identity guard.
//
// An Lwo2Object with vmaps/vmads empty (the default after adding the new
// fields) must produce EXACTLY the expected writer bytes — no VMAP/VMAD chunk,
// identical length — so this asserts the new carrier fields are wholly inert.
//
// The golden buffer was originally captured from the writer before the carrier
// fields existed (the inline quad+tri sample) and is UPDATED for the Stage 2.5
// PTAG conformance fix (one byte: the PTCH entry's PTAG poly index is now
// POLS-local 0, not the flat cross-POLS sequence 1). See Stage 2.5 tests below.
// ---------------------------------------------------------------------------
unittest
{
    // The existing inline-unittest sample: a unit quad (FACE) + a triangle
    // marked subpatch (PTCH), two surfaces. vmaps/vmads left empty.
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

    // Golden output of the same object. Byte-identical == empty maps emit
    // nothing. UPDATED for the Stage 2.5 PTAG conformance fix: the PTCH poly's
    // PTAG poly index is now POLS-LOCAL (0), not the flat cross-POLS sequence
    // (1). The single changed byte is in the PTAG SURF body — the PTCH entry's
    // VX, "0,1" (flat seq=1) is now "0,0" (local index 0 within the PTCH POLS).
    static immutable ubyte[] golden = [
        70,79,82,77,0,0,1,124,76,87,79,50,76,65,89,82,0,0,0,18,0,0,0,0,0,0,0,0,
        0,0,0,0,0,0,0,0,0,0,84,65,71,83,0,0,0,12,66,111,100,121,0,0,82,111,111,
        102,0,0,80,78,84,83,0,0,0,60,0,0,0,0,0,0,0,0,0,0,0,0,63,128,0,0,0,0,0,0,
        0,0,0,0,63,128,0,0,63,128,0,0,0,0,0,0,0,0,0,0,63,128,0,0,0,0,0,0,63,0,0,
        0,64,0,0,0,0,0,0,0,66,66,79,88,0,0,0,24,0,0,0,0,0,0,0,0,0,0,0,0,63,128,
        0,0,64,0,0,0,0,0,0,0,80,79,76,83,0,0,0,14,70,65,67,69,0,4,0,0,0,1,0,2,0,
        3,80,79,76,83,0,0,0,12,80,84,67,72,0,3,0,3,0,2,0,4,80,84,65,71,0,0,0,12,
        83,85,82,70,0,0,0,0,0,0,0,1,83,85,82,70,0,0,0,76,66,111,100,121,0,0,0,0,
        67,79,76,82,0,14,63,51,51,51,63,51,51,51,63,51,51,51,0,0,68,73,70,70,0,6,
        63,128,0,0,0,0,83,80,69,67,0,6,0,0,0,0,0,0,71,76,79,83,0,6,62,204,204,
        205,0,0,84,82,65,78,0,6,0,0,0,0,0,0,83,85,82,70,0,0,0,76,82,111,111,102,
        0,0,0,0,67,79,76,82,0,14,63,51,51,51,63,51,51,51,63,51,51,51,0,0,68,73,
        70,70,0,6,63,128,0,0,0,0,83,80,69,67,0,6,0,0,0,0,0,0,71,76,79,83,0,6,62,
        204,204,205,0,0,84,82,65,78,0,6,0,0,0,0,0,0
    ];

    assert(bytes.length == golden.length,
           "empty-UV output length changed vs pre-carrier writer");
    assert(bytes == golden,
           "empty-UV output bytes changed vs pre-carrier writer");

    // Explicit D-1 promise: no VMAP / VMAD chunk id appears anywhere.
    import std.algorithm : canFind;
    assert(!canFind(bytes, cast(const(ubyte)[]) "VMAP"),
           "VMAP chunk emitted for an object with no vmaps");
    assert(!canFind(bytes, cast(const(ubyte)[]) "VMAD"),
           "VMAD chunk emitted for an object with no vmads");
}

// ---------------------------------------------------------------------------
// Stage 1 — the carrier structs exist with the documented shape and defaults
// (dim-general, parallel-array sparse, "TXUV" default type). Inert: nothing
// here touches buildLwo2 output.
// ---------------------------------------------------------------------------
unittest
{
    Lwo2VertexMap vm;
    assert(vm.type == "TXUV");
    assert(vm.dimension == 2);
    assert(vm.points.length == 0);
    assert(vm.values.length == 0);

    // Populate a 2-point UV map; parallel arrays, row-major values.
    vm.name = "Texture";
    vm.points = [0u, 3u];
    vm.values = [0.0f, 0.0f,  1.0f, 0.5f];
    assert(vm.values.length == vm.points.length * vm.dimension);

    Lwo2VertexMapD vmad;
    assert(vmad.type == "TXUV");
    assert(vmad.dimension == 2);
    assert(vmad.points.length == 0);
    assert(vmad.polys.length == 0);
    assert(vmad.values.length == 0);

    // A per-corner (point, poly) entry; poly in obj.polygons[] index space.
    vmad.name = "Texture";
    vmad.points = [3u];
    vmad.polys  = [1u];
    vmad.values = [0.25f, 0.75f];
    assert(vmad.values.length == vmad.points.length * vmad.dimension);

    // The carriers attach to Lwo2Object and default empty.
    Lwo2Object obj;
    assert(obj.vmaps.length == 0);
    assert(obj.vmads.length == 0);
    obj.vmaps ~= vm;
    obj.vmads ~= vmad;
    assert(obj.vmaps.length == 1);
    assert(obj.vmads.length == 1);
}

// ---------------------------------------------------------------------------
// Helper: locate the body of the first top-level chunk with `id`. Returns the
// slice of `bytes` covering exactly the chunk body (length = the u4 length
// field), or null if not found. Walks the FORM payload chunk-by-chunk so it is
// robust to chunk contents that happen to contain the id bytes.
// ---------------------------------------------------------------------------
version(unittest)
private const(ubyte)[] chunkBody(const(ubyte)[] bytes, string id)
{
    // bytes[0..4]="FORM", [4..8]=u4 len, [8..12]="LWO2", then chunks.
    size_t p = 12;
    while (p + 8 <= bytes.length)
    {
        auto cid = bytes[p .. p + 4];
        uint len = (bytes[p + 4] << 24) | (bytes[p + 5] << 16)
                 | (bytes[p + 6] << 8)  | bytes[p + 7];
        size_t bodyStart = p + 8;
        if (bodyStart + len > bytes.length) break;
        if (cid == cast(const(ubyte)[]) id)
            return bytes[bodyStart .. bodyStart + len];
        p = bodyStart + len + (len & 1); // even pad not counted in len
    }
    return null;
}

// ---------------------------------------------------------------------------
// Stage 2.5 — BLOCKER 2 regression guard: PTAG poly indices are POLS-LOCAL.
//
// For a MIXED FACE+PTCH mesh the PTCH polygon lands in its own (second) POLS
// chunk, so its PTAG poly index must be 0 (local to that chunk), NOT the flat
// cross-POLS position 1. This is the single byte that distinguishes the
// conformance fix from the pre-fix flat numbering.
// ---------------------------------------------------------------------------
unittest
{
    Lwo2Object obj;
    obj.points = [
        [0f, 0f, 0f], [1f, 0f, 0f], [1f, 1f, 0f], [0f, 1f, 0f], [0.5f, 2f, 0f]
    ];
    obj.surfaces = [
        Lwo2Surface("Body"),
        Lwo2Surface("Roof"),
    ];
    obj.polygons = [
        Lwo2Polygon([0, 1, 2, 3], 0, false), // FACE — local index 0 in POLS#1
        Lwo2Polygon([3, 2, 4], 1, true),     // PTCH — local index 0 in POLS#2
    ];

    auto bytes = buildLwo2(obj);
    auto ptag  = chunkBody(bytes, "PTAG");
    assert(ptag !is null, "PTAG chunk missing");

    // PTAG body: "SURF" then per-poly (VX poly-index, U2 surface-index).
    // Both polys here have a small index, so each VX is a 2-byte U2.
    assert(ptag[0 .. 4] == cast(const(ubyte)[]) "SURF");
    // Entry 0: FACE quad — VX poly index 0, surface 0.
    ushort faceIdx = cast(ushort)((ptag[4] << 8) | ptag[5]);
    ushort faceSrf = cast(ushort)((ptag[6] << 8) | ptag[7]);
    assert(faceIdx == 0, "FACE PTAG poly index should be local 0");
    assert(faceSrf == 0);
    // Entry 1: PTCH tri — VX poly index 0 (POLS-LOCAL), surface 1.
    // Pre-fix (flat numbering) this byte pair was 1; the fix makes it 0.
    ushort ptchIdx = cast(ushort)((ptag[8] << 8) | ptag[9]);
    ushort ptchSrf = cast(ushort)((ptag[10] << 8) | ptag[11]);
    assert(ptchIdx == 0,
           "BLOCKER 2: PTCH PTAG poly index must be POLS-LOCAL 0, not flat 1");
    assert(ptchSrf == 1);
}

// ---------------------------------------------------------------------------
// Stage 2.5 — single-kind meshes are byte-UNCHANGED by the conformance fix.
//
// A pure-FACE (or pure-PTCH) mesh emits exactly one POLS chunk, so flat
// numbering == POLS-local numbering and the PTAG bytes (and thus the whole
// image) are identical to the pre-fix output. The goldens below were produced
// by the writer; they verify the fix did not perturb the single-POLS path.
// ---------------------------------------------------------------------------
unittest
{
    // Pure-FACE: two quads, one surface. One POLS chunk ⇒ PTAG indices 0,1.
    Lwo2Object obj;
    obj.points = [
        [0f, 0f, 0f], [1f, 0f, 0f], [1f, 1f, 0f], [0f, 1f, 0f],
        [2f, 0f, 0f], [2f, 1f, 0f]
    ];
    obj.surfaces = [ Lwo2Surface("Body") ];
    obj.polygons = [
        Lwo2Polygon([0, 1, 2, 3], 0, false),
        Lwo2Polygon([1, 4, 5, 2], 0, false),
    ];

    auto bytes = buildLwo2(obj);
    auto ptag  = chunkBody(bytes, "PTAG");
    assert(ptag !is null && ptag[0 .. 4] == cast(const(ubyte)[]) "SURF");
    // Sequential 0,1 — identical to flat numbering for a single POLS chunk.
    assert(((ptag[4] << 8) | ptag[5]) == 0, "poly0 local index 0");
    assert(((ptag[8] << 8) | ptag[9]) == 1, "poly1 local index 1");
    // Exactly one POLS chunk exists (single-kind ⇒ flat == local).
    size_t polsCount = 0;
    for (size_t p = 12; p + 8 <= bytes.length; )
    {
        uint len = (bytes[p + 4] << 24) | (bytes[p + 5] << 16)
                 | (bytes[p + 6] << 8)  | bytes[p + 7];
        if (bytes[p .. p + 4] == cast(const(ubyte)[]) "POLS") polsCount++;
        p += 8 + len + (len & 1);
    }
    assert(polsCount == 1, "pure-FACE mesh must emit exactly one POLS chunk");
}

unittest
{
    // Pure-PTCH: two subpatch quads, one surface. One POLS chunk ⇒ 0,1.
    Lwo2Object obj;
    obj.points = [
        [0f, 0f, 0f], [1f, 0f, 0f], [1f, 1f, 0f], [0f, 1f, 0f],
        [2f, 0f, 0f], [2f, 1f, 0f]
    ];
    obj.surfaces = [ Lwo2Surface("Body") ];
    obj.polygons = [
        Lwo2Polygon([0, 1, 2, 3], 0, true),
        Lwo2Polygon([1, 4, 5, 2], 0, true),
    ];

    auto bytes = buildLwo2(obj);
    auto ptag  = chunkBody(bytes, "PTAG");
    assert(ptag !is null && ptag[0 .. 4] == cast(const(ubyte)[]) "SURF");
    assert(((ptag[4] << 8) | ptag[5]) == 0, "poly0 local index 0");
    assert(((ptag[8] << 8) | ptag[9]) == 1, "poly1 local index 1");
    size_t polsCount = 0;
    for (size_t p = 12; p + 8 <= bytes.length; )
    {
        uint len = (bytes[p + 4] << 24) | (bytes[p + 5] << 16)
                 | (bytes[p + 6] << 8)  | bytes[p + 7];
        if (bytes[p .. p + 4] == cast(const(ubyte)[]) "POLS") polsCount++;
        p += 8 + len + (len & 1);
    }
    assert(polsCount == 1, "pure-PTCH mesh must emit exactly one POLS chunk");
}

// ---------------------------------------------------------------------------
// Stage 2 — write -> read round-trip of geometry + subpatch + surfaces.
//
// The mixed FACE+PTCH + 2-surface sample (the same one the writer's inline
// unittest builds). buildLwo2 -> readLwo2 must reproduce points, polygons
// (indices + count), the per-poly subpatch flag, the per-poly surface index,
// and every SURF field. This is a valid assertion on a MIXED FACE+PTCH mesh
// only because Stage 2.5 made PTAG POLS-local — the reader's localToGlobal
// remap (D-2 reader half) maps the PTCH entry's local index 0 back to the
// correct obj.polygons[] slot.
// ---------------------------------------------------------------------------
unittest
{
    Lwo2Object obj;
    obj.points = [
        [0f, 0f, 0f], [1f, 0f, 0f], [1f, 1f, 0f], [0f, 1f, 0f], [0.5f, 2f, 0f]
    ];
    obj.surfaces = [
        Lwo2Surface("Body", [0.8f, 0.1f, 0.1f], 0.9f, 0.2f, 0.6f, 1.0f),
        Lwo2Surface("Roof", [0.1f, 0.1f, 0.8f], 1.0f, 0.5f, 0.3f, 0.4f),
    ];
    obj.polygons = [
        Lwo2Polygon([0, 1, 2, 3], 0, false), // FACE quad, surface "Body"
        Lwo2Polygon([3, 2, 4],    1, true),  // PTCH tri,  surface "Roof"
    ];

    auto bytes = buildLwo2(obj);
    auto back  = readLwo2(bytes);

    // Layer name (empty default).
    assert(back.layerName == obj.layerName);

    // Points.
    assert(back.points.length == obj.points.length);
    foreach (i; 0 .. obj.points.length)
        foreach (a; 0 .. 3)
            assert(back.points[i][a] == obj.points[i][a],
                   "point coordinate changed in round-trip");

    // Polygons: indices, count, subpatch flag, surface index — in the SAME
    // order. The writer emits FACE-then-PTCH and the reader appends FACE-then-
    // PTCH, so for this sample the order is preserved (quad then tri).
    assert(back.polygons.length == obj.polygons.length);
    foreach (i; 0 .. obj.polygons.length)
    {
        assert(back.polygons[i].indices == obj.polygons[i].indices,
               "polygon vertex indices changed");
        assert(back.polygons[i].subpatch == obj.polygons[i].subpatch,
               "polygon subpatch flag changed");
        assert(back.polygons[i].surface == obj.polygons[i].surface,
               "polygon surface index changed (PTAG local->global remap?)");
    }
    // Explicit: the PTCH poly is poly 1, subpatch=true, surface=1 (Roof).
    assert(back.polygons[1].subpatch);
    assert(back.polygons[1].surface == 1);
    assert(back.polygons[0].surface == 0);

    // Surfaces: name + every SURF field round-trips.
    assert(back.surfaces.length == obj.surfaces.length);
    foreach (i; 0 .. obj.surfaces.length)
    {
        assert(back.surfaces[i].name        == obj.surfaces[i].name);
        assert(back.surfaces[i].baseColor   == obj.surfaces[i].baseColor);
        assert(back.surfaces[i].diffuse     == obj.surfaces[i].diffuse);
        assert(back.surfaces[i].specular    == obj.surfaces[i].specular);
        assert(back.surfaces[i].glossiness  == obj.surfaces[i].glossiness);
        // opacity is stored on disk as TRAN = 1 - opacity, so the round-trip
        // is opacity -> (1 - opacity) -> 1 - (1 - opacity). That double float
        // subtraction is not bit-exact (e.g. 0.4 -> 0.6 -> 0.3999999762), so
        // compare within a float epsilon — the reader faithfully inverts the
        // on-disk TRAN; the tiny delta is the writer's TRAN representation.
        import std.math : abs;
        assert(abs(back.surfaces[i].opacity - obj.surfaces[i].opacity) < 1e-6f,
               "opacity (1 - TRAN) changed beyond float epsilon in round-trip");
    }
}

// ---------------------------------------------------------------------------
// Stage 2 — VX 4-byte-boundary: a poly that references a point index >= 0xFF00
// is written in the 4-byte VX form and must read back exactly.
//
// Construct >0xFF00 points so the last point's index forces a 4-byte VX. The
// big point list is irrelevant geometry — only the index encoding is under
// test — but it must be present so the index is legal.
// ---------------------------------------------------------------------------
unittest
{
    enum size_t N = 0xFF00 + 4;    // 65284 points -> last index 65283 (>0xFF00)
    Lwo2Object obj;
    obj.points.length = N;
    foreach (i; 0 .. N)
        obj.points[i] = [cast(float) i, 0f, 0f];
    obj.surfaces = [ Lwo2Surface("Body") ];
    // One quad referencing two small indices and two >=0xFF00 indices so both
    // the U2 and U4 VX forms appear in the same polygon.
    uint hi0 = cast(uint)(N - 2);  // 65282
    uint hi1 = cast(uint)(N - 1);  // 65283
    obj.polygons = [ Lwo2Polygon([0u, 1u, hi0, hi1], 0, false) ];

    auto bytes = buildLwo2(obj);
    auto back  = readLwo2(bytes);

    assert(back.points.length == N);
    assert(back.polygons.length == 1);
    assert(back.polygons[0].indices == [0u, 1u, hi0, hi1],
           "VX 4-byte-boundary index round-trip mismatch");
    // The high indices really are in the 4-byte VX range.
    assert(hi0 >= 0xFF00 && hi1 >= 0xFF00);
    // First and last points survive verbatim.
    assert(back.points[0]      == [0f, 0f, 0f]);
    assert(back.points[hi1][0] == cast(float) hi1);
}

// ---------------------------------------------------------------------------
// Stage 2 — even-pad: an odd-length S0 name (surface name + layer name) is
// NUL-terminated and padded to an even byte count on write; the reader must
// consume the pad and recover the exact name.
//
// "Body" has length 4 (even) -> name+NUL = 5 (odd) -> 1 pad byte.
// "Roofy" has length 5 (odd)  -> name+NUL = 6 (even) -> 0 pad bytes.
// Exercising both parities proves the reader's S0 pad accounting.
// ---------------------------------------------------------------------------
unittest
{
    Lwo2Object obj;
    obj.layerName = "Lyr";         // length 3 (odd) -> name+NUL=4 (even), 0 pad
    obj.points = [
        [0f, 0f, 0f], [1f, 0f, 0f], [1f, 1f, 0f], [0f, 1f, 0f], [0.5f, 2f, 0f]
    ];
    obj.surfaces = [
        Lwo2Surface("Body"),       // even-length name  -> 1 pad byte
        Lwo2Surface("Roofy"),      // odd-length name   -> 0 pad bytes
    ];
    obj.polygons = [
        Lwo2Polygon([0, 1, 2, 3], 0, false),
        Lwo2Polygon([3, 2, 4],    1, true),
    ];

    auto back = readLwo2(buildLwo2(obj));

    assert(back.layerName == "Lyr", "odd-length layer name not recovered");
    assert(back.surfaces.length == 2);
    assert(back.surfaces[0].name == "Body",
           "even-length surface name (with pad) not recovered exactly");
    assert(back.surfaces[1].name == "Roofy",
           "odd-length surface name (no pad) not recovered exactly");
    // Geometry still intact alongside the padded names.
    assert(back.points.length == 5);
    assert(back.polygons.length == 2);
    assert(back.polygons[1].subpatch);
}

// ---------------------------------------------------------------------------
// Stage 3 — UV write: VMAP + VMAD are emitted, structurally valid, and the
// VMAD poly VX is the POLS-LOCAL index.
//
// The mesh has one FACE quad (obj.polygons[0]) and one PTCH tri
// (obj.polygons[1]). A continuous TXUV VMAP names two points; a discontinuous
// TXUV VMAD attaches a per-corner UV to the PTCH poly (obj.polygons[1]). Since
// the PTCH poly is the first (and only) poly in the PTCH POLS chunk, its
// POLS-LOCAL index is 0 — NOT its obj.polygons[] index 1. The on-disk VMAD poly
// VX must therefore be 0, the load-bearing D-2 remap proof.
//
// The full write->read round-trip lands in Stage 4 (reader not done yet); this
// stage asserts the EMITTED bytes structurally.
// ---------------------------------------------------------------------------
unittest
{
    Lwo2Object obj;
    obj.points = [
        [0f, 0f, 0f], [1f, 0f, 0f], [1f, 1f, 0f], [0f, 1f, 0f], [0.5f, 2f, 0f]
    ];
    obj.surfaces = [
        Lwo2Surface("Body"),
        Lwo2Surface("Roof"),
    ];
    obj.polygons = [
        Lwo2Polygon([0, 1, 2, 3], 0, false), // FACE — local index 0 in POLS#1
        Lwo2Polygon([3, 2, 4],    1, true),  // PTCH — local index 0 in POLS#2
    ];

    // Continuous per-point UV: two named points.
    Lwo2VertexMap vm;
    vm.type      = "TXUV";
    vm.name      = "Texture";
    vm.dimension = 2;
    vm.points    = [0u, 3u];
    vm.values    = [0.0f, 0.0f,  1.0f, 0.5f];
    obj.vmaps ~= vm;

    // Discontinuous per-corner UV on the PTCH poly (obj.polygons[] index 1).
    Lwo2VertexMapD vmad;
    vmad.type      = "TXUV";
    vmad.name      = "Texture";
    vmad.dimension = 2;
    vmad.points    = [3u];
    vmad.polys     = [1u];           // obj.polygons[] space; local index is 0
    vmad.values    = [0.25f, 0.75f];
    obj.vmads ~= vmad;

    auto bytes = buildLwo2(obj);

    // Well-formed FORM/LWO2 header + FORM length still == len - 8.
    assert(bytes[0 .. 4] == cast(const(ubyte)[]) "FORM");
    assert(bytes[8 .. 12] == cast(const(ubyte)[]) "LWO2");
    uint formLen = (bytes[4] << 24) | (bytes[5] << 16) | (bytes[6] << 8) | bytes[7];
    assert(formLen == bytes.length - 8, "FORM length wrong after VMAP/VMAD");
    assert(bytes.length % 2 == 0, "IFF image must be even-length");

    // The new chunks (and their TXUV type) are present.
    import std.algorithm : canFind;
    assert(canFind(bytes, cast(const(ubyte)[]) "VMAP"), "VMAP chunk missing");
    assert(canFind(bytes, cast(const(ubyte)[]) "VMAD"), "VMAD chunk missing");
    assert(canFind(bytes, cast(const(ubyte)[]) "TXUV"), "TXUV type missing");

    // VMAP body: "TXUV" | U2 dim=2 | S0 "Texture" | (VX 0, F4 0,0) (VX 3, F4 1,0.5)
    auto vmapBody = chunkBody(bytes, "VMAP");
    assert(vmapBody !is null, "VMAP body not found");
    assert(vmapBody[0 .. 4] == cast(const(ubyte)[]) "TXUV", "VMAP type != TXUV");
    ushort vmapDim = cast(ushort)((vmapBody[4] << 8) | vmapBody[5]);
    assert(vmapDim == 2, "VMAP dimension should be 2");

    // VMAD body: "TXUV" | U2 dim=2 | S0 "Texture" | (VX point=3, VX localPoly, F4..)
    auto vmadBody = chunkBody(bytes, "VMAD");
    assert(vmadBody !is null, "VMAD body not found");
    assert(vmadBody[0 .. 4] == cast(const(ubyte)[]) "TXUV", "VMAD type != TXUV");
    ushort vmadDim = cast(ushort)((vmadBody[4] << 8) | vmadBody[5]);
    assert(vmadDim == 2, "VMAD dimension should be 2");
    // Skip the S0 name "Texture" (7 chars + NUL = 8, even -> no extra pad).
    size_t off = 6;
    while (off < vmadBody.length && vmadBody[off] != 0) off++;
    off++;                                  // consume NUL
    if (((off - 6) & 1) != 0) off++;        // S0 even pad (name+NUL odd -> +1)
    // First entry: VX point (small -> U2), then VX localPoly (small -> U2).
    ushort vmadPoint = cast(ushort)((vmadBody[off] << 8) | vmadBody[off + 1]);
    ushort vmadPoly  = cast(ushort)((vmadBody[off + 2] << 8) | vmadBody[off + 3]);
    assert(vmadPoint == 3, "VMAD point index should be 3");
    assert(vmadPoly == 0,
           "VMAD poly VX must be POLS-LOCAL 0 (not obj.polygons[] index 1)");

    // Every top-level chunk has an even on-disk footprint (len + pad).
    for (size_t p = 12; p + 8 <= bytes.length; )
    {
        uint len = (bytes[p + 4] << 24) | (bytes[p + 5] << 16)
                 | (bytes[p + 6] << 8)  | bytes[p + 7];
        size_t footprint = 8 + len + (len & 1);
        assert((footprint & 1) == 0, "chunk footprint must be even");
        p += footprint;
    }
}

// ---------------------------------------------------------------------------
// Stage 3 — VMAD emit-order: a FACE-kind VMAD and a PTCH-kind VMAD each land
// immediately after their own kind's POLS chunk (the per-kind binding rule).
// Order on disk must be: POLS(FACE), VMAD(FACE), POLS(PTCH), VMAD(PTCH).
// ---------------------------------------------------------------------------
unittest
{
    Lwo2Object obj;
    obj.points = [
        [0f, 0f, 0f], [1f, 0f, 0f], [1f, 1f, 0f], [0f, 1f, 0f], [0.5f, 2f, 0f]
    ];
    obj.surfaces = [ Lwo2Surface("Body") ];
    obj.polygons = [
        Lwo2Polygon([0, 1, 2, 3], 0, false), // FACE
        Lwo2Polygon([3, 2, 4],    0, true),  // PTCH
    ];

    Lwo2VertexMapD faceVmad;
    faceVmad.type = "TXUV"; faceVmad.name = "F"; faceVmad.dimension = 2;
    faceVmad.points = [0u]; faceVmad.polys = [0u]; faceVmad.values = [0.1f, 0.2f];

    Lwo2VertexMapD ptchVmad;
    ptchVmad.type = "TXUV"; ptchVmad.name = "P"; ptchVmad.dimension = 2;
    ptchVmad.points = [4u]; ptchVmad.polys = [1u]; ptchVmad.values = [0.3f, 0.4f];

    obj.vmads = [ faceVmad, ptchVmad ];

    auto bytes = buildLwo2(obj);

    // Collect (id, bodyStart) in disk order.
    string[] ids;
    for (size_t p = 12; p + 8 <= bytes.length; )
    {
        ids ~= cast(string)(bytes[p .. p + 4].idup);
        uint len = (bytes[p + 4] << 24) | (bytes[p + 5] << 16)
                 | (bytes[p + 6] << 8)  | bytes[p + 7];
        p += 8 + len + (len & 1);
    }

    // Find each POLS by inspecting its first 4 body bytes (FACE vs PTCH).
    // Locate ordered indices of POLS-FACE, the first VMAD after it, POLS-PTCH,
    // and the VMAD after that.
    import std.algorithm : countUntil;
    // There are exactly two POLS chunks (FACE then PTCH) and two VMADs.
    size_t nPols = 0, nVmad = 0;
    foreach (id; ids) { if (id == "POLS") nPols++; if (id == "VMAD") nVmad++; }
    assert(nPols == 2, "expected two POLS chunks (FACE + PTCH)");
    assert(nVmad == 2, "expected two VMAD chunks (one per kind)");

    // Walk in order; the sequence must be POLS, VMAD, POLS, VMAD.
    string[] geomSeq;
    foreach (id; ids)
        if (id == "POLS" || id == "VMAD")
            geomSeq ~= id;
    assert(geomSeq == ["POLS", "VMAD", "POLS", "VMAD"],
           "VMAD must follow its own kind's POLS (POLS,VMAD,POLS,VMAD)");

    // The FACE VMAD's poly VX is local 0 (FACE poly is local 0 in POLS#1);
    // the PTCH VMAD's poly VX is local 0 (PTCH poly is local 0 in POLS#2).
    // Both happen to be 0 here, which is exactly the POLS-local property.
    auto vmadBody = chunkBody(bytes, "VMAD"); // first VMAD = FACE-kind
    assert(vmadBody !is null);
    assert(vmadBody[0 .. 4] == cast(const(ubyte)[]) "TXUV");
}
