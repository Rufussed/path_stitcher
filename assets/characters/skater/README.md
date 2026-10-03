# Skater asset

Edit `skater.blend` in Blender and save it. Godot watches this file and automatically reimports the mesh and animations. Keep the action names and rig/node names stable so game references continue to work.

One character mesh (8,574 vertices; 16,318 triangles), one material, and one 79-bone skeleton are shared by both actions:

- `kick`: from Downloads/Skateboarding.fbx, frames 1–66 at 30 FPS.
- `skate`: from Downloads/Skateboarding (1).fbx, frames 1–31 at 30 FPS.

`skate` has horizontal motion removed in Blender world XY; vertical motion is retained. This corresponds to Godot world XZ after import. `kick` instead anchors the left ankle (`mixamorig:LeftFoot`) to its first-frame world XYZ position. Hips translation is compensated at four samples per frame so the rest of the character moves relative to the planted ankle. Foot rotation is preserved, so this anchors the ankle rather than rigidly locking the entire sole. The original FBX files in Downloads are unchanged.

The actions are retained with fake users and muted NLA tracks. To preview/edit an action, choose it in the Action Editor on SkaterRig. Godot imports both actions into the asset's AnimationPlayer. Instance the .blend asset under the game's character object to use the shared mesh and rig; no second mesh is needed to switch animations. Animations target this skeleton and would require retargeting for a differently named or structured rig.

All character textures are 512×512 external WebP files. Diffuse uses quality 45 and specular quality 55. Normal uses lossless WebP after vector renormalization during resizing to avoid lossy color compression artifacts. Diffuse is sRGB; normal and specular are Non-Color. Relative texture paths keep the asset folder portable.

Godot automatically enabled mipmaps and VRAM compression for the diffuse and normal maps. The normal map is recognized as a normal texture. The source specular map is retained in Blender, but Godot's imported StandardMaterial3D does not expose that texture as a specular map.

This preparation covers this character's textures. Gameplay wiring and existing environment textures have not been changed.

Godot animation key reduction is disabled for this asset’s AnimationPlayer to preserve the planted left ankle. Verified kick playback drift is below 0.004 mm at sampled frames and below 2 mm between frames at 30 FPS. Future changes to kick bone rotations may require rebaking the ankle compensation. The fixed anchor is the ankle position; foot rotation remains animated.
