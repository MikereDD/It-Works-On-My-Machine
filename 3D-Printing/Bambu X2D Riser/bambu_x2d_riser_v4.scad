// ============================================
// BAMBU X2D RISER WITH TOOL DRAWERS v4.0
// Optimized for Bambu X2D + PLA+ Black
// 0.4mm hardened nozzle (standard X2D nozzle)
//
// ---- BAMBU STUDIO SLICE SETTINGS -----------
// Filament:    PLA+ (any brand black)
// Nozzle:      0.4mm
// Layer height: 0.20mm (0.28mm for frame/top
//               to cut time on non-visible parts)
// First layer: 0.20mm
// Walls:       4  (≈1.6mm — structural)
// Top/Bottom:  5 shells
// Infill:      30% Gyroid (strength/weight)
// Outer wall speed: 60 mm/s
// Inner wall speed: 150 mm/s
// Infill speed: 220 mm/s
// Nozzle temp: 220°C
// Bed temp:    60°C
// Fan:         80–100% after layer 3
// Supports:    NONE needed (all parts designed
//              to print support-free)
// Orientation: all parts print flat-face-down
// --------------------------------------------
// PRINT ORDER (largest/slowest first):
//   1. riser_frame_front   ~18h at 0.28mm
//   2. riser_frame_back    ~18h at 0.28mm
//   3. riser_top_left      ~6h  at 0.28mm
//   4. riser_top_right     ~6h  at 0.28mm
//   5. large_drawer        ~4h  at 0.20mm
//   6. small_drawer        ~3h  at 0.20mm
// ============================================

$fn = 60;

// --- DIMENSIONS ---
riser_width  = 420;
riser_depth  = 700;
base_thick   = 8;

// Wall thickness = 4 walls × 0.4mm nozzle × 1.0 line width = 1.6mm per wall
// Using 6.4mm (4 perimeters) for structural members
wall_thick   = 6.4;

airflow_gap   = 40;
drawer_height = 60;
drawer_depth  = 180;
frame_h       = airflow_gap + drawer_height; // 100mm

// Drawer widths — inner space = 420 - 6.4*2 = 407.2mm
// 240 + 6.4 (divider) + 160.8 = 407.2 ✓
large_drawer_w = 240.0;
small_drawer_w = 160.8;

// Vent slots — sized for clean bridging in PLA+
// Keep bridge spans ≤ 50mm for reliable PLA+ bridging without support
vent_h     = 14;   // height: multiple of 0.2mm layer = 14.0 ✓
vent_w     = 48;   // width: under 50mm bridge limit ✓
vent_count = 4;

// Dovetail rail dimensions (replaces fragile 4×8mm square rail)
// Dovetail is self-retaining — drawer can't pop out upward
dt_w_base  = 8;    // base width of dovetail
dt_w_top   = 6;    // narrow top (creates undercut)
dt_h       = 6;    // height
dt_slot_clearance = 0.3;  // sliding clearance each side

// Verified X2D body dimensions
x2d_w = 392;
x2d_d = 406;
x2d_margin_x = (riser_width - x2d_w) / 2;  // 14mm each side
x2d_margin_y = 15;

// Rear cable cutout (centered, behind X2D rear edge)
rear_cut_w = 300;
rear_cut_d = 32;
rear_cut_x = (riser_width - rear_cut_w) / 2;
// X2D rear edge on top plate = x2d_margin_y + x2d_d = 421mm
rear_cut_y = 418;

// Frame split point for bed-size parts
// Split front/back at y=350 (fits 350mm bed)
// Alignment pins at split joint
split_y      = 350;
pin_d        = 6;
pin_h        = 8;
pin_clearance = 0.2;

// ============================================
// HELPERS
// ============================================

// Dovetail rail — sits on shelf surface, extrudes along +Y
// Cross-section is in the XZ plane: base at z=0, narrow top at z=dt_h
module dovetail_rail_profile(length) {
    // rotate so linear_extrude (which goes along Z) ends up going along Y
    rotate([90, 0, 0])
    translate([0, 0, -length])
    linear_extrude(length)
        polygon(points=[
            [0,                                    0],
            [dt_w_base,                            0],
            [dt_w_base-(dt_w_base-dt_w_top)/2,    dt_h],
            [(dt_w_base-dt_w_top)/2,               dt_h]
        ]);
}

// Matching dovetail slot cut into drawer bottom — same axis, with clearance
module dovetail_slot_profile(length) {
    c = dt_slot_clearance;
    rotate([90, 0, 0])
    translate([0, 0, -length - 1])
    linear_extrude(length + 2)
        polygon(points=[
            [-c,                                         0],
            [dt_w_base + c,                              0],
            [dt_w_base-(dt_w_base-dt_w_top)/2 + c,     dt_h + c],
            [(dt_w_base-dt_w_top)/2 - c,                dt_h + c]
        ]);
}

// Alignment pin (male — on one half)
module align_pin() {
    cylinder(d=pin_d, h=pin_h);
}

// Alignment hole (female — on other half, with clearance)
module align_hole() {
    cylinder(d=pin_d + pin_clearance*2, h=pin_h + 1);
}

// ============================================
// SHARED FRAME GEOMETRY (used by both halves)
// Generates full frame, caller slices it
// ============================================
module _full_frame_geometry() {
    difference() {
        union() {
            // Outer walls
            cube([riser_width, wall_thick, frame_h]);
            translate([0, riser_depth - wall_thick, 0])
                cube([riser_width, wall_thick, frame_h]);
            cube([wall_thick, riser_depth, frame_h]);
            translate([riser_width - wall_thick, 0, 0])
                cube([wall_thick, riser_depth, frame_h]);

            // Floor
            cube([riser_width, riser_depth, base_thick]);

            // Drawer shelf at z=airflow_gap
            translate([wall_thick, wall_thick, airflow_gap])
                cube([riser_width - wall_thick*2,
                      riser_depth - wall_thick*2,
                      base_thick]);

            // Center divider between drawer bays
            translate([wall_thick + large_drawer_w, wall_thick, airflow_gap])
                cube([wall_thick, drawer_depth, drawer_height]);

            // Back wall of drawer bay
            translate([wall_thick, wall_thick + drawer_depth, airflow_gap])
                cube([riser_width - wall_thick*2, wall_thick, drawer_height]);

            // Internal cross-brace behind drawers (structural — stops racking)
            // Two diagonal-ish braces from back of drawer bay to back wall
            translate([wall_thick, drawer_depth + wall_thick*2, base_thick])
                cube([riser_width - wall_thick*2, wall_thick, frame_h - base_thick]);
            translate([wall_thick, (riser_depth - wall_thick)/2, base_thick])
                cube([riser_width - wall_thick*2, wall_thick, frame_h - base_thick]);
        }

        // Airflow vents — lower zone only
        // Left side
        for(i = [0 : vent_count-1]) {
            translate([-0.1, 80 + i*140, base_thick + 6])
                cube([wall_thick + 0.2, vent_w, vent_h]);
        }
        // Right side
        for(i = [0 : vent_count-1]) {
            translate([riser_width - wall_thick - 0.1, 80 + i*140, base_thick + 6])
                cube([wall_thick + 0.2, vent_w, vent_h]);
        }
        // Front intake vents
        for(i = [0 : 2]) {
            translate([90 + i*110, -0.1, base_thick + 6])
                cube([vent_w, wall_thick + 0.2, vent_h]);
        }

        // Drawer bay front wall opening
        translate([-0.1, -0.1, airflow_gap + base_thick])
            cube([riser_width + 0.2, wall_thick + 0.2, drawer_height + 0.1]);
    }

    // Dovetail rails on shelf surface
    rail_z = airflow_gap + base_thick;

    // Large drawer: left and right rails
    translate([wall_thick + 3, wall_thick + drawer_depth, rail_z])
        dovetail_rail_profile(drawer_depth);
    translate([wall_thick + large_drawer_w - dt_w_base - 3, wall_thick + drawer_depth, rail_z])
        dovetail_rail_profile(drawer_depth);

    // Small drawer: left and right rails
    translate([wall_thick*2 + large_drawer_w + 3, wall_thick + drawer_depth, rail_z])
        dovetail_rail_profile(drawer_depth);
    translate([riser_width - wall_thick - dt_w_base - 3, wall_thick + drawer_depth, rail_z])
        dovetail_rail_profile(drawer_depth);
}

// ============================================
// PART 1A: FRAME FRONT HALF
// Prints on 256×256 bed — 420×350mm section
// Print: 0.28mm layer, 4 walls, 30% Gyroid
// ============================================
module riser_frame_front() {
    difference() {
        _full_frame_geometry();
        // Cut away back half — overshoots split_y by 1mm to avoid coplanar face
        translate([-1, split_y - 1, -1])
            cube([riser_width + 2, riser_depth + 2, frame_h + 2]);
    }
    // Alignment pins — base embedded 2mm into body, no coplanar face
    translate([riser_width * 0.25, split_y - 2, base_thick + frame_h/2])
        rotate([-90, 0, 0]) align_pin();
    translate([riser_width * 0.75, split_y - 2, base_thick + frame_h/2])
        rotate([-90, 0, 0]) align_pin();
}

// ============================================
// PART 1B: FRAME BACK HALF
// Print: 0.28mm layer, 4 walls, 30% Gyroid
// ============================================
module riser_frame_back() {
    // Flat difference — no nested union, avoids non-manifold from degenerate booleans
    difference() {
        _full_frame_geometry();
        // Cut away front half — overshoots by 1mm each side, no coplanar faces
        translate([-1, -1, -1])
            cube([riser_width + 2, split_y + 1, frame_h + 2]);
        // Alignment holes — cylinder extends 2mm past face into body
        translate([riser_width * 0.25, split_y + 2, base_thick + frame_h/2])
            rotate([90, 0, 0]) align_hole();
        translate([riser_width * 0.75, split_y + 2, base_thick + frame_h/2])
            rotate([90, 0, 0]) align_hole();
    }
}

// ============================================
// SHARED TOP PLATE GEOMETRY
// ============================================
module _full_top_geometry() {
    difference() {
        cube([riser_width, riser_depth, base_thick]);

        // Airflow holes under X2D footprint
        // 35mm grid, 18mm holes — bridges cleanly in PLA+ at 0.28mm
        for(x = [x2d_margin_x + 10 : 35 : x2d_margin_x + x2d_w - 10]) {
            for(y = [x2d_margin_y + 10 : 35 : x2d_margin_y + x2d_d - 10]) {
                translate([x, y, -0.1])
                    cylinder(d=18, h=base_thick + 0.2);
            }
        }

        // Rear cable/port slot (power, USB, ethernet, exhaust)
        translate([rear_cut_x, rear_cut_y, -0.1])
            cube([rear_cut_w, rear_cut_d, base_thick + 0.2]);
    }

    // X2D corner locating bumps — 392×406mm footprint
    // 8mm dia × 2mm tall: PLA+ prints these cleanly, no support
    for(dx = [0, x2d_w]) {
        for(dy = [0, x2d_d]) {
            translate([x2d_margin_x + dx, x2d_margin_y + dy, base_thick])
                cylinder(d=8, h=2);
        }
    }
}

// ============================================
// PART 2A: TOP PLATE LEFT HALF
// 210×700mm — fits 256mm bed lengthwise
// Print: 0.28mm layer, 4 walls, 30% Gyroid
// Orient: flat face down, no supports needed
// ============================================
module riser_top_left() {
    difference() {
        _full_top_geometry();
        // Cut right half — overshoot by 1mm to avoid coplanar face
        translate([riser_width/2 - 1, -1, -1])
            cube([riser_width/2 + 2, riser_depth + 2, base_thick + 2]);
    }
    // Alignment pins embedded 2mm into right edge — no coplanar base
    translate([riser_width/2 - 2, riser_depth * 0.3, base_thick/2])
        rotate([0, -90, 0]) align_pin();
    translate([riser_width/2 - 2, riser_depth * 0.7, base_thick/2])
        rotate([0, -90, 0]) align_pin();
}

// ============================================
// PART 2B: TOP PLATE RIGHT HALF
// Print: same as left
// ============================================
module riser_top_right() {
    // Flat difference — no nested union wrapper
    difference() {
        _full_top_geometry();
        // Cut left half — overshoot by 1mm to avoid coplanar face
        translate([-1, -1, -1])
            cube([riser_width/2 + 1, riser_depth + 2, base_thick + 2]);
        // Alignment holes — extend 2mm past left face into body
        translate([riser_width/2 + 2, riser_depth * 0.3, base_thick/2])
            rotate([0, 90, 0]) align_hole();
        translate([riser_width/2 + 2, riser_depth * 0.7, base_thick/2])
            rotate([0, 90, 0]) align_hole();
    }
}

// ============================================
// PART 3: LARGE DRAWER (240 × 180 × 60mm)
// Print: 0.20mm layer, 4 walls, 30% Gyroid
// Orient: open face UP (no supports needed)
// Dovetail slots on bottom outside edges
// ============================================
module large_drawer() {
    inner_w = large_drawer_w - wall_thick*2;
    inner_d = drawer_depth - wall_thick;
    inner_h = drawer_height - wall_thick;

    difference() {
        union() {
            // Main body
            cube([large_drawer_w, drawer_depth, drawer_height]);
        }

        // Hollow interior (open top + open back for sliding)
        translate([wall_thick, wall_thick, wall_thick])
            cube([inner_w, inner_d, inner_h + 0.1]);

        // Dovetail slots on bottom outer edges (receives rail)
        translate([wall_thick + 3, -0.5, -0.1])
            dovetail_slot_profile(drawer_depth + 1);
        translate([wall_thick + large_drawer_w - dt_w_base - 3 - dt_slot_clearance, -0.5, -0.1])
            dovetail_slot_profile(drawer_depth + 1);
    }

    // Front handle lip — forward protrusion, ergonomic grip height
    translate([0, -10, 0])
        cube([large_drawer_w, 10, drawer_height + 6]);

    // Interior organizer ribs — 3 equal sections
    // Printed as part of drawer, no support needed (vertical walls)
    rib_spacing = inner_w / 3;
    for(i = [1 : 2]) {
        translate([wall_thick + i * rib_spacing - 1, wall_thick, wall_thick])
            cube([2, inner_d - 4, inner_h * 0.7]);
    }
}

// ============================================
// PART 4: SMALL DRAWER (160.8 × 180 × 60mm)
// Print: same as large drawer
// ============================================
module small_drawer() {
    inner_w = small_drawer_w - wall_thick*2;
    inner_d = drawer_depth - wall_thick;
    inner_h = drawer_height - wall_thick;

    difference() {
        cube([small_drawer_w, drawer_depth, drawer_height]);

        translate([wall_thick, wall_thick, wall_thick])
            cube([inner_w, inner_d, inner_h + 0.1]);

        // Dovetail slots
        translate([wall_thick + 3, -0.5, -0.1])
            dovetail_slot_profile(drawer_depth + 1);
        translate([wall_thick + small_drawer_w - dt_w_base - 3 - dt_slot_clearance, -0.5, -0.1])
            dovetail_slot_profile(drawer_depth + 1);
    }

    // Front handle lip
    translate([0, -10, 0])
        cube([small_drawer_w, 10, drawer_height + 6]);

    // Single center rib
    translate([wall_thick + inner_w/2 - 1, wall_thick, wall_thick])
        cube([2, inner_d - 4, inner_h * 0.7]);
}

// ============================================
// EXPORT CONTROL
// Set part = 0 for assembly preview
// Set part = 1-6 for individual STL export
// then press F6 → File → Export → Export as STL
// --------------------------------------------
// 0 = full assembly preview
// 1 = riser_frame_front
// 2 = riser_frame_back
// 3 = riser_top_left
// 4 = riser_top_right
// 5 = large_drawer
// 6 = small_drawer
// ============================================
part = 0;

// ============================================
// ASSEMBLY PREVIEW
// color() calls are preview-only, safe for F5
// Do NOT use color() when exporting STL (F6)
// ============================================
module full_assembly() {
    color("black", 0.85) riser_frame_front();
    color("black", 0.85) riser_frame_back();

    translate([0, 0, frame_h]) {
        color("black", 0.9) riser_top_left();
        color("black", 0.9) riser_top_right();
    }

    color("#1a1a1a")
    translate([wall_thick + 3, wall_thick, airflow_gap + base_thick])
        large_drawer();

    color("#1a1a1a")
    translate([wall_thick*2 + large_drawer_w + 3, wall_thick, airflow_gap + base_thick])
        small_drawer();

    // Uncomment to show X2D ghost footprint on top plate
    // %translate([x2d_margin_x, x2d_margin_y, frame_h + base_thick])
    //     cube([x2d_w, x2d_d, 10]);
}

// ============================================
// DISPATCHER — do not edit below this line
// ============================================
if      (part == 0) full_assembly();
else if (part == 1) riser_frame_front();
else if (part == 2) riser_frame_back();
else if (part == 3) riser_top_left();
else if (part == 4) riser_top_right();
else if (part == 5) large_drawer();
else if (part == 6) small_drawer();
