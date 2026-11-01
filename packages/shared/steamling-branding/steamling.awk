# steamling.awk - the boot splash frames, drawn from the steamling (steamling-figure.svg): the
# still pose (logo.svg, which the watermark shows) and the throbber frames particles-NNNN.svg.
# He sits absorbed in his handheld while puffs of steam rise and fade either side of his face and
# from the steam cloud at the tip of his tail, and the screen's glow pulses. The overlay fades to nothing on the last frame, so the loop closes on
# the still pose and the watermark underneath never shows a jump.
#   awk -v frames=N -v out=DIR -f steamling.awk
# Every frame is the whole picture on black, in the same box and mapping as the watermark's logo.
# The figure itself is pulled in by reference, so it can only ever match the logo; librsvg renders
# all of it at build time and the boot only shows PNGs.
BEGIN {
    pi = atan2(0, -1)
    for (f = 0; f < frames; f++) {
        t = (f + 1) / frames; t -= int(t)   # 0 on the last frame: the still pose
        scene(sprintf("%s/particles-%04d.svg", out, f + 1), t, 1)
    }
    scene(out "/logo.svg", 0, 0)
}

function scene(file, t, opaque,    env, k, ph, side, x, y, r, o) {
    # 776x725 is the watermark box's aspect (watermark.svg, throbber.svg).
    print "<svg xmlns=\"http://www.w3.org/2000/svg\" xmlns:xlink=\"http://www.w3.org/1999/xlink\" width=\"776\" height=\"725\" viewBox=\"67.6 48 376.8 352\">" > file
    print "  <defs>" > file
    print "<filter id=\"inkSteam\" x=\"-25%\" y=\"-25%\" width=\"150%\" height=\"150%\" color-interpolation-filters=\"sRGB\">" > file
    print "    <feMorphology in=\"SourceAlpha\" operator=\"dilate\" radius=\"1.2\" result=\"grow\"/>" > file
    print "    <feGaussianBlur in=\"grow\" stdDeviation=\"0.3\" result=\"growsoft\"/>" > file
    print "    <feFlood flood-color=\"#4A5361\"/>" > file
    print "    <feComposite in2=\"growsoft\" operator=\"in\" result=\"line\"/>" > file
    print "    <feOffset in=\"SourceAlpha\" dx=\"-3.0\" dy=\"-4.0\" result=\"up\"/>" > file
    print "    <feComposite in=\"SourceAlpha\" in2=\"up\" operator=\"out\" result=\"low\"/>" > file
    print "    <feGaussianBlur in=\"low\" stdDeviation=\"1.80\"/>" > file
    print "    <feComposite in2=\"SourceAlpha\" operator=\"in\" result=\"lowin\"/>" > file
    print "    <feFlood flood-color=\"#93A0B2\" flood-opacity=\"0.6\"/>" > file
    print "    <feComposite in2=\"lowin\" operator=\"in\" result=\"shadow\"/>" > file
    print "    <feOffset in=\"SourceAlpha\" dx=\"2.0\" dy=\"2.0\" result=\"dn\"/>" > file
    print "    <feComposite in=\"SourceAlpha\" in2=\"dn\" operator=\"out\" result=\"high\"/>" > file
    print "    <feGaussianBlur in=\"high\" stdDeviation=\"0.80\"/>" > file
    print "    <feComposite in2=\"SourceAlpha\" operator=\"in\" result=\"highin\"/>" > file
    print "    <feFlood flood-color=\"#FFFFFF\" flood-opacity=\"0.0\"/>" > file
    print "    <feComposite in2=\"highin\" operator=\"in\" result=\"light\"/>" > file
    print "    <feMerge><feMergeNode in=\"line\"/><feMergeNode in=\"SourceGraphic\"/><feMergeNode in=\"shadow\"/><feMergeNode in=\"light\"/></feMerge>" > file
    print "  </filter>" > file
    print "<linearGradient id=\"puffG\" x1=\"0\" y1=\"0\" x2=\"0\" y2=\"1\">" > file
    print "    <stop offset=\"0\" stop-color=\"#FFFFFF\"/><stop offset=\"1\" stop-color=\"#D5D9DF\"/>" > file
    print "  </linearGradient>" > file
    print "<radialGradient id=\"glow\" cx=\"0.5\" cy=\"0.5\" r=\"0.5\">" > file
    print "    <stop offset=\"0\" stop-color=\"#A6E4FF\" stop-opacity=\"0.75\"/>" > file
    print "    <stop offset=\"0.45\" stop-color=\"#8FD8FF\" stop-opacity=\"0.25\"/>" > file
    print "    <stop offset=\"1\" stop-color=\"#8FD8FF\" stop-opacity=\"0\"/>" > file
    print "  </radialGradient>" > file
    print "  </defs>" > file
    if (opaque)
        print "  <rect x=\"67.6\" y=\"48\" width=\"376.8\" height=\"352\" fill=\"#000\"/>" > file
    print "  <image x=\"68\" y=\"48\" width=\"376\" height=\"352\" xlink:href=\"steamling-figure.svg\"/>" > file
    env = sin(pi * t)
    if (env > 0.001) {
        # the figure is drawn at 92% about (240,224): the overlay uses the same mapping
        print "  <g transform=\"translate(240,224) scale(0.92) translate(-240,-224)\">" > file
        # the screen's light breathing on his face, twice a loop
        printf "  <ellipse cx=\"240\" cy=\"248\" rx=\"104\" ry=\"48\" fill=\"url(#glow)\" opacity=\"%.3f\"/>\n", env * (0.25 + 0.25 * sin(4 * pi * t)) > file
        # three puffs a side, each rising from the steam beside his face and fading as it goes
        print "  <g filter=\"url(#inkSteam)\">" > file
        for (side = -1; side <= 1; side += 2) {
            for (k = 0; k < 3; k++) {
                ph = 2 * t + k / 3; ph -= int(ph)
                x = 240 + side * (118 + 14 * ph); y = 240 - 74 * ph; r = 4 + 6 * ph
                o = env * (1 - ph); if (ph < 0.25) o *= ph * 4
                if (o > 0.01)
                    printf "    <circle cx=\"%.1f\" cy=\"%.1f\" r=\"%.2f\" fill=\"url(#puffG)\" opacity=\"%.3f\"/>\n", x, y, r, o > file
            }
        }
        # and three more drifting up off the steam cloud on his tail
        for (k = 0; k < 3; k++) {
            ph = 2 * t + k / 3 + 1 / 6; ph -= int(ph)
            x = 398 + 8 * ph; y = 272 - 64 * ph; r = 4 + 5 * ph
            o = env * (1 - ph); if (ph < 0.25) o *= ph * 4
            if (o > 0.01)
                printf "    <circle cx=\"%.1f\" cy=\"%.1f\" r=\"%.2f\" fill=\"url(#puffG)\" opacity=\"%.3f\"/>\n", x, y, r, o > file
        }
        print "  </g>" > file
        print "  </g>" > file
    }
    print "</svg>" > file
    close(file)
}
