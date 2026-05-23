// ============================================
// STAND 2 — Nokia Modem / Z906 / Creative X4
// 6mm walls, 44.45mm tall (1.75"), integrated pegs
// Bambu X2D Optimized
// ============================================

$fn = 50;

// --- GLOBAL PARAMETERS ---
stand_width = 230;
stand_depth = 140;
layer_height = 44.45;  // 1.75 inches
wall_thickness = 6;
floor_thickness = 6;
peg_diameter = 8;
peg_height = 10;
peg_top_diameter = 7.2;
lip_height = 15;
seat_depth = 4;
seat_wall = 2;
peg_tolerance = 0.5;
hole_chamfer = 1.5;

// Device dimensions (mm)
x4_device_w = 130.2;   x4_device_d = 127.0;   // Creative X4 (sits flat)
z906_front_w = 215.9;  z906_back_w = 177.8;   // Z906 (trapezoid, front/back width)
z906_depth = 76.2;                             // Z906 depth
nokia_device_w = 190.5;  nokia_device_d = 101.6;  // Nokia (pill shape, upright)

// Peg positions
peg_positions = [
    [wall_thickness, wall_thickness],
    [stand_width - wall_thickness, wall_thickness],
    [wall_thickness, stand_depth - wall_thickness],
    [stand_width - wall_thickness, stand_depth - wall_thickness]
];

// ============================================
// MODULES
// ============================================

module peg(x, y, z) {
    translate([x, y, z]) {
        cylinder(d1=peg_diameter, d2=peg_top_diameter, h=peg_height);
        translate([0, 0, peg_height])
            sphere(d=peg_top_diameter);
    }
}

module peg_hole(x, y, z) {
    hole_d = peg_diameter + peg_tolerance;
    translate([x, y, z - 0.1]) {
        translate([0, 0, peg_height + 2 - hole_chamfer])
            cylinder(d1=hole_d, d2=hole_d + 3, h=hole_chamfer + 0.1);
        cylinder(d=hole_d, h=peg_height + 2);
    }
}

module corner_pad(x, y, z, h) {
    translate([x - 6, y - 6, z])
        cube([12, 12, h]);
}

module tray_base(width, depth, wall_t, floor_t, height) {
    cube([width, depth, floor_t]);
    cube([wall_t, depth, height]);
    translate([width - wall_t, 0, 0])
        cube([wall_t, depth, height]);
    translate([wall_t, depth - wall_t, 0])
        cube([width - 2*wall_t, wall_t, 8]);
    for(pos = peg_positions) {
        corner_pad(pos[0], pos[1], 0, height);
    }
}

module top_base_and_lip(width, depth, wall_t, lip_h) {
    cube([width, depth, floor_thickness]);
    cube([width, wall_t, lip_h]);
    translate([0, depth - wall_t, 0])
        cube([width, wall_t, lip_h]);
    cube([wall_t, depth, lip_h]);
    translate([width - wall_t, 0, 0])
        cube([wall_t, depth, lip_h]);
    for(pos = peg_positions) {
        corner_pad(pos[0], pos[1], 0, lip_h);
    }
}

// ============================================
// LAYER 1: BOTTOM — Creative Labs X4 (flat, rectangular pocket)
// ============================================
module layer1() {
    dev_x = (stand_width - x4_device_w) / 2;
    dev_y = (stand_depth - x4_device_d) / 2;
    pocket_x = dev_x - seat_wall;
    pocket_y = dev_y - seat_wall;
    pocket_w = x4_device_w + 2 * seat_wall;
    pocket_d = x4_device_d + 2 * seat_wall;

    difference() {
        union() {
            tray_base(stand_width, stand_depth, wall_thickness, floor_thickness, layer_height);
        }
        translate([pocket_x, pocket_y, floor_thickness - seat_depth])
            cube([pocket_w, pocket_d, seat_depth + 0.1]);
    }

    // Pocket floor
    translate([dev_x, dev_y, floor_thickness - seat_depth])
        cube([x4_device_w, x4_device_d, seat_depth]);

    // Rim
    difference() {
        translate([pocket_x, pocket_y, floor_thickness - seat_depth])
            cube([pocket_w, pocket_d, seat_depth]);
        translate([dev_x - 0.1, dev_y - 0.1, floor_thickness - seat_depth - 0.1])
            cube([x4_device_w + 0.2, x4_device_d + 0.2, seat_depth + 0.2]);
    }

    // Ventilation slots
    for(i = [0:2]) {
        translate([dev_x + 20 + i*35, dev_y + 15, floor_thickness - seat_depth - 0.1])
            cube([10, x4_device_d - 30, seat_depth + 0.2]);
    }

    for(pos = peg_positions) {
        peg(pos[0], pos[1], layer_height);
    }
}

// ============================================
// LAYER 2: MIDDLE — Logitech Z906 (trapezoid pocket)
// Front is wider than back
// ============================================
module layer2() {
    center_x = stand_width / 2;
    center_y = stand_depth / 2;
    front_y = center_y + z906_depth / 2;
    back_y = center_y - z906_depth / 2;
    pocket_front_w = z906_front_w + 2 * seat_wall;
    pocket_back_w = z906_back_w + 2 * seat_wall;
    pocket_front_left = center_x - pocket_front_w / 2;
    pocket_front_right = center_x + pocket_front_w / 2;
    pocket_back_left = center_x - pocket_back_w / 2;
    pocket_back_right = center_x + pocket_back_w / 2;
    pocket_front_y = front_y + seat_wall;
    pocket_back_y = back_y - seat_wall;

    difference() {
        union() {
            tray_base(stand_width, stand_depth, wall_thickness, floor_thickness, layer_height);
        }
        translate([0, 0, floor_thickness - seat_depth])
        linear_extrude(height = seat_depth + 0.1)
        hull() {
            translate([pocket_back_left, pocket_back_y])
                square([pocket_back_w, 0.1]);
            translate([pocket_front_left, pocket_front_y - 0.1])
                square([pocket_front_w, 0.1]);
        }
    }

    // Trapezoid pocket floor
    translate([0, 0, floor_thickness - seat_depth])
    linear_extrude(height = seat_depth)
    hull() {
        translate([center_x - z906_back_w / 2, back_y])
            square([z906_back_w, 0.1]);
        translate([center_x - z906_front_w / 2, front_y - 0.1])
            square([z906_front_w, 0.1]);
    }

    // Trapezoid rim
    difference() {
        translate([0, 0, floor_thickness - seat_depth])
        linear_extrude(height = seat_depth)
        hull() {
            translate([pocket_back_left, pocket_back_y])
                square([pocket_back_w, 0.1]);
            translate([pocket_front_left, pocket_front_y - 0.1])
                square([pocket_front_w, 0.1]);
        }
        translate([0, 0, floor_thickness - seat_depth - 0.1])
        linear_extrude(height = seat_depth + 0.2)
        hull() {
            translate([center_x - z906_back_w / 2, back_y])
                square([z906_back_w, 0.1]);
            translate([center_x - z906_front_w / 2, front_y - 0.1])
                square([z906_front_w, 0.1]);
        }
    }

    for(pos = peg_positions) {
        peg_hole(pos[0], pos[1], 0);
    }
    for(pos = peg_positions) {
        peg(pos[0], pos[1], layer_height);
    }
}

// ============================================
// LAYER 3: TOP — Nokia Modem (pill-shaped, upright)
// ============================================
module layer3() {
    dev_x = (stand_width - nokia_device_w) / 2;
    dev_y = (stand_depth - nokia_device_d) / 2;
    corner_radius = 25;

    difference() {
        union() {
            top_base_and_lip(stand_width, stand_depth, wall_thickness, lip_height);
            translate([dev_x, dev_y, floor_thickness])
            linear_extrude(height = 3)
            hull() {
                translate([corner_radius, corner_radius])
                    circle(r = corner_radius);
                translate([nokia_device_w - corner_radius, corner_radius])
                    circle(r = corner_radius);
                translate([corner_radius, nokia_device_d - corner_radius])
                    circle(r = corner_radius);
                translate([nokia_device_w - corner_radius, nokia_device_d - corner_radius])
                    circle(r = corner_radius);
            }
        }
        translate([dev_x + 15, dev_y + 10, floor_thickness + 3])
            cube([nokia_device_w - 30, nokia_device_d - 20, 5]);
    }

    for(pos = peg_positions) {
        peg_hole(pos[0], pos[1], 0);
    }
}

// ============================================
// EXPORTS — USE ONE AT A TIME
// ============================================

// Uncomment ONE for STL export:
// layer1();
// layer2();
// layer3();

module full_assembly() {
    layer1();
    translate([0, 0, layer_height + peg_height]) layer2();
    translate([0, 0, 2*(layer_height + peg_height)]) layer3();
}

full_assembly();

module print_layout() {
    layer1();
    translate([stand_width + 20, 0, 0]) layer2();
    translate([2*(stand_width + 20), 0, 0]) layer3();
}
// print_layout();