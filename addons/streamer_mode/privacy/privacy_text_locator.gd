class_name PrivacyTextLocator
extends RefCounted
## Works out where a substring actually renders inside a text Control, so a
## mask can cover only the private part of a line instead of the whole node.
##
## locate() returns node-local rects. A match that wraps across lines yields one
## rect per line fragment. An empty result means "measure precisely" was not
## possible; the caller should fall back to the full control rect.
##
## Coverage by node type:
##   Label          - full precision (horizontal and vertical), incl. wrapping,
##                    horizontal/vertical alignment and the `normal` stylebox.
##   LineEdit       - horizontal precision on its single line. Does NOT account
##                    for horizontal scrolling of overflowing text (see below).
##   RichTextLabel  - vertical precision only: the matched line band at full
##                    width. Per-character x offsets are not reliably derivable
##                    once BBCode changes fonts/sizes or inserts images, so we
##                    deliberately do not guess. See PRECISION_NOTES.

## Documented cases where exact measurement is not attempted.
const PRECISION_NOTES := {
	"RichTextLabel": "Line band only, full width. BBCode can change font, size and insert non-text items, so character x offsets are not derivable from the public API.",
	"LineEdit_scrolled": "Falls back to the full control rect when the text is wider than the field, because the visible window depends on the caret-driven scroll offset.",
	"no_font": "Falls back when the control has no resolvable theme font.",
	"unknown_type": "Falls back for any Control that is not Label, LineEdit or RichTextLabel.",
}


## Text used for pattern matching, matching what the user actually sees.
static func text_of(node: Node) -> String:
	if node is RichTextLabel:
		return (node as RichTextLabel).get_parsed_text()
	if node is Label:
		return (node as Label).text
	if node is LineEdit:
		return (node as LineEdit).text
	return ""


static func supports(node: Node) -> bool:
	return node is Label or node is LineEdit or node is RichTextLabel


## Node-local rects covering text[start, end). Empty means "fall back".
static func locate(node: Control, start: int, end: int) -> Array[Rect2]:
	var empty: Array[Rect2] = []
	if not is_instance_valid(node) or start < 0 or end <= start:
		return empty
	if node is Label:
		return _locate_label(node as Label, start, end)
	if node is LineEdit:
		return _locate_line_edit(node as LineEdit, start, end)
	if node is RichTextLabel:
		return _locate_rich(node as RichTextLabel, start, end)
	return empty


## --- Label: full precision ---------------------------------------------

static func _locate_label(label: Label, start: int, end: int) -> Array[Rect2]:
	var out: Array[Rect2] = []
	var text := label.text
	if end > text.length():
		return out
	var font := label.get_theme_font("font")
	var font_size := label.get_theme_font_size("font_size")
	if font == null or font_size <= 0:
		return out

	var pad := Vector2.ZERO
	var inner := label.size
	var sb := label.get_theme_stylebox("normal")
	if sb != null:
		pad = Vector2(sb.get_margin(SIDE_LEFT), sb.get_margin(SIDE_TOP))
		inner = label.size - sb.get_minimum_size()
	if inner.x <= 0.0:
		return out

	var spacing := float(label.get_theme_constant("line_spacing"))
	var para := _paragraph(text, font, font_size, inner.x, label.autowrap_mode, spacing)
	if para == null:
		return out

	var line_count := para.get_line_count()
	var heights: Array[float] = []
	var total := 0.0
	for i in line_count:
		var h: float = para.get_line_ascent(i) + para.get_line_descent(i)
		heights.append(h)
		total += h
	total += spacing * maxf(0.0, float(line_count - 1))

	var y := pad.y
	match label.vertical_alignment:
		VERTICAL_ALIGNMENT_CENTER:
			y += (inner.y - total) * 0.5
		VERTICAL_ALIGNMENT_BOTTOM:
			y += inner.y - total
		_:
			pass

	for i in line_count:
		var line_range := para.get_line_range(i)
		var a := maxi(start, line_range.x)
		var b := mini(end, line_range.y)
		if a < b:
			var span := _selection_span(para.get_line_rid(i), a, b)
			if span.y > span.x:
				var line_w: float = para.get_line_size(i).x
				var dx := _align_offset(label.horizontal_alignment, inner.x, line_w)
				out.append(Rect2(pad.x + dx + span.x, y, span.y - span.x, heights[i]))
		y += heights[i] + spacing
	return out


## --- LineEdit: single line, horizontal precision ----------------------

static func _locate_line_edit(field: LineEdit, start: int, end: int) -> Array[Rect2]:
	var out: Array[Rect2] = []
	var text := field.text
	if end > text.length():
		return out
	var font := field.get_theme_font("font")
	var font_size := field.get_theme_font_size("font_size")
	if font == null or font_size <= 0:
		return out

	var pad := Vector2.ZERO
	var inner := field.size
	var sb := field.get_theme_stylebox("normal")
	if sb != null:
		pad = Vector2(sb.get_margin(SIDE_LEFT), sb.get_margin(SIDE_TOP))
		inner = field.size - sb.get_minimum_size()
	if inner.x <= 0.0:
		return out

	var para := _paragraph(text, font, font_size, inner.x, TextServer.AUTOWRAP_OFF, 0.0)
	if para == null or para.get_line_count() == 0:
		return out

	# Overflowing text scrolls with the caret; the visible window is not
	# derivable here, so hand back a fallback instead of a wrong rect.
	if para.get_line_size(0).x > inner.x + 1.0:
		return out

	var span := _selection_span(para.get_line_rid(0), start, end)
	if span.y <= span.x:
		return out
	var h: float = para.get_line_ascent(0) + para.get_line_descent(0)
	var dx := _align_offset(field.alignment, inner.x, para.get_line_size(0).x)
	var y := pad.y + maxf(0.0, (inner.y - h) * 0.5)
	out.append(Rect2(pad.x + dx + span.x, y, span.y - span.x, h))
	return out


## --- RichTextLabel: line band only -----------------------------------

static func _locate_rich(rich: RichTextLabel, start: int, end: int) -> Array[Rect2]:
	var out: Array[Rect2] = []
	if rich.get_line_count() <= 0:
		return out
	var first := rich.get_character_line(start)
	var last := rich.get_character_line(maxi(start, end - 1))
	if first < 0 or last < first:
		return out
	var top := rich.get_line_offset(first)
	var bottom: float
	if last + 1 < rich.get_line_count():
		bottom = rich.get_line_offset(last + 1)
	else:
		bottom = rich.get_content_height()
	if bottom <= top:
		return out
	# Full width on purpose: see PRECISION_NOTES["RichTextLabel"].
	out.append(Rect2(0.0, top - rich.get_v_scroll_bar().value, rich.size.x, bottom - top))
	return out


## --- shared helpers ---------------------------------------------------

static func _paragraph(text: String, font: Font, font_size: int, width: float,
		autowrap: int, spacing: float) -> TextParagraph:
	var para := TextParagraph.new()
	para.clear()
	# Always shape left-aligned; alignment is applied by _align_offset so the
	# offset is never counted twice.
	para.alignment = HORIZONTAL_ALIGNMENT_LEFT
	para.break_flags = _break_flags(autowrap)
	para.width = width
	if "line_spacing" in para:
		para.line_spacing = spacing
	if not para.add_string(text, font, font_size):
		return null
	return para


static func _break_flags(autowrap: int) -> int:
	match autowrap:
		TextServer.AUTOWRAP_WORD:
			return TextServer.BREAK_WORD_BOUND
		TextServer.AUTOWRAP_WORD_SMART:
			return TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE
		TextServer.AUTOWRAP_ARBITRARY:
			return TextServer.BREAK_GRAPHEME_BOUND
		_:
			return TextServer.BREAK_NONE


## Min/max x of the shaped selection between two character offsets.
static func _selection_span(line_rid: RID, from: int, to: int) -> Vector2:
	if not line_rid.is_valid():
		return Vector2.ZERO
	var ts := TextServerManager.get_primary_interface()
	if ts == null:
		return Vector2.ZERO
	var ranges := ts.shaped_text_get_selection(line_rid, from, to)
	if ranges.is_empty():
		return Vector2.ZERO
	var lo := INF
	var hi := -INF
	for r in ranges:
		lo = minf(lo, minf(r.x, r.y))
		hi = maxf(hi, maxf(r.x, r.y))
	if hi <= lo:
		return Vector2.ZERO
	return Vector2(lo, hi)


static func _align_offset(alignment: int, area_width: float, line_width: float) -> float:
	match alignment:
		HORIZONTAL_ALIGNMENT_CENTER:
			return maxf(0.0, (area_width - line_width) * 0.5)
		HORIZONTAL_ALIGNMENT_RIGHT:
			return maxf(0.0, area_width - line_width)
		_:
			return 0.0
