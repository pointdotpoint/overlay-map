module OverlayMap

// Tooltip payload returned by OverlayMapLayerListener.GetDetails.
public class OverlayMapDetails {
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

    public static func Create(category: String, title: String) -> ref<OverlayMapDetails> {
        let d = new OverlayMapDetails();
        d.category = category;
        d.title = title;
        return d;
    }

    public func WithSubtitle(s: String) -> ref<OverlayMapDetails> {
        this.subtitle = s;
        return this;
    }

    // At most 6 rows; extra rows are ignored.
    public func AddRow(key: String, value: String) -> ref<OverlayMapDetails> {
        if ArraySize(this.rowKeys) < 6 {
            ArrayPush(this.rowKeys, key);
            ArrayPush(this.rowValues, value);
        }
        return this;
    }

    public func WithColor(c: HDRColor) -> ref<OverlayMapDetails> {
        this.color = c;
        this.hasColor = true;
        return this;
    }

    public func WithDescription(s: String) -> ref<OverlayMapDetails> {
        this.description = s;
        return this;
    }

    // At most 3 actions; extra actions are ignored.
    public func AddAction(keyLabel: String, label: String) -> ref<OverlayMapDetails> {
        if ArraySize(this.actionKeys) < 3 {
            ArrayPush(this.actionKeys, keyLabel);
            ArrayPush(this.actionLabels, label);
        }
        return this;
    }
}
