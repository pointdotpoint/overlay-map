module NightMap

// One pin per place: shots within Radius() (2D) of a newer shown shot fold into it.
public abstract class NMPhotoGroups {
    public static func Radius() -> Float { return 10.0; }

    // Indices of the shown spot per place. Greedy newest-first: each existing spot that is not within `radius`
    // of an already chosen spot starts a place. Spots with exists[i] == false are ignored.
    public static func Newest(spots: array<ref<NMPhotoSpot>>, exists: array<Bool>, radius: Float) -> array<Int32> {
        let order: array<Int32>;
        let i = 0;
        while i < ArraySize(spots) {
            if i < ArraySize(exists) && exists[i] {
                // insertion by created, newest first
                let k = 0;
                while k < ArraySize(order) && spots[order[k]].created >= spots[i].created {
                    k += 1;
                }
                ArrayInsert(order, k, i);
            }
            i += 1;
        }
        let r2 = radius * radius;
        let chosen: array<Int32>;
        for idx in order {
            let s = spots[idx];
            let taken = false;
            for c in chosen {
                let dx = spots[c].x - s.x;
                let dy = spots[c].y - s.y;
                if dx * dx + dy * dy <= r2 {
                    taken = true;
                    break;
                }
            }
            if !taken {
                ArrayPush(chosen, idx);
            }
        }
        return chosen;
    }
}
