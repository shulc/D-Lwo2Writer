/// Import any assimp-supported model and save it as LWO2.
///
///   dub run :convert -- input.fbx output.lwo
module app;

import std.stdio     : stderr, writefln;
import std.string    : toStringz;
import std.exception : enforce;

import bindbc.assimp;
import lwo2.assimp;

int main(string[] args)
{
    if (args.length != 3)
    {
        stderr.writefln("usage: %s <input-model> <output.lwo>", args[0]);
        return 1;
    }

    enforce(loadAssimp() == AssimpSupport.loaded, "failed to load libassimp");
    scope (exit) unloadAssimp();

    const(aiScene)* scene = aiImportFile(
        args[1].toStringz,
        aiProcess_Triangulate | aiProcess_JoinIdenticalVertices);
    enforce(scene !is null, "import failed: " ~ args[1]);
    scope (exit) aiReleaseImport(scene);

    exportSceneToLwo2(scene, args[2]);
    writefln("wrote %s  (%d meshes, %d materials)",
             args[2], scene.mNumMeshes, scene.mNumMaterials);
    return 0;
}
