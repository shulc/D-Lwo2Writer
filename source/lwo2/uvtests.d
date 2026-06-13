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
// fields) must produce EXACTLY the pre-change writer bytes — no VMAP/VMAD
// chunk, identical length. The golden buffer below was captured from the
// writer BEFORE the carrier fields were added (the existing inline quad+tri
// sample), so this asserts the new fields are wholly inert.
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

    // Pre-change golden output of the same object (captured from the writer
    // before vmaps/vmads existed). Byte-identical == empty maps emit nothing.
    static immutable ubyte[] golden = [
        70,79,82,77,0,0,1,124,76,87,79,50,76,65,89,82,0,0,0,18,0,0,0,0,0,0,0,0,
        0,0,0,0,0,0,0,0,0,0,84,65,71,83,0,0,0,12,66,111,100,121,0,0,82,111,111,
        102,0,0,80,78,84,83,0,0,0,60,0,0,0,0,0,0,0,0,0,0,0,0,63,128,0,0,0,0,0,0,
        0,0,0,0,63,128,0,0,63,128,0,0,0,0,0,0,0,0,0,0,63,128,0,0,0,0,0,0,63,0,0,
        0,64,0,0,0,0,0,0,0,66,66,79,88,0,0,0,24,0,0,0,0,0,0,0,0,0,0,0,0,63,128,
        0,0,64,0,0,0,0,0,0,0,80,79,76,83,0,0,0,14,70,65,67,69,0,4,0,0,0,1,0,2,0,
        3,80,79,76,83,0,0,0,12,80,84,67,72,0,3,0,3,0,2,0,4,80,84,65,71,0,0,0,12,
        83,85,82,70,0,0,0,0,0,1,0,1,83,85,82,70,0,0,0,76,66,111,100,121,0,0,0,0,
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
