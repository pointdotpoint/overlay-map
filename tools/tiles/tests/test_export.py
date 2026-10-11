from nmtiles.export import style_for


def test_style_for_known_meshes():
    assert style_for("3dmap_terrain") == "land"
    assert style_for("3dmap_water") == "water"
    assert style_for("3dmap_cliffs") == "cliff"
    assert style_for("3dmap_roads") == "road"
    assert style_for("3dmap_roads_borders") == "road_border"
    assert style_for("3dmap_metro") == "metro"


def test_style_for_skips_collision_and_helpers():
    assert style_for("3dmap_coll_buildings2") is None
    assert style_for("3dmap_coll_roads") is None
    assert style_for("mappin_geo_bulb") is None
    assert style_for("3dmap_cursor") is None


def test_style_for_everything_else_is_building():
    assert style_for("3dmap_triangle_soup") == "building"
    assert style_for("rcr_park_ferris_wheel") == "building"
