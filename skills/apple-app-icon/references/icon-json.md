# `icon.json`, as measured

Loaded on demand: read this when the generator needs changing, or when
something in the document is accepted and does not work.

The layered icon format is not published anywhere reachable, and its errors
name the symptom rather than the syntax ("Invalid color encoding, missing ':'
delimiter" — which names the delimiter and not the prefix). Everything below
was got by asking `ictool` directly: write a document, render it, read the
pixel back.

```bash
ICTOOL="/Applications/Xcode.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool"
"$ICTOOL" App.icon --export-image --output-file out.png \
    --platform iOS --rendition Dark --width 128 --height 128 --scale 1
```

`--rendition` takes: `Default`, `Dark`, `TintedLight`, `TintedDark`,
`ClearLight`, `ClearDark`. (`Clear` alone is rejected, and the error lists the
valid set — the one helpful message in the tool.)

## Shape of the document

```json
{
  "fill": { "linear-gradient": ["display-p3:0,0.56,1,1", "display-p3:1,0.6,0.07,1"] },
  "groups": [
    { "layers": [ { "image-name": "play.svg", "name": "Play",
                    "fill": { "solid": "display-p3:1,1,1,1" } } ],
      "shadow": { "kind": "neutral", "opacity": 0.4 },
      "specular": true,
      "translucency": { "enabled": false, "value": 0.0 } },
    { "layers": [ { "image-name": "background.svg", "name": "Background" } ],
      "shadow": { "kind": "neutral", "opacity": 0.0 },
      "specular": false,
      "translucency": { "enabled": false, "value": 0.0 } }
  ],
  "supported-platforms": { "squares": ["iOS", "macOS"], "circles": ["watchOS"] }
}
```

The bundle is a directory: `App.icon/icon.json` plus `App.icon/Assets/*.svg`.

## What holds, and how it was found

| Rule | How it showed up |
|---|---|
| A colour is `display-p3:r,g,b,a` | three components → "Expected four comma separated color components"; no prefix → "missing ':' delimiter" |
| `fill` accepts `{"solid": …}`, `{"linear-gradient": [a, b]}`, `{"automatic-gradient": …}` | `{"linear-gradient": {"colors": […], "angle": …}}` → "the data couldn't be read" |
| `linear-gradient` is **exactly two** colours | "Linear gradients require exactly 2 colors" |
| `fill` works on a **layer** | filled a white circle red: red on the layer, unchanged on the group |
| `fill` on a **group** is ignored | same test, `ictool` still returned 0 |
| `fill-specializations` on a group parses and does nothing | asked for red in `dark`, got the system's own colouring |
| `fill-specializations` on a layer breaks the document | "the data couldn't be read because it isn't in the correct format" |
| Groups draw **front to back** | background written first covered the mark; the icon rendered as a bare gradient square |
| SVG contours are **filled**, strokes ignored | `fill="none" stroke="#FFF"` rendered as a filled disc |

## What the system does that you cannot override

In **Dark**, the layers are re-coloured from what is behind them: a white mark
over a gradient background comes back rainbow — cyan at the top, amber at the
bottom. A white `fill` does not stop it, and neither does `specular: false`
(measured: the arc stayed at `(143, 95, 191)`).

Removing the background *layer* changes it — with only the document's two-colour
`fill` behind it, the same mark came back at `(41, 41, 41)`, i.e. the system dims
the whole tile properly. So the trade is:

| background as | Default | Dark / tinted |
|---|---|---|
| a **layer** (any number of stops) | exact | system cannot dim it; mark goes rainbow |
| the document's **`fill`** (two colours) | two stops only | dims correctly, mark reads clean |

A three-stop brand gradient and a correct dark appearance cannot both come out
of JSON. Choose, comment the choice, or set the dark fill by hand in Icon
Composer's own UI and stop regenerating that file.

## Reading the artwork instead of retyping it

```python
re.search(r"<linearGradient[^>]*>(.*?)</linearGradient>", svg, re.S)   # the stops
re.search(r'viewBox="0 0 ([\d.]+) ([\d.]+)"', svg)                     # the canvas
re.findall(r'<path d="([^"]+)"', svg)                                  # the shapes
```

Read the artboard's own numbers. The brand mark on one project is 431×429 —
not square and not the 512 the earlier file happened to be — and hard-coding
either puts the mark a few points off centre with nothing on screen to say why.
