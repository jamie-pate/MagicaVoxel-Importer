# Godot-MagicaVoxel-Importer
A Plugin for the GodotEngine to import MagicaVoxel's .vox format as meshes
For Godot verision 3.4

## How-To
Download the Plugin and put it into your projects folder

To Start importing select a .vox file and press '(Re)Import'

Adjust the settings as needed.

* `root_scale`: Scale the entire mesh so the voxels are this distance from each other. default is 1.0 (1m in godot)
* `origin`: Whether to auto-center the vox or use the MagicaVoxel scene tree transformations
* `smoothing`: Gausian smoothing of normals in voxels. e.g. 5 will blend the normals of the 5 nearest voxels weighted by distance

## Animated Voxel Mesh

Use the bone_rig.gd script to apply an Area's CollisionShape with bone
names to each voxel and re-import with bones/weights

See the readme at https://github.com/jamie-pate/govox for examples and details.

## Utilities

`scale_obj.js`: Scales the vertices in an obj file. Useful when uploading to e.g. mixamo since the obj scale is different.

## Shader Parameters

The voxel shader has these important parameters as well as some of the regular spatial material parameters:

* `show_normals`: 0..1 Sets the mix of normal color that will be drawn. Useful for checking the normal smoothing.
* `show_bone_weights`: 0..1 Sets the mix of bone weight color that will be drawn. Requires `Copy Bones To Uv` to be set during import.
* `root_scale`: Voxel size for the imported model. Must match the `root_scale` used during import
* `lod_bias`: When to start skipping voxels for performance based on the voxel size on the screen. 1.0 will skip voxels once they overlap. 2.0 will skip twice as early, 0.5 will draw voxels twice as small, etc.

## XR testing

You need to install
* [Godot Openxr vendors addon](https://github.com/GodotVR/godot_openxr_vendors/releases/) for this to work
* [Android Build Template](https://docs.godotengine.org/en/stable/tutorials/export/android_gradle_build.html#set-up-the-gradle-build-environment)

