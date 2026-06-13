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
