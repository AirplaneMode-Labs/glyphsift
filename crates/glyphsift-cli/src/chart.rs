//! The score-versus-noise chart as a deterministic, inert SVG.
//!
//! Form: line chart, emphasis style. One accent hue carries the headline (the mixed family: the mean
//! over the seeds bold, a min-to-max band behind it); every other family is a thin gray line, the
//! triggering families solid and the "none directly" families dashed, so the distinction does not
//! rest on colour. The x positions are the seven schedule steps, equally spaced.
//!
//! Determinism and safety: integer coordinates only, a fixed palette, no timestamp, no CSS, no
//! script, no event handlers, no links, no external reference of any kind; every piece of text is
//! XML-escaped. Colours are the validated light-surface palette of the lab's chart method (accent
//! `#2a78d6` passes its lightness, chroma and contrast gates on `#fcfcfb`); the chart draws its own
//! opaque surface so it reads the same on any README theme.

use std::fmt::Write as _;

use glyphsift_core::corrupt::{Family, SCHEDULE, Strength};

use crate::bench::Row;

const W: i64 = 960;
const H: i64 = 540;
const X0: i64 = 100;
const STEP: i64 = 130;
const Y_TOP: i64 = 130;
const Y_BOTTOM: i64 = 440;

const SURFACE: &str = "#fcfcfb";
const INK: &str = "#0b0b0b";
const INK_2: &str = "#52514e";
const GRID: &str = "#e1e0d9";
const AXIS: &str = "#c3c2b7";
const ACCENT: &str = "#2a78d6";
// The accent at 15% over the surface, as a solid colour so no fractional opacity is needed.
const BAND: &str = "#dde8f5";
const CONTEXT: &str = "#898781";

/// Escape text for an XML text node or a double-quoted attribute.
pub fn xml_escape(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    for c in s.chars() {
        match c {
            '&' => out.push_str("&amp;"),
            '<' => out.push_str("&lt;"),
            '>' => out.push_str("&gt;"),
            '"' => out.push_str("&quot;"),
            '\'' => out.push_str("&apos;"),
            c => out.push(c),
        }
    }
    out
}

fn x_at(k: usize) -> i64 {
    X0 + STEP * k as i64
}

/// The lower end of the y axis in ppm: the largest multiple of 0.1 that leaves at least 0.02 of
/// room below the lowest point drawn, never above 0.9. Derived from the data so the headline curve
/// is not squashed into the top of a 0 to 1 axis; the axis title says where it starts.
fn axis_floor(lowest: u64) -> u64 {
    (lowest.saturating_sub(20_000) / 100_000 * 100_000).min(900_000)
}

/// Score in ppm to a y coordinate on an axis that runs from `floor` to 1_000_000, rounded half up
/// in integer arithmetic; scores outside the axis are clamped to its ends.
fn y_at(ppm: u64, floor: u64) -> i64 {
    let span = (1_000_000 - floor) as i64;
    let v = (ppm.clamp(floor, 1_000_000) - floor) as i64;
    Y_BOTTOM - (v * (Y_BOTTOM - Y_TOP) + span / 2) / span
}

/// `0.6`-style tick label from ppm (a multiple of 0.1): `0`, `0.6`, `1`.
fn tick_label(ppm: u64) -> String {
    if ppm.is_multiple_of(1_000_000) {
        return (ppm / 1_000_000).to_string();
    }
    format!("0.{}", ppm / 100_000)
}

/// `0.6231`-style figure from ppm, truncated to four decimals with integer arithmetic.
fn fmt4(ppm: u64) -> String {
    format!("{}.{:04}", ppm / 1_000_000, (ppm % 1_000_000) / 100)
}

/// Mean (floor), minimum and maximum of a family's score at schedule step `k` over the seeds.
fn stats(rows: &[Row], family: &str, k: usize) -> (u64, u64, u64) {
    let scores: Vec<u64> = rows
        .iter()
        .filter(|r| r.family == family && r.p == SCHEDULE[k])
        .map(|r| r.score_ppm)
        .collect();
    if scores.is_empty() {
        return (0, 0, 0);
    }
    let sum: u64 = scores.iter().sum();
    (
        sum / scores.len() as u64,
        scores.iter().copied().min().unwrap_or(0),
        scores.iter().copied().max().unwrap_or(0),
    )
}

fn polyline(points: &[(i64, i64)]) -> String {
    points
        .iter()
        .map(|(x, y)| format!("{x},{y}"))
        .collect::<Vec<_>>()
        .join(" ")
}

/// Render the chart for `rows` (the benchmark's rows for every family and `mixed`).
pub fn svg(rows: &[Row]) -> String {
    let mixed: Vec<(u64, u64, u64)> = (0..SCHEDULE.len())
        .map(|k| stats(rows, "mixed", k))
        .collect();
    let trigger: Vec<Family> = Family::ALL
        .iter()
        .copied()
        .filter(|f| f.strength() == Strength::Triggering)
        .collect();
    let none: Vec<Family> = Family::ALL
        .iter()
        .copied()
        .filter(|f| f.strength() == Strength::NoneDirectly)
        .collect();

    let last = SCHEDULE.len() - 1;
    let none_ends: Vec<u64> = none.iter().map(|f| stats(rows, f.name(), last).0).collect();
    let none_lo = none_ends.iter().copied().min().unwrap_or(0);
    let none_hi = none_ends.iter().copied().max().unwrap_or(0);
    // The lowest point of anything drawn: a family mean or the lower edge of the mixed band.
    let lowest = (0..SCHEDULE.len())
        .flat_map(|k| {
            trigger
                .iter()
                .chain(none.iter())
                .map(move |f| (f.name(), k))
                .chain(std::iter::once(("mixed", k)))
        })
        .map(|(name, k)| {
            let (mean, min, _) = stats(rows, name, k);
            if name == "mixed" { min } else { mean }
        })
        .min()
        .unwrap_or(0);
    let floor = axis_floor(lowest);
    let desc = format!(
        "Line chart of the document score against the noise level p, for p = 0 to {}. The mixed \
         family's mean over the seeds falls from {} at p = {} to {} at p = {}. The {} triggering \
         families each fall as p rises. The {} none-directly families end between {} and {} at \
         p = {}. The data is in docs/score-vs-noise.csv.",
        SCHEDULE[last],
        fmt4(mixed[0].0),
        SCHEDULE[0],
        fmt4(mixed[last].0),
        SCHEDULE[last],
        trigger.len(),
        none.len(),
        fmt4(none_lo),
        fmt4(none_hi),
        SCHEDULE[last],
    );

    let mut s = String::with_capacity(16 * 1024);
    let _ = writeln!(
        s,
        "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"{W}\" height=\"{H}\" viewBox=\"0 0 {W} {H}\" \
         role=\"img\" aria-labelledby=\"t d\" font-family=\"system-ui, -apple-system, Segoe UI, sans-serif\">"
    );
    let _ = writeln!(
        s,
        "<title id=\"t\">Document score versus synthetic OCR noise</title>"
    );
    let _ = writeln!(s, "<desc id=\"d\">{}</desc>", xml_escape(&desc));
    let _ = writeln!(
        s,
        "<rect x=\"0\" y=\"0\" width=\"{W}\" height=\"{H}\" fill=\"{SURFACE}\"/>"
    );
    let _ = writeln!(
        s,
        "<rect x=\"1\" y=\"1\" width=\"{}\" height=\"{}\" fill=\"none\" stroke=\"{GRID}\" stroke-width=\"1\"/>",
        W - 2,
        H - 2
    );

    // Title, subtitle.
    let _ = writeln!(
        s,
        "<text x=\"40\" y=\"40\" font-size=\"18\" font-weight=\"600\" fill=\"{INK}\">{}</text>",
        xml_escape("Document score versus synthetic OCR noise")
    );
    let _ = writeln!(
        s,
        "<text x=\"40\" y=\"62\" font-size=\"12\" fill=\"{INK_2}\">{}</text>",
        xml_escape(
            "Synthetic Hindi and Marathi corpus, seeds 1 to 3. A score of 1 is clean; each step corrupts a larger share of eligible sites."
        )
    );

    // Legend: identity is never colour alone.
    let _ = writeln!(
        s,
        "<rect x=\"40\" y=\"88\" width=\"24\" height=\"12\" fill=\"{BAND}\"/>"
    );
    let _ = writeln!(
        s,
        "<line x1=\"40\" y1=\"94\" x2=\"64\" y2=\"94\" stroke=\"{ACCENT}\" stroke-width=\"3\" stroke-linecap=\"round\"/>"
    );
    let _ = writeln!(
        s,
        "<text x=\"72\" y=\"98\" font-size=\"12\" fill=\"{INK_2}\">{}</text>",
        xml_escape("Mixed: mean of seeds, band is min to max")
    );
    let _ = writeln!(
        s,
        "<line x1=\"360\" y1=\"94\" x2=\"384\" y2=\"94\" stroke=\"{CONTEXT}\" stroke-width=\"1\"/>"
    );
    let _ = writeln!(
        s,
        "<text x=\"392\" y=\"98\" font-size=\"12\" fill=\"{INK_2}\">{}</text>",
        xml_escape(&format!(
            "{} triggering families (seed mean)",
            trigger.len()
        ))
    );
    let _ = writeln!(
        s,
        "<line x1=\"640\" y1=\"94\" x2=\"664\" y2=\"94\" stroke=\"{CONTEXT}\" stroke-width=\"1\" stroke-dasharray=\"4 3\"/>"
    );
    let _ = writeln!(
        s,
        "<text x=\"672\" y=\"98\" font-size=\"12\" fill=\"{INK_2}\">{}</text>",
        xml_escape(&format!("{} none-directly families", none.len()))
    );

    // Axes and gridlines.
    let _ = writeln!(
        s,
        "<text x=\"40\" y=\"116\" font-size=\"12\" fill=\"{INK_2}\">{}</text>",
        xml_escape(&format!(
            "Score (1 = clean); the axis starts at {}",
            tick_label(floor)
        ))
    );
    let mut tick = floor;
    while tick <= 1_000_000 {
        let (v, label) = (tick, tick_label(tick));
        tick += 100_000;
        let y = y_at(v, floor);
        let color = if v == floor { AXIS } else { GRID };
        let _ = writeln!(
            s,
            "<line x1=\"{X0}\" y1=\"{y}\" x2=\"{}\" y2=\"{y}\" stroke=\"{color}\" stroke-width=\"1\"/>",
            x_at(last)
        );
        let _ = writeln!(
            s,
            "<text x=\"{}\" y=\"{}\" font-size=\"12\" text-anchor=\"end\" fill=\"{INK_2}\">{}</text>",
            X0 - 8,
            y + 4,
            xml_escape(&label)
        );
    }
    for (k, label) in SCHEDULE.iter().enumerate() {
        let _ = writeln!(
            s,
            "<text x=\"{}\" y=\"{}\" font-size=\"12\" text-anchor=\"middle\" fill=\"{INK_2}\">{}</text>",
            x_at(k),
            Y_BOTTOM + 22,
            xml_escape(label)
        );
    }
    let _ = writeln!(
        s,
        "<text x=\"{}\" y=\"{}\" font-size=\"12\" text-anchor=\"middle\" fill=\"{INK_2}\">{}</text>",
        (X0 + x_at(last)) / 2,
        Y_BOTTOM + 52,
        xml_escape(
            "Noise level p: share of eligible sites corrupted (steps are equally spaced, not to scale)"
        )
    );

    // The min-to-max band of the mixed family: upper edge left to right, lower edge back.
    let mut band: Vec<(i64, i64)> = (0..SCHEDULE.len())
        .map(|k| (x_at(k), y_at(mixed[k].2, floor)))
        .collect();
    band.extend(
        (0..SCHEDULE.len())
            .rev()
            .map(|k| (x_at(k), y_at(mixed[k].1, floor))),
    );
    let _ = writeln!(
        s,
        "<polygon points=\"{}\" fill=\"{BAND}\"/>",
        polyline(&band)
    );

    // Context lines: none-directly dashed first, triggering solid on top.
    for family in &none {
        let pts: Vec<(i64, i64)> = (0..SCHEDULE.len())
            .map(|k| (x_at(k), y_at(stats(rows, family.name(), k).0, floor)))
            .collect();
        let _ = writeln!(
            s,
            "<polyline points=\"{}\" fill=\"none\" stroke=\"{CONTEXT}\" stroke-width=\"1\" stroke-dasharray=\"4 3\" \
             stroke-linejoin=\"round\" stroke-linecap=\"round\"/>",
            polyline(&pts)
        );
    }
    for family in &trigger {
        let pts: Vec<(i64, i64)> = (0..SCHEDULE.len())
            .map(|k| (x_at(k), y_at(stats(rows, family.name(), k).0, floor)))
            .collect();
        let _ = writeln!(
            s,
            "<polyline points=\"{}\" fill=\"none\" stroke=\"{CONTEXT}\" stroke-width=\"1\" \
             stroke-linejoin=\"round\" stroke-linecap=\"round\"/>",
            polyline(&pts)
        );
    }

    // The headline: the mixed mean, bold, with a ringed marker per step and the end value labelled.
    let mean: Vec<(i64, i64)> = (0..SCHEDULE.len())
        .map(|k| (x_at(k), y_at(mixed[k].0, floor)))
        .collect();
    let _ = writeln!(
        s,
        "<polyline points=\"{}\" fill=\"none\" stroke=\"{ACCENT}\" stroke-width=\"3\" \
         stroke-linejoin=\"round\" stroke-linecap=\"round\"/>",
        polyline(&mean)
    );
    for (x, y) in &mean {
        let _ = writeln!(
            s,
            "<circle cx=\"{x}\" cy=\"{y}\" r=\"4\" fill=\"{ACCENT}\" stroke=\"{SURFACE}\" stroke-width=\"2\"/>"
        );
    }
    // One selective direct label besides the headline: the triggering family that ends lowest.
    if let Some((name, end)) = trigger
        .iter()
        .map(|f| (f.name(), stats(rows, f.name(), last).0))
        .min_by_key(|&(_, v)| v)
    {
        let _ = writeln!(
            s,
            "<text x=\"{}\" y=\"{}\" font-size=\"12\" text-anchor=\"end\" fill=\"{INK_2}\">{}</text>",
            x_at(last),
            y_at(end, floor) + 20,
            xml_escape(&format!("{name} {}", fmt4(end)))
        );
    }
    let (ex, ey) = mean[last];
    let _ = writeln!(
        s,
        "<text x=\"{}\" y=\"{}\" font-size=\"12\" font-weight=\"600\" fill=\"{INK}\">{}</text>",
        ex + 12,
        ey + 4,
        xml_escape(&fmt4(mixed[last].0))
    );

    let _ = writeln!(
        s,
        "<text x=\"40\" y=\"{}\" font-size=\"11\" fill=\"{INK_2}\">{}</text>",
        H - 16,
        xml_escape(
            "Source: docs/score-vs-noise.csv. Weights: crates/glyphsift-core/weights/devanagari.toml. Command: see the README."
        )
    );
    s.push_str("</svg>\n");
    s
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn escape_neutralises_markup_and_quotes() {
        assert_eq!(
            xml_escape("<script>alert(\"x\" & 'y')</script>"),
            "&lt;script&gt;alert(&quot;x&quot; &amp; &apos;y&apos;)&lt;/script&gt;"
        );
        assert_eq!(xml_escape("plain क्ष"), "plain क्ष");
    }

    #[test]
    fn coordinates_are_integers_and_clamped() {
        assert_eq!(y_at(1_000_000, 0), Y_TOP);
        assert_eq!(y_at(0, 0), Y_BOTTOM);
        assert_eq!(y_at(2_000_000, 0), Y_TOP, "scores above 1 are clamped");
        assert_eq!(y_at(500_000, 0), Y_BOTTOM - 155);
        assert_eq!(
            y_at(800_000, 600_000),
            Y_BOTTOM - 155,
            "half way up an axis from 0.6"
        );
        assert_eq!(
            y_at(100, 600_000),
            Y_BOTTOM,
            "scores below the axis are clamped"
        );
        assert_eq!(x_at(0), 100);
        assert_eq!(x_at(6), 880);
    }

    #[test]
    fn the_axis_floor_leaves_room_and_is_a_multiple_of_a_tenth() {
        assert_eq!(axis_floor(710_783), 600_000);
        assert_eq!(axis_floor(720_000), 700_000);
        assert_eq!(axis_floor(931_000), 900_000, "never above 0.9");
        assert_eq!(axis_floor(10_000), 0);
        assert_eq!(axis_floor(0), 0);
        assert_eq!(tick_label(0), "0");
        assert_eq!(tick_label(600_000), "0.6");
        assert_eq!(tick_label(1_000_000), "1");
    }

    #[test]
    fn figures_use_four_decimals_without_floats() {
        assert_eq!(fmt4(1_000_000), "1.0000");
        assert_eq!(fmt4(623_199), "0.6231");
        assert_eq!(fmt4(5), "0.0000");
        assert_eq!(fmt4(100), "0.0001");
    }
}
