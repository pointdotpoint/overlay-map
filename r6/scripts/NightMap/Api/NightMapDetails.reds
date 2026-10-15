module NightMap

// Tooltip payload returned by NightMapLayerListener.GetDetails.
public class NightMapDetails {
    public let category: String;
    public let title: String;
    public let subtitle: String;
    public let description: String;
    public let rowKeys: array<String>;
    public let rowValues: array<String>;
    public let actionKeys: array<String>;
    public let actionLabels: array<String>;
    public let hasColor: Bool;
    public let color: HDRColor;   // tooltip category colour; unset = the layer category colour

    public static func Create(category: String, title: String) -> ref<NightMapDetails> {
        let d = new NightMapDetails();
        d.category = category;
        d.title = title;
        return d;
    }

    public func WithSubtitle(s: String) -> ref<NightMapDetails> {
        this.subtitle = s;
        return this;
    }

    // At most 6 rows; extra rows are ignored.
    public func AddRow(key: String, value: String) -> ref<NightMapDetails> {
        if ArraySize(this.rowKeys) < 6 {
            ArrayPush(this.rowKeys, key);
            ArrayPush(this.rowValues, value);
        }
        return this;
    }

    public func WithColor(c: HDRColor) -> ref<NightMapDetails> {
        this.color = c;
        this.hasColor = true;
        return this;
    }

    public func WithDescription(s: String) -> ref<NightMapDetails> {
        this.description = s;
        return this;
    }

    // At most 3 actions; extra actions are ignored.
    public func AddAction(keyLabel: String, label: String) -> ref<NightMapDetails> {
        if ArraySize(this.actionKeys) < 3 {
            ArrayPush(this.actionKeys, keyLabel);
            ArrayPush(this.actionLabels, label);
        }
        return this;
    }
}
