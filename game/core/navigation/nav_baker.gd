class_name NavBaker
extends RefCounted
## Bakes a navigation mesh from a sector's static colliders at load time (P1-08).
## The template (`data/navigation/navmesh_droid.tres`) holds the agent size and
## parse settings: WORLD-layer static colliders only, so props without a
## collider (low rubble, tyres: MIN_COLLIDER_HEIGHT rule) don't block paths.
##
## Baking runs synchronously on the main thread (web has no threads). The time
## is printed so we can see its cost. If it gets too slow for big Zones, bake
## per sector at build time and save the result instead (P2-01).

const DEFAULT_TEMPLATE: String = "res://data/navigation/navmesh_droid.tres"


## Returns a new navigation mesh baked from the colliders under `source_root`.
## `source_root` must be inside the scene tree.
static func bake(source_root: Node, template: NavigationMesh) -> NavigationMesh:
	var navmesh: NavigationMesh = template.duplicate() as NavigationMesh
	var source: NavigationMeshSourceGeometryData3D = NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(navmesh, source, source_root)
	NavigationServer3D.bake_from_source_geometry_data(navmesh, source)
	return navmesh


## Bakes from `source_root` and adds the result as a NavigationRegion3D under
## `parent`, aligned with `source_root`. Returns the region.
static func add_region(
	parent: Node, source_root: Node3D, template: NavigationMesh = null
) -> NavigationRegion3D:
	if template == null:
		template = load(DEFAULT_TEMPLATE) as NavigationMesh
	var start_usec: int = Time.get_ticks_usec()
	var region: NavigationRegion3D = NavigationRegion3D.new()
	region.name = "Navigation"
	region.navigation_mesh = bake(source_root, template)
	parent.add_child(region)
	region.global_transform = source_root.global_transform
	print(
		(
			"[NAV] baked %d polygons from %s in %.1f ms"
			% [
				region.navigation_mesh.get_polygon_count(),
				source_root.name,
				(Time.get_ticks_usec() - start_usec) / 1000.0,
			]
		)
	)
	return region
