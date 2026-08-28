/**
 * synOTR — chip editor (contenteditable + hidden canonical §-string)
 *
 * Same interaction as synOCR: palette pins are dragged or clicked into a
 * contenteditable field; the hidden input keeps the §-syntax for save.
 *
 * Markup (see edit.sh):
 *   <input type="hidden" id="NameSyntax" name="NameSyntax" value="§tit …">
 *   <div id="NameSyntax-visual" contenteditable
 *        data-synotr-chip-hidden="NameSyntax"
 *        data-synotr-chip-palette="synotr-namesyntax-palette"></div>
 *   <div id="synotr-namesyntax-palette">… [data-token="§tit"] …</div>
 *
 * Several editors may share one palette. Click inserts into the last focused
 * field; drop always targets the editor under the pointer.
 */
(function () {
	"use strict";

	var CHIP_CLASS = "synotr-namesyntax-chip";
	var ACTIVE_CLASS = "synotr-namesyntax-editor-active";
	var paletteState = {};

	function sortedTokens(map) {
		return Object.keys(map).sort(function (a, b) {
			return b.length - a.length;
		});
	}

	function makeChip(token, label) {
		var span = document.createElement("span");
		span.className = CHIP_CLASS;
		span.setAttribute("contenteditable", "false");
		span.setAttribute("data-token", token);
		span.setAttribute("aria-label", token + " — " + label);
		span.setAttribute("draggable", "true");
		span.setAttribute("title", token);
		span.appendChild(document.createTextNode(label));
		return span;
	}

	function parseToFragment(s, map, sorted) {
		var frag = document.createDocumentFragment();
		var i = 0;
		var SEC = "\u00A7";

		while (i < s.length) {
			if (s.charAt(i) !== SEC) {
				var litStart = i;
				while (i < s.length && s.charAt(i) !== SEC) {
					i++;
				}
				frag.appendChild(document.createTextNode(s.slice(litStart, i)));
				continue;
			}

			var matched = false;
			var k;
			for (k = 0; k < sorted.length; k++) {
				var t = sorted[k];
				if (s.slice(i, i + t.length) === t && map[t]) {
					frag.appendChild(makeChip(t, map[t]));
					i += t.length;
					matched = true;
					break;
				}
			}
			if (!matched) {
				var unkStart = i;
				i++;
				while (i < s.length && s.charAt(i) !== SEC) {
					i++;
				}
				frag.appendChild(document.createTextNode(s.slice(unkStart, i)));
			}
		}
		return frag;
	}

	function serializeVisual(el) {
		var out = "";
		function walk(node) {
			if (node.nodeType === Node.TEXT_NODE) {
				out += node.textContent;
				return;
			}
			if (node.nodeType === Node.ELEMENT_NODE) {
				if (node.classList && node.classList.contains(CHIP_CLASS)) {
					out += node.getAttribute("data-token") || "";
					return;
				}
				var c;
				for (c = node.firstChild; c; c = c.nextSibling) {
					walk(c);
				}
			}
		}
		var ch;
		for (ch = el.firstChild; ch; ch = ch.nextSibling) {
			walk(ch);
		}
		return out;
	}

	function rangeFromClientInVisual(visual, clientX, clientY) {
		var r = null;
		if (document.caretRangeFromPoint) {
			r = document.caretRangeFromPoint(clientX, clientY);
		} else if (document.caretPositionFromPoint) {
			var pos = document.caretPositionFromPoint(clientX, clientY);
			if (pos && pos.offsetNode) {
				r = document.createRange();
				r.setStart(pos.offsetNode, pos.offset);
				r.collapse(true);
			}
		}
		if (!r || !visual.contains(r.commonAncestorContainer)) {
			return null;
		}
		return r;
	}

	function findContainingChip(fromNode, visual) {
		var n = fromNode;
		if (n && n.nodeType === Node.TEXT_NODE) {
			n = n.parentElement;
		}
		while (n && n !== visual) {
			if (n.nodeType === Node.ELEMENT_NODE && n.classList && n.classList.contains(CHIP_CLASS)) {
				return n;
			}
			n = n.parentElement;
		}
		return null;
	}

	function normalizeDropRange(visual, range, clientX) {
		if (!range) {
			return null;
		}
		var host = findContainingChip(range.startContainer, visual);
		if (!host) {
			return range;
		}
		var rect = host.getBoundingClientRect();
		var mid = rect.left + rect.width * 0.5;
		var r2 = document.createRange();
		if (clientX < mid) {
			r2.setStartBefore(host);
		} else {
			r2.setStartAfter(host);
		}
		r2.collapse(true);
		return r2;
	}

	function positionDropIndicator(indicator, wrap, visual, clientX, clientY, dragChip) {
		var r = rangeFromClientInVisual(visual, clientX, clientY);
		r = normalizeDropRange(visual, r, clientX, dragChip);
		if (!r) {
			indicator.style.display = "none";
			return;
		}
		var rect = r.getBoundingClientRect();
		var wr = wrap.getBoundingClientRect();
		var lineHeight = parseFloat(window.getComputedStyle(visual).lineHeight) || 20;
		var h = Math.max(rect.height > 0 ? rect.height : lineHeight, lineHeight * 0.85);
		var left = rect.left - wr.left;
		var top = rect.top - wr.top;
		indicator.style.left = left + "px";
		indicator.style.top = top + "px";
		indicator.style.height = h + "px";
		indicator.style.display = "block";
	}

	function ensureCaretInVisual(visual) {
		visual.focus();
		if (window.getSelection().rangeCount === 0) {
			var r = document.createRange();
			r.selectNodeContents(visual);
			r.collapse(false);
			var sel = window.getSelection();
			sel.removeAllRanges();
			sel.addRange(r);
		}
	}

	function dataTransferHasPlain(dt) {
		if (!dt || !dt.types) {
			return false;
		}
		var i;
		for (i = 0; i < dt.types.length; i++) {
			if (dt.types[i] === "text/plain") {
				return true;
			}
		}
		return false;
	}

	function buildMapFromPalette(pal) {
		var m = {};
		if (!pal) {
			return m;
		}
		var items = pal.querySelectorAll("[data-token]");
		var i;
		for (i = 0; i < items.length; i++) {
			var el = items[i];
			var tok = el.getAttribute("data-token");
			if (tok) {
				m[tok] = (el.textContent || "").trim();
			}
		}
		return m;
	}

	function markActive(visual, palette) {
		var id = palette && palette.id;
		var others;
		var i;
		if (!id) {
			visual.classList.add(ACTIVE_CLASS);
			return;
		}
		others = document.querySelectorAll('[data-synotr-chip-palette="' + id + '"]');
		for (i = 0; i < others.length; i++) {
			if (others[i] === visual) {
				others[i].classList.add(ACTIVE_CLASS);
			} else {
				others[i].classList.remove(ACTIVE_CLASS);
			}
		}
	}

	function bindSharedPalette(palette) {
		if (!palette || !palette.id || paletteState[palette.id]) {
			return;
		}
		var st = {
			insert: null,
			ensure: null
		};
		paletteState[palette.id] = st;

		palette.addEventListener("dragstart", function (e) {
			var t = e.target.closest("[data-token]");
			if (!t || !palette.contains(t)) {
				return;
			}
			e.dataTransfer.setData("text/plain", t.getAttribute("data-token") || "");
			e.dataTransfer.effectAllowed = "copy";
		});

		palette.addEventListener("click", function (e) {
			var t = e.target.closest("[data-token]");
			if (!t || !palette.contains(t)) {
				return;
			}
			e.preventDefault();
			var tok = (t.getAttribute("data-token") || "").trim();
			if (tok && st.insert) {
				if (st.ensure) {
					st.ensure();
				}
				st.insert(tok);
			}
		});
	}

	function create(opts) {
		opts = opts || {};
		var visual = opts.visual;
		var hidden = opts.hidden;
		var palette = opts.palette || null;
		var tokenMap = opts.tokenMap || {};
		var onChange = opts.onChange || null;

		if (!visual || !hidden) {
			return null;
		}

		var map = tokenMap;
		var sorted = sortedTokens(map);
		var listeners = [];

		function on(target, type, fn, useCapture) {
			target.addEventListener(type, fn, useCapture || false);
			listeners.push({ target: target, type: type, fn: fn, useCapture: useCapture || false });
		}

		var wrap = visual.parentElement;
		var dropIndicator = document.createElement("div");
		dropIndicator.className = "synotr-namesyntax-drop-indicator";
		dropIndicator.setAttribute("aria-hidden", "true");
		if (wrap) {
			wrap.appendChild(dropIndicator);
		}
		var internalDragChip = null;

		function hideDropIndicator() {
			dropIndicator.style.display = "none";
		}

		function syncHidden() {
			var next = serializeVisual(visual);
			if (hidden.value === next) {
				return;
			}
			hidden.value = next;
			hidden.dispatchEvent(new Event("input", { bubbles: true }));
			if (onChange) {
				onChange(next);
			}
		}

		function insertChipAtCaret(token) {
			var label = map[token] || token;
			var chip = makeChip(token, label);
			var sel = window.getSelection();
			if (!sel.rangeCount) {
				visual.appendChild(chip);
				syncHidden();
				return;
			}
			var range = sel.getRangeAt(0);
			if (!visual.contains(range.commonAncestorContainer)) {
				range.selectNodeContents(visual);
				range.collapse(false);
			}
			range.deleteContents();
			range.insertNode(chip);
			range.setStartAfter(chip);
			range.collapse(true);
			sel.removeAllRanges();
			sel.addRange(range);
			syncHidden();
		}

		function insertChipAtRange(token, range) {
			if (!range) {
				insertChipAtCaret(token);
				return;
			}
			if (!map[token]) {
				return;
			}
			var label = map[token] || token;
			var chip = makeChip(token, label);
			range.deleteContents();
			range.insertNode(chip);
			range.setStartAfter(chip);
			range.collapse(true);
			var sel = window.getSelection();
			sel.removeAllRanges();
			sel.addRange(range);
			visual.focus();
			syncHidden();
		}

		function moveChipToRange(chip, range) {
			if (!chip || !range || !visual.contains(range.commonAncestorContainer)) {
				return;
			}
			range.deleteContents();
			range.insertNode(chip);
			range.setStartAfter(chip);
			range.collapse(true);
			var sel = window.getSelection();
			sel.removeAllRanges();
			sel.addRange(range);
			visual.focus();
			syncHidden();
		}

		function claimPalette() {
			if (!palette || !palette.id) {
				return;
			}
			paletteState[palette.id].insert = insertChipAtCaret;
			paletteState[palette.id].ensure = function () {
				ensureCaretInVisual(visual);
			};
			markActive(visual, palette);
		}

		visual.innerHTML = "";
		visual.appendChild(parseToFragment(hidden.value || "", map, sorted));

		var debounceTimer;
		function scheduleSync() {
			clearTimeout(debounceTimer);
			debounceTimer = setTimeout(syncHidden, 0);
		}

		on(visual, "input", scheduleSync);
		on(visual, "blur", syncHidden);
		on(visual, "focus", claimPalette);

		on(visual, "paste", function (e) {
			e.preventDefault();
			var text = e.clipboardData.getData("text/plain");
			if (!text) {
				return;
			}
			var sel = window.getSelection();
			if (!sel.rangeCount) {
				return;
			}
			var range = sel.getRangeAt(0);
			if (!visual.contains(range.commonAncestorContainer)) {
				return;
			}
			range.deleteContents();
			range.insertNode(document.createTextNode(text));
			range.collapse(false);
			sel.removeAllRanges();
			sel.addRange(range);
			syncHidden();
		});

		var form = visual.closest("form");
		if (form) {
			on(form, "submit", syncHidden);
		}

		on(visual, "keydown", function (e) {
			if (e.key === "Enter") {
				e.preventDefault();
				return;
			}

			if (e.key !== "Backspace" && e.key !== "Delete") {
				return;
			}

			var sel = window.getSelection();
			if (!sel.rangeCount) {
				return;
			}
			var range = sel.getRangeAt(0);
			if (!range.collapsed) {
				return;
			}

			var node = range.startContainer;
			var offset = range.startOffset;

			if (e.key === "Backspace") {
				if (node.nodeType === Node.TEXT_NODE && offset > 0) {
					return;
				}
				if (node.nodeType === Node.TEXT_NODE && offset === 0) {
					var prev = node.previousSibling;
					if (prev && prev.classList && prev.classList.contains(CHIP_CLASS)) {
						e.preventDefault();
						prev.remove();
						syncHidden();
					}
					return;
				}
				if (node === visual && offset > 0) {
					var before = visual.childNodes[offset - 1];
					if (before && before.classList && before.classList.contains(CHIP_CLASS)) {
						e.preventDefault();
						before.remove();
						syncHidden();
					}
				}
			}

			if (e.key === "Delete") {
				if (node.nodeType === Node.TEXT_NODE && offset < node.textContent.length) {
					return;
				}
				if (node.nodeType === Node.TEXT_NODE && offset === node.textContent.length) {
					var next = node.nextSibling;
					if (next && next.classList && next.classList.contains(CHIP_CLASS)) {
						e.preventDefault();
						next.remove();
						syncHidden();
					}
					return;
				}
				if (node === visual && offset < visual.childNodes.length) {
					var after = visual.childNodes[offset];
					if (after && after.classList && after.classList.contains(CHIP_CLASS)) {
						e.preventDefault();
						after.remove();
						syncHidden();
					}
				}
			}
		});

		on(visual, "dragstart", function (e) {
			var chip = e.target.closest("." + CHIP_CLASS);
			if (!chip || !visual.contains(chip)) {
				return;
			}
			internalDragChip = chip;
			e.dataTransfer.setData("text/plain", chip.getAttribute("data-token") || "");
			e.dataTransfer.effectAllowed = "move";
		});

		on(visual, "dragover", function (e) {
			if (!wrap || !dataTransferHasPlain(e.dataTransfer)) {
				return;
			}
			e.preventDefault();
			e.dataTransfer.dropEffect = internalDragChip ? "move" : "copy";
			positionDropIndicator(dropIndicator, wrap, visual, e.clientX, e.clientY, internalDragChip);
		});

		on(visual, "drop", function (e) {
			e.preventDefault();
			hideDropIndicator();
			var token = (e.dataTransfer.getData("text/plain") || "").trim();
			var range = rangeFromClientInVisual(visual, e.clientX, e.clientY);
			range = normalizeDropRange(visual, range, e.clientX);

			if (internalDragChip && visual.contains(internalDragChip) && token) {
				if (!range) {
					visual.appendChild(internalDragChip);
					syncHidden();
				} else {
					moveChipToRange(internalDragChip, range);
				}
				internalDragChip = null;
				claimPalette();
				return;
			}

			if (token && map[token]) {
				insertChipAtRange(token, range);
			}
			internalDragChip = null;
			claimPalette();
		});

		on(visual, "dragend", function () {
			internalDragChip = null;
			hideDropIndicator();
		});

		on(document, "dragend", hideDropIndicator, true);

		if (palette && palette.id) {
			bindSharedPalette(palette);
			if (!paletteState[palette.id].insert) {
				claimPalette();
			}
		}

		function setValue(s) {
			visual.innerHTML = "";
			visual.appendChild(parseToFragment(s || "", map, sorted));
			hidden.value = s || "";
			if (onChange) {
				onChange(hidden.value);
			}
		}

		function getValue() {
			return serializeVisual(visual);
		}

		function destroy() {
			var i;
			for (i = 0; i < listeners.length; i++) {
				var l = listeners[i];
				l.target.removeEventListener(l.type, l.fn, l.useCapture);
			}
			listeners = [];
			if (dropIndicator.parentNode) {
				dropIndicator.parentNode.removeChild(dropIndicator);
			}
		}

		return {
			setValue: setValue,
			getValue: getValue,
			destroy: destroy
		};
	}

	function autoInit() {
		var visuals = document.querySelectorAll("[data-synotr-chip-hidden]");
		var i;
		for (i = 0; i < visuals.length; i++) {
			var visual = visuals[i];
			var hiddenId = visual.getAttribute("data-synotr-chip-hidden");
			var palId = visual.getAttribute("data-synotr-chip-palette");
			var hidden = hiddenId ? document.getElementById(hiddenId) : null;
			var palette = palId ? document.getElementById(palId) : null;
			if (!hidden) {
				continue;
			}
			create({
				visual: visual,
				hidden: hidden,
				palette: palette,
				tokenMap: buildMapFromPalette(palette)
			});
		}
	}

	if (document.readyState === "loading") {
		document.addEventListener("DOMContentLoaded", autoInit);
	} else {
		autoInit();
	}

	window.synotrChipEditor = { create: create };
}());
