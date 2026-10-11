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


def test_style_for_unknown_and_local_space_props_are_not_styled():
    # building style now comes only from the baked 3dmap boxes
    for stem in ("3dmap_triangle_soup", "3dmap_ext_monument_av_building_b", "3dmap_obelisk",
                 "3dmap_statue_splash_a", "cz_cz_building_h_icosphere", "monument_ave_pyramid",
                 "northoak_sign_a", "rcr_park_ferris_wheel", "something_unknown"):
        assert style_for(stem) is None


def test_building_regexes_match_only_the_point_cloud_sources():
    import re
    from nmtiles.export import BUILDING_JSON_REGEX, BUILDING_REGEX
    base = "base\\entities\\cameras\\3dmap\\"
    tex = "base\\fx\\textures\\3dmap\\static\\"
    for ok in (base + "3dmap_triangle_soup.mesh", base + "3dmap_view.ent", tex + "city_center_data.xbm"):
        assert re.search(BUILDING_REGEX, ok)
    for no in (base + "3dmap_roads.mesh", tex + "city_center_m.xbm"):
        assert not re.search(BUILDING_REGEX, no)
    assert re.search(BUILDING_JSON_REGEX, "/x/base/fx/textures/3dmap/static/city_center_data.xbm")
    assert not re.search(BUILDING_JSON_REGEX, "/x/base/fx/textures/3dmap/static/city_center_m.xbm")
