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

Use the BoneRig.gd script to apply an Area's CollisionShape with bone
names to each voxel and re-import with bones/weights

See the readme at https://github.com/jamie-pate/govox for examples and details.

