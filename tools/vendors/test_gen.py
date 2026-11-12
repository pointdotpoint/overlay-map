from tools.vendors.gen import build, reds, shop_key

LOC = {"1": "Ginger Panda", "2": "Food Vendor", "3": "Food Vendor", "4": "Chang-Hoon Nam", "5": "Fingers M.D.",
       "6": "Straight Shooters"}


def flats(**names):
    return {f"Vendors.{k}.localizedName": v for k, v in names.items()}


def test_shop_key_normalizes_type_spellings():
    assert shop_key("wbr_jpn_food_04") == shop_key("wbr_jpn_foodshop_04") == ("wbr_jpn", "food", 4)
    assert shop_key("wbr_hil_ripperdoc_01") == shop_key("wbr_hil_ripdoc_01")
    assert shop_key("bls_ina_se1_foodshop_03") == ("bls_ina_se1", "food", 3)


def test_alias_to_differently_spelled_record():
    aliases, _, _ = build([("wbr_jpn_food_04", "ServicePointFoodVariant")],
                          flats(wbr_jpn_foodshop_04="LocKey#1"), LOC)
    assert aliases == {"wbr_jpn_food_04": "wbr_jpn_foodshop_04"}


def test_shared_wording_is_generic_whatever_the_key():
    aliases, generic, _ = build([("std_arr_food_01", "ServicePointFoodVariant")],
                                flats(std_arr_foodshop_01="LocKey#2", hey_rey_foodshop_03="LocKey#3"), LOC)
    assert aliases == {} and generic == {"LocKey#2", "LocKey#3"}


def test_record_of_another_service_is_not_used():
    aliases, _, _ = build([("wbr_jpn_netrunner_02", "ServicePointRipperdocVariant")],
                          flats(wbr_jpn_netrunner_02="LocKey#4", wbr_jpn_ripperdoc_02="LocKey#5"), LOC)
    assert aliases == {"wbr_jpn_netrunner_02": "wbr_jpn_ripperdoc_02"}
    aliases, _, _ = build([("wbr_jpn_netrunner_02", "ServicePointRipperdocVariant")],
                          flats(wbr_jpn_netrunner_02="LocKey#4"), LOC)
    assert aliases == {"wbr_jpn_netrunner_02": "-"}


def test_unknown_type_id_is_not_guessed_by_number():
    aliases, _, _ = build([("wat_kab_gun_trainer_01", "ServicePointGunsVariant")],
                          flats(wat_kab_gunsmith_01="LocKey#6"), LOC)
    assert aliases == {}


def test_reds_lists_aliases_and_generic_keys():
    out = reds({"a_b_food_01": "a_b_foodshop_01"}, {"LocKey#2"})
    assert 'case "a_b_food_01": return "a_b_foodshop_01";' in out and 'case "LocKey#2":' in out
