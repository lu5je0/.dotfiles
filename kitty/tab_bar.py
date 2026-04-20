from kitty.fast_data_types import Screen, get_options
from kitty.tab_bar import DrawData, ExtraData, TabBarData, as_rgb, draw_title
from kitty.utils import color_as_int

opts = get_options()

# tab_title_min_length: kitty doesn't have this natively, sync with kitty.conf manually
TAB_TITLE_MIN_LENGTH = 8


def _get_powerline_symbols(draw_data: DrawData):
    try:
        from kitty.tab_bar import powerline_symbols
        return powerline_symbols.get(draw_data.powerline_style, ('\ue0b0', '\ue0b1'))
    except (ImportError, AttributeError):
        return ('\ue0b0', '\ue0b1')


def draw_tab(
    draw_data: DrawData,
    screen: Screen,
    tab: TabBarData,
    before: int,
    max_tab_length: int,
    index: int,
    is_last: bool,
    extra_data: ExtraData,
) -> int:
    return _draw_tab_powerline(draw_data, screen, tab, before, max_tab_length, index, is_last, extra_data)


def _center_title(title: str, min_length: int) -> str:
    """Center title with spaces if shorter than min_length."""
    if len(title) >= min_length:
        return title
    total_pad = min_length - len(title)
    left_pad = total_pad // 2
    right_pad = total_pad - left_pad
    return ' ' * left_pad + title + ' ' * right_pad


def _draw_tab_powerline(
    draw_data: DrawData,
    screen: Screen,
    tab: TabBarData,
    before: int,
    max_tab_length: int,
    index: int,
    is_last: bool,
    extra_data: ExtraData,
) -> int:
    tab_bg = screen.cursor.bg
    tab_fg = screen.cursor.fg
    default_bg = as_rgb(int(draw_data.default_bg))

    if extra_data.next_tab:
        next_tab_bg = as_rgb(draw_data.tab_bg(extra_data.next_tab))
        needs_soft_separator = next_tab_bg == tab_bg
    else:
        next_tab_bg = default_bg
        needs_soft_separator = False

    separator_symbol, soft_separator_symbol = _get_powerline_symbols(draw_data)

    start_draw = 2
    if screen.cursor.x == 0:
        screen.cursor.bg = tab_bg
        screen.draw(' ')
        start_draw = 1

    screen.cursor.bg = tab_bg

    # Get title and apply min length centering
    title = tab.title
    tab_title = f'{title}'
    if TAB_TITLE_MIN_LENGTH > 0:
        inner_min = TAB_TITLE_MIN_LENGTH - 2
        if len(tab_title) < inner_min:
            tab_title = _center_title(tab_title, inner_min)

    # Draw manually: space + title + space
    cell = f' {tab_title} '
    if len(cell) > max_tab_length:
        cell = cell[:max_tab_length - 1] + '\u2026'
    screen.draw(cell)

    if not needs_soft_separator:
        screen.cursor.fg = tab_bg
        screen.cursor.bg = next_tab_bg
        screen.draw(separator_symbol)
    else:
        prev_fg = screen.cursor.fg
        if tab_bg == tab_fg:
            screen.cursor.fg = default_bg
        elif tab_bg != default_bg:
            c1 = draw_data.inactive_bg.contrast(draw_data.default_bg)
            c2 = draw_data.inactive_bg.contrast(draw_data.inactive_fg)
            if c1 < c2:
                screen.cursor.fg = default_bg
        screen.draw(f' {soft_separator_symbol}')
        screen.cursor.fg = prev_fg

    end = screen.cursor.x
    if end < screen.columns:
        screen.draw(' ')
    return end
