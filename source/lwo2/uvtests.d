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

// ===========================================================================
// Stage 4 — UV read: parse VMAP + VMAD.
// ===========================================================================

// ---------------------------------------------------------------------------
// Inline IFF byte-emit primitives — DELIBERATELY independent of writer.d's
// private put* helpers. The hand-authored byte fixture below is built with
// these (not via buildLwo2), so a shared wrong poly-index model in the
// writer+reader cannot make the fixture pass.
// ---------------------------------------------------------------------------
version(unittest)
private struct Bld
{
    ubyte[] b;

    void u2(ushort v) { b ~= cast(ubyte)(v >> 8); b ~= cast(ubyte)(v & 0xFF); }
    void u4(uint v)
    {
        b ~= cast(ubyte)(v >> 24); b ~= cast(ubyte)(v >> 16);
        b ~= cast(ubyte)(v >> 8);  b ~= cast(ubyte)(v & 0xFF);
    }
    void f4(float v) @trusted { u4(*cast(uint*) &v); }
    void id4(string s) { assert(s.length == 4); b ~= cast(const(ubyte)[]) s; }
    /// VX (small index only — the hand fixture uses indices < 0xFF00).
    void vx(uint idx) { assert(idx < 0xFF00); u2(cast(ushort) idx); }
    /// S0: NUL-terminated, even-padded.
    void s0(string s)
    {
        b ~= cast(const(ubyte)[]) s;
        b ~= cast(ubyte) 0;
        if (s.length % 2 == 0) b ~= cast(ubyte) 0; // chars+NUL odd -> 1 pad byte
    }
}

/// Wrap a chunk body in `[ID4 id][u4 len][body][even pad]`, append to `out_`.
version(unittest)
private void emitChunk(ref ubyte[] out_, string id, const(ubyte)[] body_)
{
    assert(id.length == 4);
    out_ ~= cast(const(ubyte)[]) id;
    Bld h; h.u4(cast(uint) body_.length);
    out_ ~= h.b;
    out_ ~= body_;
    if (body_.length & 1) out_ ~= cast(ubyte) 0; // even pad, not counted in len
}

// ---------------------------------------------------------------------------
// Stage 4 — HAND-AUTHORED BYTE FIXTURE (the BLOCKER-1/2 guard).
//
// This is the single authoritative test that the POLS-local poly-index model
// is correct, because it is constructed BY HAND (not via buildLwo2). A writer
// and reader that share the same wrong index space would agree on a generated
// round-trip; only an independently-authored buffer with a hand-computed
// expected mapping can catch that.
//
// Layout authored below (one layer):
//   PNTS    : 5 points p0..p4.
//   TAGS    : 2 surfaces  -> tag 0 = "FaceSurf", tag 1 = "PatchSurf".
//   POLS FACE: 2 FACE polys                  (POLS-local 0, 1)
//                local 0 = [0,1,2]  -> obj.polygons[0]
//                local 1 = [0,2,3]  -> obj.polygons[1]
//   POLS PTCH: 1 PTCH poly                   (POLS-local 0)
//                local 0 = [0,3,4]  -> obj.polygons[2]   (subpatch=true)
//   PTAG SURF: FACE local 0 -> tag 0, FACE local 1 -> tag 0,
//              PTCH local 0 -> tag 1   <-- PTCH PTAG poly index = 0 (LOCAL)
//   VMAD TXUV: one entry on PTCH local 0     <-- VMAD poly index = 0 (LOCAL)
//
// EXPECTED MAPPING (authored by hand):
//   - The PTCH poly is the LAST polygon appended, so it lands at
//     obj.polygons[2], NOT obj.polygons[0]. Its POLS-local index (0) must be
//     remapped through localToGlobal[PTCH] to slot 2.
//   - The PTAG PTCH entry (local 0) must therefore set obj.polygons[2].surface
//     = 1 (PatchSurf). A FLAT-INDEX reader would wrongly assign tag 1 to
//     obj.polygons[0] (the first FACE) — so this proves the remap, not a
//     flat-index coincidence (slot 2 != local 0).
//   - The VMAD (local 0) must attach to that SAME obj.polygons[2].
// ---------------------------------------------------------------------------
unittest
{
    // --- PNTS body: 5 points (f4 x3 each) ---------------------------------
    Bld pnts;
    pnts.f4(0); pnts.f4(0); pnts.f4(0);   // p0
    pnts.f4(1); pnts.f4(0); pnts.f4(0);   // p1
    pnts.f4(1); pnts.f4(1); pnts.f4(0);   // p2
    pnts.f4(0); pnts.f4(1); pnts.f4(0);   // p3
    pnts.f4(0); pnts.f4(2); pnts.f4(0);   // p4

    // --- TAGS body: two surface names -------------------------------------
    Bld tags;
    tags.s0("FaceSurf");   // tag 0 (8 chars -> +NUL=9 odd -> 1 pad)
    tags.s0("PatchSurf");  // tag 1 (9 chars -> +NUL=10 even -> 0 pad)

    // --- POLS FACE body: "FACE" + 2 polys ---------------------------------
    Bld polsFace;
    polsFace.id4("FACE");
    polsFace.u2(3); polsFace.vx(0); polsFace.vx(1); polsFace.vx(2); // local 0
    polsFace.u2(3); polsFace.vx(0); polsFace.vx(2); polsFace.vx(3); // local 1

    // --- POLS PTCH body: "PTCH" + 1 poly ----------------------------------
    Bld polsPtch;
    polsPtch.id4("PTCH");
    polsPtch.u2(3); polsPtch.vx(0); polsPtch.vx(3); polsPtch.vx(4); // local 0

    // --- PTAG SURF body: "SURF" + per-entry (VX localPoly, U2 tag) ---------
    // The PTAG that follows the PTCH POLS binds to the PTCH chunk; its single
    // entry's poly index is POLS-LOCAL 0. We also tag the two FACE polys, but
    // a single PTAG binds to ONE POLS chunk, so we emit a PTAG after the FACE
    // POLS (FACE locals) and a PTAG after the PTCH POLS (PTCH local). The
    // reader binds each PTAG to the most-recent POLS — exactly like VMAD.
    Bld ptagFace;
    ptagFace.id4("SURF");
    ptagFace.vx(0); ptagFace.u2(0);   // FACE local 0 -> tag 0 (FaceSurf)
    ptagFace.vx(1); ptagFace.u2(0);   // FACE local 1 -> tag 0 (FaceSurf)

    Bld ptagPtch;
    ptagPtch.id4("SURF");
    ptagPtch.vx(0); ptagPtch.u2(1);   // PTCH local 0 -> tag 1 (PatchSurf)

    // --- VMAD TXUV body: type + dim + name + (VX point, VX localPoly, f4xdim)
    Bld vmad;
    vmad.id4("TXUV");
    vmad.u2(2);                        // dimension
    vmad.s0("UV");                     // name (2 chars -> +NUL=3 odd -> 1 pad)
    vmad.vx(4);                        // point index 4 (a corner of the PTCH)
    vmad.vx(0);                        // POLS-LOCAL poly index 0 (the PTCH poly)
    vmad.f4(0.5f); vmad.f4(0.25f);     // the UV value

    // --- SURF bodies (minimal: name + empty parent) -----------------------
    Bld surf0; surf0.s0("FaceSurf");  surf0.s0("");
    Bld surf1; surf1.s0("PatchSurf"); surf1.s0("");

    // --- LAYR body (compact LWO2): u2 number, u2 flags, f4x3 pivot, S0 name -
    Bld layr;
    layr.u2(0); layr.u2(0);
    layr.f4(0); layr.f4(0); layr.f4(0);
    layr.s0("");

    // --- Assemble the chunk stream. The PTAG/VMAD for the PTCH bind to the
    //     PTCH POLS, so they must follow it (most-recent-POLS rule). Order:
    //       LAYR, TAGS, PNTS, POLS FACE, PTAG(FACE), POLS PTCH, PTAG(PTCH),
    //       VMAD(PTCH), SURF, SURF.
    ubyte[] payload;
    emitChunk(payload, "LAYR", layr.b);
    emitChunk(payload, "TAGS", tags.b);
    emitChunk(payload, "PNTS", pnts.b);
    emitChunk(payload, "POLS", polsFace.b);
    emitChunk(payload, "PTAG", ptagFace.b);
    emitChunk(payload, "POLS", polsPtch.b);
    emitChunk(payload, "PTAG", ptagPtch.b);
    emitChunk(payload, "VMAD", vmad.b);
    emitChunk(payload, "SURF", surf0.b);
    emitChunk(payload, "SURF", surf1.b);

    // --- FORM/LWO2 wrapper: "FORM" + u4(4 + payload) + "LWO2" + payload ----
    ubyte[] file;
    file ~= cast(const(ubyte)[]) "FORM";
    Bld len; len.u4(cast(uint)(4 + payload.length));
    file ~= len.b;
    file ~= cast(const(ubyte)[]) "LWO2";
    file ~= payload;
    assert(file.length % 2 == 0, "hand-authored IFF image must be even-length");

    // --- READ + assert the HAND-AUTHORED expected mapping -----------------
    auto obj = readLwo2(file);

    // Geometry: 3 polys total, in append order FACE,FACE,PTCH.
    assert(obj.points.length == 5, "5 points expected");
    assert(obj.polygons.length == 3, "2 FACE + 1 PTCH = 3 polygons");
    assert(obj.polygons[0].indices == [0u, 1u, 2u]);
    assert(obj.polygons[1].indices == [0u, 2u, 3u]);
    assert(obj.polygons[2].indices == [0u, 3u, 4u]);

    // (a) The PTCH poly landed at obj.polygons[2] with subpatch=true.
    assert(!obj.polygons[0].subpatch, "FACE poly 0 must not be subpatch");
    assert(!obj.polygons[1].subpatch, "FACE poly 1 must not be subpatch");
    assert(obj.polygons[2].subpatch,
           "the PTCH poly must land at obj.polygons[2] with subpatch=true");

    // (b) The surface assignment proves the LOCAL->GLOBAL remap (not a flat
    //     coincidence): the PTCH PTAG entry's LOCAL index 0 maps to GLOBAL
    //     slot 2. A flat-index reader would have put tag 1 on slot 0.
    assert(obj.polygons[0].surface == 0, "FACE poly 0 -> FaceSurf (tag 0)");
    assert(obj.polygons[1].surface == 0, "FACE poly 1 -> FaceSurf (tag 0)");
    assert(obj.polygons[2].surface == 1,
           "BLOCKER 1/2: PTCH PTAG local 0 must remap to obj.polygons[2] "
           ~ "(PatchSurf, tag 1), NOT flat slot 0");
    // The surface table itself round-trips its names.
    assert(obj.surfaces.length == 2);
    assert(obj.surfaces[0].name == "FaceSurf");
    assert(obj.surfaces[1].name == "PatchSurf");

    // (c) The VMAD UV attaches to the SAME obj.polygons[2] poly. Its on-disk
    //     poly index was POLS-LOCAL 0; it must read back as obj.polygons[]
    //     slot 2 — the load-bearing D-2 reader-half remap.
    assert(obj.vmads.length == 1, "one VMAD expected");
    assert(obj.vmads[0].type == "TXUV");
    assert(obj.vmads[0].name == "UV");
    assert(obj.vmads[0].dimension == 2);
    assert(obj.vmads[0].points == [4u], "VMAD point index round-trip");
    assert(obj.vmads[0].polys == [2u],
           "BLOCKER 1/2: VMAD local poly 0 must remap to obj.polygons[2], "
           ~ "NOT flat slot 0");
    assert(obj.vmads[0].values == [0.5f, 0.25f], "VMAD UV value round-trip");
}

// ---------------------------------------------------------------------------
// Stage 4 — write -> read field-equality round-trip of a FULL object, plus
// write -> read -> write BYTE-IDENTITY (the strongest self-consistency check).
//
// Exercises every emitted chunk: LAYR/TAGS/PNTS/BBOX/POLS FACE+PTCH/PTAG/SURF
// and crucially a MULTI-CHANNEL VMAP (two named TXUV maps) and TWO VMADs —
// one on a FACE poly, one on a PTCH poly — so the per-kind local<->global
// remap is exercised on BOTH kinds (single-kind constraint: each VMAD's polys
// all share one kind). All UV/PTAG state is keyed in obj.polygons[] space on
// both sides of the round-trip.
// ---------------------------------------------------------------------------
unittest
{
    Lwo2Object obj;
    obj.layerName = "Main";
    obj.points = [
        [0f, 0f, 0f], [1f, 0f, 0f], [1f, 1f, 0f], [0f, 1f, 0f], [0.5f, 2f, 0f]
    ];
    obj.surfaces = [
        Lwo2Surface("Body", [0.8f, 0.1f, 0.1f], 0.9f, 0.2f, 0.6f, 1.0f),
        Lwo2Surface("Roof", [0.1f, 0.1f, 0.8f], 1.0f, 0.5f, 0.3f, 0.4f),
    ];
    obj.polygons = [
        Lwo2Polygon([0, 1, 2, 3], 0, false), // obj.polygons[0]  FACE
        Lwo2Polygon([3, 2, 4],    1, true),  // obj.polygons[1]  PTCH
    ];

    // Multi-channel VMAP: two named TXUV maps over the points.
    Lwo2VertexMap uv0;
    uv0.type = "TXUV"; uv0.name = "UVChannel0"; uv0.dimension = 2;
    uv0.points = [0u, 1u, 2u, 3u];
    uv0.values = [0f,0f, 1f,0f, 1f,1f, 0f,1f];
    Lwo2VertexMap uv1;
    uv1.type = "TXUV"; uv1.name = "UVChannel1"; uv1.dimension = 2;
    uv1.points = [2u, 3u, 4u];
    uv1.values = [0.2f,0.3f, 0.4f,0.5f, 0.6f,0.7f];
    obj.vmaps = [uv0, uv1];

    // Two VMADs, one per kind. FACE VMAD binds obj.polygons[0] (FACE); PTCH
    // VMAD binds obj.polygons[1] (PTCH). Each is single-kind.
    Lwo2VertexMapD faceVmad;
    faceVmad.type = "TXUV"; faceVmad.name = "FaceCorners"; faceVmad.dimension = 2;
    faceVmad.points = [0u, 2u]; faceVmad.polys = [0u, 0u];
    faceVmad.values = [0.11f,0.12f, 0.13f,0.14f];
    Lwo2VertexMapD ptchVmad;
    ptchVmad.type = "TXUV"; ptchVmad.name = "PatchCorners"; ptchVmad.dimension = 2;
    ptchVmad.points = [4u]; ptchVmad.polys = [1u];
    ptchVmad.values = [0.91f, 0.92f];
    obj.vmads = [faceVmad, ptchVmad];

    auto bytes = buildLwo2(obj);
    auto back  = readLwo2(bytes);

    // --- field-by-field equality ------------------------------------------
    assert(back.layerName == obj.layerName);

    assert(back.points.length == obj.points.length);
    foreach (i; 0 .. obj.points.length)
        assert(back.points[i] == obj.points[i], "point changed");

    assert(back.polygons.length == obj.polygons.length);
    foreach (i; 0 .. obj.polygons.length)
    {
        assert(back.polygons[i].indices  == obj.polygons[i].indices);
        assert(back.polygons[i].subpatch == obj.polygons[i].subpatch);
        assert(back.polygons[i].surface  == obj.polygons[i].surface);
    }

    // VMAP: two channels, equal field-by-field (order preserved by the writer).
    assert(back.vmaps.length == 2, "two VMAP channels expected");
    foreach (i; 0 .. 2)
    {
        assert(back.vmaps[i].type      == obj.vmaps[i].type);
        assert(back.vmaps[i].name      == obj.vmaps[i].name);
        assert(back.vmaps[i].dimension == obj.vmaps[i].dimension);
        assert(back.vmaps[i].points    == obj.vmaps[i].points);
        assert(back.vmaps[i].values    == obj.vmaps[i].values,
               "VMAP values changed in round-trip");
    }

    // VMAD: two per-kind maps, polys keyed in obj.polygons[] space both sides.
    // The writer emits FACE-kind VMADs after the FACE POLS, then PTCH-kind
    // after the PTCH POLS — same order as authored here (face then ptch).
    assert(back.vmads.length == 2, "two VMADs expected (one per kind)");
    foreach (i; 0 .. 2)
    {
        assert(back.vmads[i].type      == obj.vmads[i].type);
        assert(back.vmads[i].name      == obj.vmads[i].name);
        assert(back.vmads[i].dimension == obj.vmads[i].dimension);
        assert(back.vmads[i].points    == obj.vmads[i].points);
        assert(back.vmads[i].polys     == obj.vmads[i].polys,
               "VMAD polys changed (local<->global remap broken?)");
        assert(back.vmads[i].values    == obj.vmads[i].values,
               "VMAD values changed in round-trip");
    }
    // Explicit: the FACE VMAD binds the FACE poly (slot 0), the PTCH VMAD the
    // PTCH poly (slot 1) — exercising the remap on BOTH kinds.
    assert(back.vmads[0].polys == [0u, 0u], "FACE VMAD -> obj.polygons[0]");
    assert(back.vmads[1].polys == [1u],     "PTCH VMAD -> obj.polygons[1]");

    // --- write -> read -> write BYTE-IDENTITY -----------------------------
    // POLS-local stays on disk; both directions agree, so re-serializing the
    // read-back object reproduces the original bytes exactly.
    auto bytes2 = buildLwo2(back);
    assert(bytes2.length == bytes.length,
           "write->read->write image length changed");
    assert(bytes2 == bytes,
           "write->read->write is not byte-identical (UV remap not inverse?)");
}

// ===========================================================================
// Stage 5 — golden fixture, consolidated edge tests, README polish.
// ===========================================================================

// ---------------------------------------------------------------------------
// Stage 5 — GOLDEN CUBE FIXTURE (writer-drift guard).
//
// FIXTURE DECISION: the golden bytes are EMBEDDED into the test binary via a
// string import (`import("cube_uv.lwo")`, with `tests/fixtures` on dub's
// `stringImportPaths`). The same bytes are ALSO committed as an actual
// `tests/fixtures/cube_uv.lwo` (regenerated by `tools/gen_cube_fixture.d`) so
// the file can be opened in a DCC — but the test gate does NOT depend on a
// runtime file path (which is fragile under dub's varying working directory).
// `import()` resolves at COMPILE time against `stringImportPaths`, so the test
// is deterministic and location-independent under `dub test --config=core`.
//
// The test rebuilds the SAME object the generator built (makeCubeUv below),
// re-reads the committed bytes, and asserts geometry + UV match field-by-field.
// If the writer's byte layout ever drifts, the committed file no longer decodes
// to the expected object and this fails loudly.
// ---------------------------------------------------------------------------

/// The deterministic golden cube — MUST stay in sync with
/// `tools/gen_cube_fixture.d`'s `makeCubeUv` (which produced the committed
/// `tests/fixtures/cube_uv.lwo`). A unit cube with one continuous TXUV VMAP and
/// one per-corner TXUV VMAD on the +Y face (obj.polygons[5]).
version(unittest)
private Lwo2Object makeGoldenCube()
{
    Lwo2Object obj;
    obj.layerName = "Cube";
    obj.points = [
        [-0.5f, -0.5f, -0.5f], [ 0.5f, -0.5f, -0.5f],
        [ 0.5f,  0.5f, -0.5f], [-0.5f,  0.5f, -0.5f],
        [-0.5f, -0.5f,  0.5f], [ 0.5f, -0.5f,  0.5f],
        [ 0.5f,  0.5f,  0.5f], [-0.5f,  0.5f,  0.5f],
    ];
    obj.surfaces = [ Lwo2Surface("Cube") ];
    obj.polygons = [
        Lwo2Polygon([0, 1, 2, 3], 0, false),
        Lwo2Polygon([5, 4, 7, 6], 0, false),
        Lwo2Polygon([4, 0, 3, 7], 0, false),
        Lwo2Polygon([1, 5, 6, 2], 0, false),
        Lwo2Polygon([4, 5, 1, 0], 0, false),
        Lwo2Polygon([3, 2, 6, 7], 0, false),
    ];
    Lwo2VertexMap uv;
    uv.type = "TXUV"; uv.name = "Texture"; uv.dimension = 2;
    foreach (i; 0 .. obj.points.length)
    {
        uv.points ~= cast(uint) i;
        uv.values ~= obj.points[i][0] + 0.5f;
        uv.values ~= obj.points[i][1] + 0.5f;
    }
    obj.vmaps ~= uv;
    Lwo2VertexMapD vmad;
    vmad.type = "TXUV"; vmad.name = "Texture"; vmad.dimension = 2;
    vmad.points = [3u, 2u, 6u, 7u];
    vmad.polys  = [5u, 5u, 5u, 5u];
    vmad.values = [0f,0f,  1f,0f,  1f,1f,  0f,1f];
    obj.vmads ~= vmad;
    return obj;
}

unittest
{
    // Embedded committed golden bytes (compile-time string import).
    static immutable string goldenStr = import("cube_uv.lwo");
    const(ubyte)[] golden = cast(const(ubyte)[]) goldenStr;
    assert(golden.length > 12, "golden cube fixture is empty/missing");
    assert(golden[0 .. 4] == cast(const(ubyte)[]) "FORM");
    assert(golden[8 .. 12] == cast(const(ubyte)[]) "LWO2");

    // The committed bytes must be EXACTLY what today's writer produces for the
    // golden object — the direct writer-drift gate.
    auto expected = makeGoldenCube();
    auto fresh = buildLwo2(expected);
    assert(fresh == golden,
           "committed cube_uv.lwo no longer matches the writer's output — "
           ~ "regenerate via `rdmd -Isource tools/gen_cube_fixture.d`");

    // And the reader reproduces the known geometry + UV from the committed file.
    auto back = readLwo2(golden);
    assert(back.layerName == "Cube");
    assert(back.points.length == 8);
    foreach (i; 0 .. 8)
        assert(back.points[i] == expected.points[i], "cube point changed");
    assert(back.polygons.length == 6, "cube has 6 faces");
    foreach (i; 0 .. 6)
    {
        assert(back.polygons[i].indices  == expected.polygons[i].indices);
        assert(!back.polygons[i].subpatch, "cube faces are FACE, not PTCH");
        assert(back.polygons[i].surface  == 0);
    }
    assert(back.surfaces.length == 1 && back.surfaces[0].name == "Cube");

    // VMAP (continuous) round-trips.
    assert(back.vmaps.length == 1);
    assert(back.vmaps[0].type == "TXUV" && back.vmaps[0].name == "Texture");
    assert(back.vmaps[0].dimension == 2);
    assert(back.vmaps[0].points == expected.vmaps[0].points);
    assert(back.vmaps[0].values == expected.vmaps[0].values, "cube VMAP UV changed");

    // VMAD (per-corner on +Y face) round-trips, polys keyed in obj.polygons[].
    assert(back.vmads.length == 1);
    assert(back.vmads[0].type == "TXUV" && back.vmads[0].name == "Texture");
    assert(back.vmads[0].points == [3u, 2u, 6u, 7u]);
    assert(back.vmads[0].polys  == [5u, 5u, 5u, 5u],
           "cube VMAD must bind obj.polygons[5] (the +Y face)");
    assert(back.vmads[0].values == expected.vmads[0].values, "cube VMAD UV changed");
}

// ---------------------------------------------------------------------------
// Stage 5 — VX 2-byte / 4-byte boundary, HAND-AUTHORED (probes the reader's
// primitive decode, not the writer's encode).
//
//   0xFEFF      -> a 2-byte U2 VX, value 65279 (just below the 0xFF00 boundary).
//   0xFF00 0xFF00 -> a 4-byte U4 VX, value 65280 (((0xFF00<<16)|0xFF00) & 0x00FFFFFF).
//
// This unittest covers the POINT VX (a polygon's vertex index); the next one
// covers the POLY VX (a PTAG poly index). Both buffers are built inline (no
// buildLwo2), so the VX decode itself is under test.
//
// A poly's vertex indices are stored verbatim (the reader does NOT bounds-check
// them against the point count), so a poly referencing points 65279 and 65280
// round-trips the raw decoded VX without authoring 65k PNTS.
// ---------------------------------------------------------------------------
version(unittest)
private struct VXBld
{
    ubyte[] b;
    void u2(ushort v) { b ~= cast(ubyte)(v >> 8); b ~= cast(ubyte)(v & 0xFF); }
    void u4(uint v)
    {
        b ~= cast(ubyte)(v >> 24); b ~= cast(ubyte)(v >> 16);
        b ~= cast(ubyte)(v >> 8);  b ~= cast(ubyte)(v & 0xFF);
    }
    void f4(float v) @trusted { u4(*cast(uint*) &v); }
    void id4(string s) { assert(s.length == 4); b ~= cast(const(ubyte)[]) s; }
    /// Emit a VX in its 2-byte form (caller guarantees value < 0xFF00).
    void vx2(uint v) { assert(v < 0xFF00); u2(cast(ushort) v); }
    /// Emit a VX in its 4-byte form: high u16 has top byte 0xFF.
    /// value = ((a<<16)|b) & 0x00FFFFFF. We choose a=0xFF00, b=0xFF00 for 65280.
    void vx4(ushort a, ushort b_) { assert(a >= 0xFF00); u2(a); u2(b_); }
    void s0(string s)
    {
        b ~= cast(const(ubyte)[]) s; b ~= cast(ubyte) 0;
        if (s.length % 2 == 0) b ~= cast(ubyte) 0;
    }
}

unittest
{
    // --- POINT VX boundary: a single FACE poly whose 2 vertex indices are the
    //     2-byte (65279) and 4-byte (65280) forms. Poly vertex indices are not
    //     bounds-checked against the point count, so this isolates VX decode.
    VXBld pnts; // minimal PNTS (1 point) — present so the chunk loop is happy.
    pnts.f4(0); pnts.f4(0); pnts.f4(0);

    VXBld pols;
    pols.id4("FACE");
    pols.u2(2);              // 2 vertices in this poly
    pols.vx2(0xFEFF);       // 65279 — exactly at the 2-byte boundary
    pols.vx4(0xFF00, 0xFF00); // 65280 — 4-byte form

    VXBld surf; surf.s0("S"); surf.s0("");

    ubyte[] payload;
    emitVX(payload, "PNTS", pnts.b);
    emitVX(payload, "POLS", pols.b);
    emitVX(payload, "SURF", surf.b);
    auto file = wrapVX(payload);

    auto obj = readLwo2(file);
    assert(obj.polygons.length == 1, "one FACE poly");
    assert(obj.polygons[0].indices.length == 2);
    assert(obj.polygons[0].indices[0] == 65279,
           "2-byte VX 0xFEFF must decode to 65279 (point VX)");
    assert(obj.polygons[0].indices[1] == 65280,
           "4-byte VX 0xFF00 0xFF00 must decode to 65280 (point VX)");
}

unittest
{
    // POLY VX boundary (the poly-index slot in a PTAG entry). Two buffers:
    //   (a) valid: a 2-byte poly VX (0) maps in range -> proves 2-byte decode.
    //   (b) a 4-byte poly VX (65280) out of range -> proves the reader decodes
    //       the 4-byte form AND range-checks it (typed throw, no crash).

    // Valid buffer: 1 PTCH poly, PTAG poly index 0 (2-byte form) -> tag 0.
    VXBld pnts; pnts.f4(0); pnts.f4(0); pnts.f4(0);
    pnts.f4(1); pnts.f4(0); pnts.f4(0);
    pnts.f4(1); pnts.f4(1); pnts.f4(0);
    VXBld pols; pols.id4("PTCH"); pols.u2(3); pols.vx2(0); pols.vx2(1); pols.vx2(2);
    VXBld ptag; ptag.id4("SURF"); ptag.vx2(0); ptag.u2(0); // 2-byte poly VX = 0
    VXBld surf; surf.s0("S"); surf.s0("");
    ubyte[] payload;
    emitVX(payload, "PNTS", pnts.b);
    emitVX(payload, "POLS", pols.b);
    emitVX(payload, "PTAG", ptag.b);
    emitVX(payload, "SURF", surf.b);
    auto obj = readLwo2(wrapVX(payload));
    assert(obj.polygons.length == 1 && obj.polygons[0].subpatch);
    assert(obj.polygons[0].surface == 0, "2-byte poly VX 0 -> tag 0");

    // Out-of-range 4-byte poly VX: PTAG entry's poly index = 65280 (4-byte) but
    // the POLS has 1 local poly -> the reader must decode the 4-byte VX and
    // throw a typed range error (not silently corrupt / crash).
    VXBld ptagBad; ptagBad.id4("SURF");
    ptagBad.vx4(0xFF00, 0xFF00); ptagBad.u2(0); // 4-byte poly VX = 65280, OOR
    ubyte[] payload2;
    emitVX(payload2, "PNTS", pnts.b);
    emitVX(payload2, "POLS", pols.b);
    emitVX(payload2, "PTAG", ptagBad.b);
    emitVX(payload2, "SURF", surf.b);
    bool threw = false;
    try { readLwo2(wrapVX(payload2)); }
    catch (Lwo2ReadException) { threw = true; }
    assert(threw,
           "4-byte poly VX 65280 out of range must throw Lwo2ReadException "
           ~ "(proves the 4-byte poly-VX decode + range check)");
}

// Inline chunk/wrapper emitters for the VX + edge tests (independent of writer).
version(unittest)
private void emitVX(ref ubyte[] out_, string id, const(ubyte)[] body_)
{
    assert(id.length == 4);
    out_ ~= cast(const(ubyte)[]) id;
    VXBld h; h.u4(cast(uint) body_.length);
    out_ ~= h.b;
    out_ ~= body_;
    if (body_.length & 1) out_ ~= cast(ubyte) 0;
}

version(unittest)
private ubyte[] wrapVX(const(ubyte)[] payload)
{
    ubyte[] file;
    file ~= cast(const(ubyte)[]) "FORM";
    VXBld len; len.u4(cast(uint)(4 + payload.length));
    file ~= len.b;
    file ~= cast(const(ubyte)[]) "LWO2";
    file ~= payload;
    return file;
}

// ---------------------------------------------------------------------------
// Stage 5 — EVEN-PAD on odd S0 names (hand-authored). S0 strings are NUL-
// terminated and padded so (chars + NUL) is even; the reader must consume the
// pad byte for an odd S0 and none for an even one. Two names of opposite parity
// in the same buffer exercise both branches of the reader's S0 pad accounting:
//   "Body" -> 4 chars + NUL = 5 (odd)  -> 1 S0 pad byte.
//   "Srf"  -> 3 chars + NUL = 4 (even) -> 0 S0 pad bytes.
// The matching odd-CHUNK-BODY even-pad path is covered by the ODDB test below.
// ---------------------------------------------------------------------------
unittest
{
    VXBld pnts; pnts.f4(0); pnts.f4(0); pnts.f4(0);
    pnts.f4(1); pnts.f4(0); pnts.f4(0); pnts.f4(1); pnts.f4(1); pnts.f4(0);
    VXBld pols; pols.id4("FACE"); pols.u2(3); pols.vx2(0); pols.vx2(1); pols.vx2(2);
    VXBld surf0; surf0.s0("Body"); surf0.s0(""); // even-name (1 S0 pad)
    VXBld surf1; surf1.s0("Srf");  surf1.s0("");  // odd-name  (0 S0 pad)
    // A VMAP whose name S0 also has a pad ("UV" -> 2+NUL=3 odd -> 1 pad).
    VXBld vmap; vmap.id4("TXUV"); vmap.u2(2); vmap.s0("UV");
    vmap.vx2(0); vmap.f4(0.1f); vmap.f4(0.2f);

    ubyte[] payload;
    emitVX(payload, "PNTS", pnts.b);
    emitVX(payload, "POLS", pols.b);
    emitVX(payload, "VMAP", vmap.b);
    emitVX(payload, "SURF", surf0.b);
    emitVX(payload, "SURF", surf1.b);
    auto obj = readLwo2(wrapVX(payload));

    assert(obj.surfaces.length == 2);
    assert(obj.surfaces[0].name == "Body", "even-S0-name (with pad) not recovered");
    assert(obj.surfaces[1].name == "Srf",  "odd-S0-name (no pad) not recovered");
    assert(obj.points.length == 3);
    assert(obj.vmaps.length == 1 && obj.vmaps[0].name == "UV",
           "VMAP name S0 pad not consumed");
}

// ---------------------------------------------------------------------------
// Stage 5 — ODD CHUNK BODY even-pad (hand-authored): inject a chunk whose body
// length is ODD and assert the reader resyncs to the next chunk past the IFF
// even pad byte. We use an unknown chunk "ODDB" with a 1-byte body (odd) placed
// BETWEEN two real chunks; the reader must skip its body + the 1 pad byte and
// still find the following SURF.
// ---------------------------------------------------------------------------
unittest
{
    VXBld pnts; pnts.f4(0); pnts.f4(0); pnts.f4(0);
    pnts.f4(1); pnts.f4(0); pnts.f4(0); pnts.f4(1); pnts.f4(1); pnts.f4(0);
    VXBld pols; pols.id4("FACE"); pols.u2(3); pols.vx2(0); pols.vx2(1); pols.vx2(2);
    VXBld surf; surf.s0("Body"); surf.s0("");

    ubyte[] oddBody = [ cast(ubyte) 0x7F ]; // length 1 (odd)
    ubyte[] payload;
    emitVX(payload, "PNTS", pnts.b);
    emitVX(payload, "ODDB", oddBody);       // odd body -> emitVX adds 1 even pad
    emitVX(payload, "POLS", pols.b);
    emitVX(payload, "SURF", surf.b);
    auto obj = readLwo2(wrapVX(payload));

    // The reader skipped the odd unknown chunk (body + pad) and still parsed the
    // POLS/SURF after it.
    assert(obj.points.length == 3, "PNTS before odd chunk parsed");
    assert(obj.polygons.length == 1, "POLS after odd-body chunk parsed");
    assert(obj.surfaces.length == 1 && obj.surfaces[0].name == "Body",
           "SURF after odd-body chunk parsed (chunk even-pad accounted)");
}

// ---------------------------------------------------------------------------
// Stage 5 — EMPTY-UV no-chunk promise (consolidated). An object with no vmaps
// and no vmads must round-trip with empty maps and the writer emits no VMAP/VMAD
// (the Stage 1 byte-identity guard already proves the writer side; here we prove
// the READER side reports empty for a hand-authored UV-free buffer).
// ---------------------------------------------------------------------------
unittest
{
    VXBld pnts; pnts.f4(0); pnts.f4(0); pnts.f4(0);
    pnts.f4(1); pnts.f4(0); pnts.f4(0); pnts.f4(1); pnts.f4(1); pnts.f4(0);
    VXBld pols; pols.id4("FACE"); pols.u2(3); pols.vx2(0); pols.vx2(1); pols.vx2(2);
    VXBld surf; surf.s0("Body"); surf.s0("");
    ubyte[] payload;
    emitVX(payload, "PNTS", pnts.b);
    emitVX(payload, "POLS", pols.b);
    emitVX(payload, "SURF", surf.b);
    auto obj = readLwo2(wrapVX(payload));
    assert(obj.vmaps.length == 0, "no VMAP chunk -> empty vmaps");
    assert(obj.vmads.length == 0, "no VMAD chunk -> empty vmads");
}

// ---------------------------------------------------------------------------
// Stage 5 — UNKNOWN-CHUNK SKIP (hand-authored): inject a junk "XXXX" chunk
// between real chunks and assert the reader ignores it and parses the rest.
// ---------------------------------------------------------------------------
unittest
{
    VXBld pnts; pnts.f4(0); pnts.f4(0); pnts.f4(0);
    pnts.f4(1); pnts.f4(0); pnts.f4(0); pnts.f4(1); pnts.f4(1); pnts.f4(0);
    VXBld pols; pols.id4("FACE"); pols.u2(3); pols.vx2(0); pols.vx2(1); pols.vx2(2);
    VXBld surf; surf.s0("Body"); surf.s0("");
    // Junk chunk with an EVEN body (4 arbitrary bytes) so we also cover the
    // even-body skip path (odd-body skip is covered by the ODDB test above).
    ubyte[] junk = [ cast(ubyte) 1, 2, 3, 4 ];

    ubyte[] payload;
    emitVX(payload, "PNTS", pnts.b);
    emitVX(payload, "XXXX", junk);
    emitVX(payload, "POLS", pols.b);
    emitVX(payload, "XXXX", junk);  // a second junk chunk for good measure
    emitVX(payload, "SURF", surf.b);
    auto obj = readLwo2(wrapVX(payload));

    assert(obj.points.length == 3, "PNTS before junk parsed");
    assert(obj.polygons.length == 1, "POLS between junk chunks parsed");
    assert(obj.surfaces.length == 1 && obj.surfaces[0].name == "Body",
           "SURF after junk parsed — unknown 'XXXX' chunks ignored");
}

// ---------------------------------------------------------------------------
// Stage 5 — TRUNCATED FILE -> typed Lwo2ReadException (does not crash/segfault).
//
// Take a valid hand-authored buffer and cut it mid-chunk. The reader's bounds
// checks must convert every short read into a typed throw. We probe a few cut
// points: in the FORM header, mid a chunk's declared body, and at the FORM
// length mismatch boundary.
// ---------------------------------------------------------------------------
unittest
{
    VXBld pnts; pnts.f4(0); pnts.f4(0); pnts.f4(0);
    pnts.f4(1); pnts.f4(0); pnts.f4(0); pnts.f4(1); pnts.f4(1); pnts.f4(0);
    VXBld pols; pols.id4("FACE"); pols.u2(3); pols.vx2(0); pols.vx2(1); pols.vx2(2);
    VXBld surf; surf.s0("Body"); surf.s0("");
    ubyte[] payload;
    emitVX(payload, "PNTS", pnts.b);
    emitVX(payload, "POLS", pols.b);
    emitVX(payload, "SURF", surf.b);
    auto full = wrapVX(payload);

    static bool throwsRead(const(ubyte)[] bytes)
    {
        try { readLwo2(bytes); return false; }
        catch (Lwo2ReadException) { return true; }
    }

    // 1) Cut to fewer than 12 bytes (no room for FORM/LWO2 header).
    assert(throwsRead(full[0 .. 6]),
           "header-truncated buffer must throw, not crash");

    // 2) Cut mid-chunk: keep the FORM/LWO2 header + the first chunk's id+len but
    //    drop most of its body. The FORM-length check (formLen+8 != size) fires
    //    first here, but either way it must be a typed throw.
    assert(throwsRead(full[0 .. 24]),
           "mid-chunk-truncated buffer must throw, not crash");

    // 3) Same image with a CORRECT FORM length but a final chunk whose declared
    //    size overruns the (truncated) file — exercises the per-chunk overrun
    //    guard rather than the FORM-length guard. Rebuild the FORM length to
    //    match the truncated length so we get past the header check.
    auto cut = full[0 .. full.length - 6].dup; // drop 6 bytes off the last chunk
    // Patch the FORM length field to (cut.length - 8) so the header check passes
    // and the per-chunk overrun check is the one that fires.
    uint newFormLen = cast(uint)(cut.length - 8);
    cut[4] = cast(ubyte)(newFormLen >> 24);
    cut[5] = cast(ubyte)(newFormLen >> 16);
    cut[6] = cast(ubyte)(newFormLen >> 8);
    cut[7] = cast(ubyte)(newFormLen & 0xFF);
    assert(throwsRead(cut),
           "chunk-overrun (declared size > remaining) must throw, not crash");
}
