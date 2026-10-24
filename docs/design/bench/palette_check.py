#!/usr/bin/env python3
"""Contrast and colorblind-separation check for the OpenBar palette (docs/design/README.md, section 2).

Usage: python3 -I docs/design/bench/palette_check.py

WCAG 2.x contrast; color-vision deficiency simulated with Machado et al. 2009 (severity 1.0) in linear
sRGB; distance is CIELAB Delta E 1976. Values mirror Sources/OpenBarCore/Design/OpenBarDesignTokens.swift.
"""
import itertools
import math

MODES = {
    "light": {"surfaces": {"white": "#FFFFFF", "card": "#F2F2F5"},
              "accent": "#5246E0", "accentFill": "#5246E0",
              "ok": "#07729A", "warning": "#946200", "critical": "#B4123F", "stale": "#8A8A8E"},
    "dark": {"surfaces": {"window": "#1E1E1E", "card": "#2C2C2E"},
             "accent": "#A39EFF", "accentFill": "#6159F0",
             "ok": "#2EC0EA", "warning": "#FFC533", "critical": "#FF6378", "stale": "#98989D"},
    "light-hc": {"surfaces": {"white": "#FFFFFF", "card": "#F2F2F5"},
                 "accent": "#3A2FC4", "accentFill": "#3A2FC4",
                 "ok": "#05648A", "warning": "#7A4F00", "critical": "#940B33", "stale": "#6E6E73"},
    "dark-hc": {"surfaces": {"black": "#000000", "card": "#1C1C1E"},
                "accent": "#BDB9FF", "accentFill": "#5B52EE",
                "ok": "#6FD6F5", "warning": "#FFD56B", "critical": "#FF8A9A", "stale": "#AEAEB2"},
}

MACHADO = {
    "protan": [[0.152286, 1.052583, -0.204868], [0.114503, 0.786281, 0.099216], [-0.003882, -0.048116, 1.051998]],
    "deutan": [[0.367322, 0.860646, -0.227968], [0.280085, 0.672501, 0.047413], [-0.011820, 0.042940, 0.968881]],
    "tritan": [[1.255528, -0.076749, -0.178779], [-0.078411, 0.930809, 0.147602], [0.004733, 0.691367, 0.303900]],
}


def rgb(hex_value):
    hex_value = hex_value.lstrip("#")
    return [int(hex_value[i:i + 2], 16) / 255 for i in (0, 2, 4)]


def linear(channel):
    return channel / 12.92 if channel <= 0.04045 else ((channel + 0.055) / 1.055) ** 2.4


def luminance(hex_value):
    r, g, b = (linear(c) for c in rgb(hex_value))
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def contrast(a, b):
    high, low = sorted((luminance(a), luminance(b)), reverse=True)
    return (high + 0.05) / (low + 0.05)


def lab(hex_value, deficiency=None):
    values = [linear(c) for c in rgb(hex_value)]
    if deficiency:
        m = MACHADO[deficiency]
        values = [max(0.0, min(1.0, sum(m[i][j] * values[j] for j in range(3)))) for i in range(3)]
    r, g, b = values
    x = (0.4124 * r + 0.3576 * g + 0.1805 * b) / 0.95047
    y = 0.2126 * r + 0.7152 * g + 0.0722 * b
    z = (0.0193 * r + 0.1192 * g + 0.9505 * b) / 1.08883

    def f(t):
        return t ** (1 / 3) if t > 0.008856 else 7.787 * t + 16 / 116

    return 116 * f(y) - 16, 500 * (f(x) - f(y)), 200 * (f(y) - f(z))


def main():
    tones = ("ok", "warning", "critical")
    for mode, values in MODES.items():
        print(f"== {mode}")
        for name in ("accent", "accentFill") + tones + ("stale",):
            ratios = "  ".join(f"{s} {contrast(values[name], c):5.2f}" for s, c in values["surfaces"].items())
            print(f"  {name:10s} {values[name]}  {ratios}  white-on {contrast('#FFFFFF', values[name]):4.2f}")
        for deficiency in (None, "protan", "deutan", "tritan"):
            pairs = [(math.dist(lab(values[a], deficiency), lab(values[b], deficiency)), a, b)
                     for a, b in itertools.combinations(tones, 2)]
            accent = min(math.dist(lab(values["accent"], deficiency), lab(values[t], deficiency)) for t in tones)
            worst = min(pairs)
            print(f"  {deficiency or 'normal':7s} tones min dE {worst[0]:5.1f} ({worst[1]}/{worst[2]})"
                  f"  accent-vs-tone min dE {accent:5.1f}")


if __name__ == "__main__":
    main()
