/// Adapter: assimp scene (bindbc-assimp6) -> `Lwo2Object` -> LWO2 file.
///
/// This is the "import anything assimp reads, save as LWO2" bridge. It merges
/// every mesh of an `aiScene` into one LWO2 layer, builds one surface per
/// assimp material (name + diffuse color), and maps each polygon to its
/// material via PTAG.
///
/// Requires the assimp library to be loaded first (`loadAssimp()`), since the
/// material readers below call into it.
///
/// Only compiled in the package's `full` configuration (the one that pulls in
/// bindbc-assimp6); the `core` configuration excludes this module so the
/// writer stays dependency-free.
module lwo2.assimp;

import bindbc.assimp;
import lwo2.writer;

/// Convert an imported assimp scene into a single-layer `Lwo2Object`.
///
/// Coordinates are copied verbatim (no handedness conversion). Polygons keep
/// their assimp winding. Faces with fewer than 2 indices (points) are dropped.
Lwo2Object fromAiScene(const(aiScene)* scene)
{
    assert(scene !is null, "fromAiScene: null scene");

    Lwo2Object obj;

    // One surface per material; assimp scenes usually carry at least one.
    immutable uint nmat = scene.mNumMaterials;
    if (nmat == 0)
    {
        obj.surfaces ~= Lwo2Surface("Default");
    }
    else
    {
        foreach (i; 0 .. nmat)
        {
            const(aiMaterial)* m = scene.mMaterials[i];
            Lwo2Surface s;
            s.name = materialName(m, i);
            s.baseColor = materialDiffuse(m);
            obj.surfaces ~= s;
        }
    }

    // Merge all meshes into one point/polygon list, offsetting indices.
    uint offset = 0;
    foreach (mi; 0 .. scene.mNumMeshes)
    {
        const(aiMesh)* mesh = scene.mMeshes[mi];
        if (mesh is null || mesh.mVertices is null)
            continue;

        foreach (vi; 0 .. mesh.mNumVertices)
        {
            const v = mesh.mVertices[vi];
            obj.points ~= cast(float[3]) [cast(float) v.x, cast(float) v.y, cast(float) v.z];
        }

        uint surf = (nmat == 0) ? 0 : mesh.mMaterialIndex;
        if (surf >= obj.surfaces.length)
            surf = 0;

        foreach (fi; 0 .. mesh.mNumFaces)
        {
            const aiFace f = mesh.mFaces[fi];
            if (f.mNumIndices < 2)
                continue;            // drop points / degenerate

            Lwo2Polygon poly;
            poly.surface = surf;
            poly.indices.length = f.mNumIndices;
            foreach (k; 0 .. f.mNumIndices)
                poly.indices[k] = f.mIndices[k] + offset;
            obj.polygons ~= poly;
        }

        offset += mesh.mNumVertices;
    }

    return obj;
}

/// Convenience: import-conversion in one call. Writes `scene` to `path` as LWO2.
void exportSceneToLwo2(const(aiScene)* scene, string path)
{
    writeLwo2File(path, fromAiScene(scene));
}

// ---------------------------------------------------------------------------
// material readers
// ---------------------------------------------------------------------------

private string materialName(const(aiMaterial)* m, uint fallbackIndex)
{
    aiString s;
    if (aiGetMaterialString(m, AI_MATKEY_NAME.key, AI_MATKEY_NAME.semantic,
                            AI_MATKEY_NAME.index, &s) == aiReturn.SUCCESS && s.length > 0)
        return cast(string) s.data[0 .. s.length].idup;

    import std.conv : to;
    return "Surface." ~ to!string(fallbackIndex);
}

private float[3] materialDiffuse(const(aiMaterial)* m)
{
    aiColor4D c;
    if (aiGetMaterialColor(m, AI_MATKEY_COLOR_DIFFUSE.key, AI_MATKEY_COLOR_DIFFUSE.semantic,
                           AI_MATKEY_COLOR_DIFFUSE.index, &c) == aiReturn.SUCCESS)
        return [c.r, c.g, c.b];
    return [0.7f, 0.7f, 0.7f];
}
