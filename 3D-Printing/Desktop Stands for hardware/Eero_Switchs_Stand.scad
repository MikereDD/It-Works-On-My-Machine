// ============================================
// 3-LAYER MODULAR HARDWARE STAND — Bambu X2D Optimized
// 6mm walls, 44.45mm tall (1.75"), integrated pegs
// DEVICE-SPECIFIC recessed seating pockets
// ============================================

$fn = 50;

// --- GLOBAL PARAMETERS ---
stand_width = 216;
stand_depth = 121;
layer_height = 44.45;  // 1.75 inches
wall_thickness = 6;
floor_thickness = 6;
peg_diameter = 8;
peg_height = 10;
peg_top_diameter = 7.2;
lip_height = 15;
seat_depth = 4;      // how deep device sits below base floor
seat_wall = 2;       // thickness of pocket rim
peg_tolerance = 0.5;
hole_chamfer = 1.5;

// Device dimensions (exact)
l1_device_w = 101.6;  l1_device_d = 101.6;  // TP-Link TL-SG1055-M2
l2l_device_w = 127;   l2l_device_d = 51;    // UGREEN USB 3.0 Switch
l2r_device_w = 44.5;  l2r_device_d = 51;    // Warrky HDMI Switch
l3_device_w = 146.6;  l3_device_d = 78.5;   // Eero 7 Pro

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
// LAYER 1: BOTTOM - TP-Link Switch (101.6 x 101.6 mm pocket)
// ============================================
module layer1() {
    dev_x = (stand_width - l1_device_w) / 2;
    dev_y = (stand_depth - l1_device_d) / 2;
    pocket_x = dev_x - seat_wall;
    pocket_y = dev_y - seat_wall;
    pocket_w = l1_device_w + 2 * seat_wall;
    pocket_d = l1_device_d + 2 * seat_wall;
    
    difference() {
        union() {
            tray_base(stand_width, stand_depth, wall_thickness, floor_thickness, layer_height);
        }
        translate([pocket_x, pocket_y, floor_thickness - seat_depth])
            cube([pocket_w, pocket_d, seat_depth + 0.1]);
    }
    
    translate([dev_x, dev_y, floor_thickness - seat_depth])
        cube([l1_device_w, l1_device_d, seat_depth]);
    
    difference() {
        translate([pocket_x, pocket_y, floor_thickness - seat_depth])
            cube([pocket_w, pocket_d, seat_depth]);
        translate([dev_x - 0.1, dev_y - 0.1, floor_thickness - seat_depth - 0.1])
            cube([l1_device_w + 0.2, l1_device_d + 0.2, seat_depth + 0.2]);
    }
    
    for(i = [0:2]) {
        translate([dev_x + 15 + i*30, dev_y + 10, floor_thickness - seat_depth - 0.1])
            cube([8, l1_device_d - 20, seat_depth + 0.2]);
    }
    
    for(pos = peg_positions) {
        peg(pos[0], pos[1], layer_height);
    }
}

// ============================================
// LAYER 2: MIDDLE - UGREEN + Warrky (two pockets, no divider wall)
// ============================================
module layer2() {
    gap = 15;
    total_device_w = l2l_device_w + gap + l2r_device_w;
    start_x = (stand_width - total_device_w) / 2;
    
    l2l_dev_x = start_x;
    l2l_dev_y = (stand_depth - l2l_device_d) / 2;
    l2l_pocket_x = l2l_dev_x - seat_wall;
    l2l_pocket_y = l2l_dev_y - seat_wall;
    l2l_pocket_w = l2l_device_w + 2 * seat_wall;
    l2l_pocket_d = l2l_device_d + 2 * seat_wall;
    
    l2r_dev_x = start_x + l2l_device_w + gap;
    l2r_dev_y = (stand_depth - l2r_device_d) / 2;
    l2r_pocket_x = l2r_dev_x - seat_wall;
    l2r_pocket_y = l2r_dev_y - seat_wall;
    l2r_pocket_w = l2r_device_w + 2 * seat_wall;
    l2r_pocket_d = l2r_device_d + 2 * seat_wall;
    
    difference() {
        union() {
            tray_base(stand_width, stand_depth, wall_thickness, floor_thickness, layer_height);
        }
        translate([l2l_pocket_x, l2l_pocket_y, floor_thickness - seat_depth])
            cube([l2l_pocket_w, l2l_pocket_d, seat_depth + 0.1]);
        translate([l2r_pocket_x, l2r_pocket_y, floor_thickness - seat_depth])
            cube([l2r_pocket_w, l2r_pocket_d, seat_depth + 0.1]);
    }
    
    translate([l2l_dev_x, l2l_dev_y, floor_thickness - seat_depth])
        cube([l2l_device_w, l2l_device_d, seat_depth]);
    difference() {
        translate([l2l_pocket_x, l2l_pocket_y, floor_thickness - seat_depth])
            cube([l2l_pocket_w, l2l_pocket_d, seat_depth]);
        translate([l2l_dev_x - 0.1, l2l_dev_y - 0.1, floor_thickness - seat_depth - 0.1])
            cube([l2l_device_w + 0.2, l2l_device_d + 0.2, seat_depth + 0.2]);
    }
    
    translate([l2r_dev_x, l2r_dev_y, floor_thickness - seat_depth])
        cube([l2r_device_w, l2r_device_d, seat_depth]);
    difference() {
        translate([l2r_pocket_x, l2r_pocket_y, floor_thickness - seat_depth])
            cube([l2r_pocket_w, l2r_pocket_d, seat_depth]);
        translate([l2r_dev_x - 0.1, l2r_dev_y - 0.1, floor_thickness - seat_depth - 0.1])
            cube([l2r_device_w + 0.2, l2r_device_d + 0.2, seat_depth + 0.2]);
    }
    
    for(pos = peg_positions) {
        peg_hole(pos[0], pos[1], 0);
    }
    for(pos = peg_positions) {
        peg(pos[0], pos[1], layer_height);
    }
}

// ============================================
// LAYER 3: TOP - Eero 7 Pro (base + lip only)
// ============================================
module layer3() {
    base_x = (stand_width - l3_device_w) / 2;
    base_y = (stand_depth - l3_device_d) / 2;
    
    difference() {
        union() {
            top_base_and_lip(stand_width, stand_depth, wall_thickness, lip_height);
            translate([base_x, base_y, floor_thickness])
                cube([l3_device_w, l3_device_d, 3]);
        }
        
        // Hollow out platform center
        translate([base_x + 10, base_y + 5, floor_thickness + 3])
            cube([l3_device_w - 20, l3_device_d - 10, 5]);
        
        // PEG HOLES — now properly inside difference() block
        for(pos = peg_positions) {
            peg_hole(pos[0], pos[1], 0);
        }
    }
    
    // No pegs on top (this is the top layer)
}

// ============================================
// EXPORTS — USE ONE AT A TIME
// ============================================

// Uncomment ONE for STL export:
// layer1();
// layer2();
// layer3();

// Preview full stack (for viewing only, do NOT export)
module full_assembly() {
    layer1();
    translate([0, 0, layer_height + peg_height]) layer2();
    translate([0, 0, 2*(layer_height + peg_height)]) layer3();
}

full_assembly();

// Flat print layout (do NOT export this)
module print_layout() {
    layer1();
    translate([stand_width + 20, 0, 0]) layer2();
    translate([2*(stand_width + 20), 0, 0]) layer3();
}
// print_layout();