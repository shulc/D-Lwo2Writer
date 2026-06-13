/// One-shot generator for the committed golden cube fixture
/// (`tests/fixtures/cube_uv.lwo`). Run from the repo root with:
///
///     rdmd -Isource tools/gen_cube_fixture.d
///
/// It is NOT part of the library build or `dub test`; it only regenerates the
/// committed golden bytes when the cube definition below changes deliberately.
/// The golden test in `lwo2.uvtests` reads the committed file (via a string
/// import) and asserts the reader reproduces this exact geometry + UV, which
/// fails loudly if the writer ever drifts.
module gen_cube_fixture;

import std.file : write, mkdirRecurse;
import lwo2.writer;

void main()
{
    Lwo2Object obj = makeCubeUv();
    auto bytes = buildLwo2(obj);
    mkdirRecurse("tests/fixtures");
    write("tests/fixtures/cube_uv.lwo", bytes);
}

/// The deterministic golden cube. Kept as a standalone function so the test can
/// build the SAME object and compare field-by-field against the re-read file.
Lwo2Object makeCubeUv()
{
    Lwo2Object obj;
    obj.layerName = "Cube";

    // Unit cube centred at the origin, 8 corners.
    obj.points = [
        [-0.5f, -0.5f, -0.5f], // 0
        [ 0.5f, -0.5f, -0.5f], // 1
        [ 0.5f,  0.5f, -0.5f], // 2
        [-0.5f,  0.5f, -0.5f], // 3
        [-0.5f, -0.5f,  0.5f], // 4
        [ 0.5f, -0.5f,  0.5f], // 5
        [ 0.5f,  0.5f,  0.5f], // 6
        [-0.5f,  0.5f,  0.5f], // 7
    ];

    obj.surfaces = [ Lwo2Surface("Cube") ];

    // Six quad faces (all FACE kind, single surface 0). Winding is consistent
    // outward but the exact winding is irrelevant to the fixture's purpose.
    obj.polygons = [
        Lwo2Polygon([0, 1, 2, 3], 0, false), // -Z
        Lwo2Polygon([5, 4, 7, 6], 0, false), // +Z
        Lwo2Polygon([4, 0, 3, 7], 0, false), // -X
        Lwo2Polygon([1, 5, 6, 2], 0, false), // +X
        Lwo2Polygon([4, 5, 1, 0], 0, false), // -Y
        Lwo2Polygon([3, 2, 6, 7], 0, false), // +Y
    ];

    // One continuous TXUV VMAP: a planar UV per point (x/y of the position
    // shifted into [0,1]). Deterministic; the values are not physically a real
    // unwrap, just a stable, distinct value per point.
    Lwo2VertexMap uv;
    uv.type      = "TXUV";
    uv.name      = "Texture";
    uv.dimension = 2;
    foreach (i; 0 .. obj.points.length)
    {
        uv.points ~= cast(uint) i;
        uv.values ~= obj.points[i][0] + 0.5f; // u
        uv.values ~= obj.points[i][1] + 0.5f; // v
    }
    obj.vmaps ~= uv;

    // One discontinuous TXUV VMAD: a per-corner override on the four corners of
    // the +Y face (obj.polygons[5]) so the read path exercises VMAD local->global
    // remap on a non-zero poly slot.
    Lwo2VertexMapD vmad;
    vmad.type      = "TXUV";
    vmad.name      = "Texture";
    vmad.dimension = 2;
    vmad.points    = [3u, 2u, 6u, 7u];
    vmad.polys     = [5u, 5u, 5u, 5u];        // obj.polygons[] space
    vmad.values    = [0f,0f,  1f,0f,  1f,1f,  0f,1f];
    obj.vmads ~= vmad;

    return obj;
}
