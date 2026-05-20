/*
  Sharting Tray v1.0
  A shallow 3D-printable catch tray for tiny printer bits, poop purge, screws,
  cursed scraps, and whatever other crimes the workbench commits.

  Units: mm
*/

$fn = 64;

// ---------- Parameters ----------
outer_x      = 150;
outer_y      = 105;
corner_r     = 14;
bottom_thick = 3;
wall_height  = 18;
wall_thick   = 4;

// Optional label
show_label   = true;
label_text   = "SHARTING TRAY";
label_depth  = 0.8;

// ---------- Helpers ----------
module rounded_rect_2d(x, y, r) {
  hull() {
    translate([ x/2-r,  y/2-r]) circle(r=r);
    translate([-x/2+r,  y/2-r]) circle(r=r);
    translate([ x/2-r, -y/2+r]) circle(r=r);
    translate([-x/2+r, -y/2+r]) circle(r=r);
  }
}

module tray_shell() {
  difference() {
    linear_extrude(height = bottom_thick + wall_height)
      rounded_rect_2d(outer_x, outer_y, corner_r);

    translate([0, 0, bottom_thick])
      linear_extrude(height = wall_height + 0.2)
        rounded_rect_2d(
          outer_x - (wall_thick * 2),
          outer_y - (wall_thick * 2),
          max(corner_r - wall_thick, 1)
        );
  }
}

module label() {
  if (show_label) {
    translate([0, -outer_y/2 + 18, bottom_thick + 0.02])
      linear_extrude(height = label_depth)
        text(label_text, size = 8, halign = "center", valign = "center", font = "Liberation Sans:style=Bold");
  }
}

union() {
  tray_shell();
  label();
}
