// Sharting Poop Tray v3 - Simple Desk Tray
// Units: mm
// Purpose: freestanding tray that sits behind the printer.
// No hanger. No weird back geometry. No supports needed.
//
// Matching STL: sharting_poop_tray_v3_simple.stl

$fn = 48;

// -------------------------
// Dimensions
// -------------------------
tray_width  = 170;
tray_depth  = 125;

floor_thickness = 3;
wall_thickness  = 3;

rear_wall_height  = 75;
side_wall_height  = 60;
front_wall_height = 28;

// -------------------------
// Simple Tray
// -------------------------
module simple_poop_tray() {
    union() {
        // floor
        cube([tray_width, tray_depth, floor_thickness]);

        // rear wall
        translate([0, tray_depth - wall_thickness, 0])
            cube([tray_width, wall_thickness, rear_wall_height]);

        // left wall
        translate([0, 0, 0])
            cube([wall_thickness, tray_depth, side_wall_height]);

        // right wall
        translate([tray_width - wall_thickness, 0, 0])
            cube([wall_thickness, tray_depth, side_wall_height]);

        // front lip
        translate([0, 0, 0])
            cube([tray_width, wall_thickness, front_wall_height]);
    }
}

simple_poop_tray();
