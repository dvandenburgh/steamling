-- Retroid Pocket 6: Visionox VTDR6130 OLED. The RP5 and Flip 2 Visionox revisions carry the same
-- panel driver chip and borrow these values (not measured on them).
-- The panel exposes no EDID: gamescope synthesizes one (patch 0012) and matches this profile
-- on GAMESCOPE_INTERNAL_DEVICE_ID, which steamling-steam sets to the board's STEAMLING_DEVICE
-- (0013). It supplies the colorimetry (nominal DCI-P3, not measured) and the HDR range;
-- Steam's display settings turn HDR on and off. Values from armada-os/armada's profile for
-- the same panel. The board's STEAMLING_PANEL_HDR_NITS must match max_content_light_level.
gamescope.config.known_displays.steamling_rp6_vtdr6130 = {
    pretty_name = "Retroid Pocket 6 OLED (Visionox VTDR6130)",
    colorimetry = {
        r = { x = 0.6800, y = 0.3200 },
        g = { x = 0.2650, y = 0.6900 },
        b = { x = 0.1500, y = 0.0600 },
        w = { x = 0.3127, y = 0.3290 },
    },
    hdr = {
        supported = true,
        eotf = gamescope.eotf.gamma22,
        max_content_light_level = 750,
        max_frame_average_luminance = 375,
        min_content_light_level = 0,
    },
    matches = function(display)
        if (display.device_id == "rp6" or display.device_id == "rp5-visionox"
            or display.device_id == "rpflip2-visionox")
            and display.internal and not display.has_edid then
            return 6000
        end
        return -1
    end,
}
debug("Registered Retroid Pocket 6 OLED (Visionox VTDR6130) as a known display")
