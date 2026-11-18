extends RefCounted
# Mesh building helpers: coloured boxes, spheres, cylinders and cones. All static.

static var _shared := {}

# One material per colour, shared by every mesh that uses it. Only for meshes whose colour never
# changes (breakables): changing a shared material changes all of them.
static func shared(c: String) -> StandardMaterial3D:
	if not _shared.has(c):
		_shared[c] = mat(c)
	return _shared[c]

# Gives every mesh in a group the shared material of its colour.
static func share(n: Node3D) -> Node3D:
	for ch in n.get_children():
		if ch is MeshInstance3D and ch.mesh.material is StandardMaterial3D:
			ch.mesh.material = shared(ch.mesh.material.albedo_color.to_html(false))
	return n

static func mat(c) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(c) if c is String else c
	m.roughness = 0.8
	return m

static func _mi(mesh: PrimitiveMesh, c, x: float, y: float, z: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mesh.material = mat(c)
	mi.mesh = mesh
	mi.position = Vector3(x, y, z)
	return mi

static func box(w: float, h: float, d: float, c, x := 0.0, y := 0.0, z := 0.0) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = Vector3(w, h, d)
	return _mi(b, c, x, y, z)

static func ball(r: float, c, x := 0.0, y := 0.0, z := 0.0) -> MeshInstance3D:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2
	return _mi(s, c, x, y, z)

static func cyl(r: float, h: float, c, x := 0.0, y := 0.0, z := 0.0, top := -1.0) -> MeshInstance3D:
	var m := CylinderMesh.new()
	m.bottom_radius = r
	m.top_radius = r if top < 0 else top
	m.height = h
	return _mi(m, c, x, y, z)

static func cone(r: float, h: float, c, x := 0.0, y := 0.0, z := 0.0) -> MeshInstance3D:
	return cyl(r, h, c, x, y, z, 0.0)

static func fwd(n: MeshInstance3D) -> MeshInstance3D:
	n.rotation.x = PI / 2
	return n

static func grp(ch: Array) -> Node3D:
	var node := Node3D.new()
	for c in ch:
		node.add_child(c)
	return node
