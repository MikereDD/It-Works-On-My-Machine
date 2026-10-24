"""Approved ARAKIEL Raspberry + Arch InfoCat artwork."""

ART_WIDTH = 43

FRUIT_X = 16

FRUIT_Y = 10

ARCH = [
"                  -`                       ",
"                 .o+`                      ",
"                `ooo/                      ",
"               `+oooo:                     ",
"              `+oooooo:                    ",
"              -+oooooo+:                   ",
"            `/:-:++oooo+:                  ",
"           `/++++/+++++++:                 ",
"          `/++++++++++++++:                ",
"         `/+++ooooooooooooo/`              ",
"        ./ooosssso++osssssso+`             ",
"       .oossssso-````/ossssss+`            ",
"      -osssssso.      :ssssssso.           ",
"     :osssssss/        osssso+++.          ",
"    /ossssssss/        +ssssooo/-          ",
"  `/ossssso+/:-        -:/+osssso+-        ",
" `+sso+:-`                 `.-/+oso:       ",
"`++:.                           `-/+/      ",
".`                                 `/      ",
"                                           ",
"                                           ",
"                                           ",
"                                           ",
"                                           ",
"                                           ",
]

FRUIT = [
"  vv  ",
" vVVv ",
" oOOo ",
"oO88Oo",
"oO88Oo",
" 'oo' ",
]

def ansi(code):
    return f"\x1b[{code}m"

RESET = ansi("0")

BLUE  = ansi("38;5;39")

GREEN = ansi("38;5;77")

RED   = ansi("38;5;197")

TITLE = ansi("38;5;230")

def build_canvas():
    chars = [list(row.ljust(ART_WIDTH)) for row in ARCH]
    colors = [[BLUE if ch != " " else "" for ch in row] for row in chars]

    for ry, row in enumerate(FRUIT):
        ay = FRUIT_Y + ry
        if ay < 0 or ay >= len(chars):
            continue

        for rx, ch in enumerate(row):
            ax = FRUIT_X + rx
            if ax < 0 or ax >= ART_WIDTH:
                continue

            if ch == " ":
                continue

            chars[ay][ax] = ch
            colors[ay][ax] = GREEN if ry < 2 else RED

    return chars, colors
