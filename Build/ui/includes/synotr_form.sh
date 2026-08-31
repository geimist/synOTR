#!/bin/bash
# shellcheck disable=SC2154
# Gemeinsame Formular-Helfer (Konfiguration, CutEditor-Warteliste).

synotr_html_attr() {
	printf '%s' "${1-}" | sed 's/&/\&amp;/g; s/"/\&quot;/g; s/</\&lt;/g'
}

synotr_form_help_btn() {
	if [ -z "$2" ]; then
		echo '<span class="synotr-help-btn"></span>'
		return
	fi
	echo '<label for="'"$1"'-info" class="synotr-help-btn"><img src="images/icon_information_mini@geimist.svg" height="25" width="25" alt=""/></label>'
}

synotr_form_hint() {
	[ -z "$2" ] && return
	echo '<input type="checkbox" id="'"$1"'-info" class="synotr-help-check" tabindex="-1"/>
		<div class="synotr-hint-card">'"$2"'</div>'
}

synotr_field_open() {
	if [ -n "$1" ]; then
		if [ "$2" = "hidden" ]; then
			echo '<div class="synotr-field" id="'"$1"'" style="display:none;">'
		else
			echo '<div class="synotr-field" id="'"$1"'">'
		fi
	else
		echo '<div class="synotr-field">'
	fi
}

# name label value help [wrap_id] [hidden]
synotr_form_text() {
	local _n="$1" _l="$2" _v="$3" _h="$4"
	local _esc
	_esc=$(synotr_html_attr "$_v")
	synotr_field_open "$5" "$6"
	echo '<div class="synotr-form-row">
			<label for="'"$_n"'">'"$_l"'</label>
			<input type="text" class="synotr-form-control" name="'"$_n"'" id="'"$_n"'" value="'"$_esc"'" />'
	synotr_form_help_btn "$_n" "$_h"
	echo '</div>'
	synotr_form_hint "$_n" "$_h"
	echo '</div>'
}

# name label value help [wrap_id] [hidden]
synotr_form_path() {
	local _n="$1" _l="$2" _v="$3" _h="$4"
	local _esc
	_esc=$(synotr_html_attr "$_v")
	synotr_field_open "$5" "$6"
	echo '<div class="synotr-form-row">
			<label for="'"$_n"'">'"$_l"'</label>
			<div class="synotr-path-wrap">
				<input type="text" class="synotr-form-control synotr-path-input" name="'"$_n"'" id="'"$_n"'" value="'"$_esc"'" spellcheck="false"/>
				<button type="button" class="synotr-path-pick" data-synotr-pick="'"$_n"'" title="Ordner auswählen" aria-label="Ordner auswählen">
					<svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true"><path d="M3 7a2 2 0 0 1 2-2h4l2 2h8a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"/></svg>
				</button>
			</div>'
	synotr_form_help_btn "$_n" "$_h"
	echo '</div>'
	synotr_form_hint "$_n" "$_h"
	echo '</div>'
}

synotr_chip_pin() {
	printf '<span draggable="true" class="synotr-namesyntax-palette-item" data-token="%s" title="%s">%s</span>\n' "$1" "$1" "$2"
}

synotr_form_namesyntax() {
	local _n="$1" _l="$2" _v="$3" _h="$4"
	local _esc
	_esc=$(synotr_html_attr "$_v")
	synotr_field_open
	echo '<div class="synotr-form-row synotr-namesyntax-row">
			<label for="'"$_n"'-visual">'"$_l"'</label>
			<div class="synotr-namesyntax-editor-wrap">
				<input type="hidden" name="'"$_n"'" id="'"$_n"'" value="'"$_esc"'" />
				<div id="'"$_n"'-visual" class="synotr-form-control synotr-namesyntax-editor" contenteditable="true" role="textbox" aria-multiline="false" spellcheck="false" tabindex="0" data-synotr-chip-hidden="'"$_n"'" data-synotr-chip-palette="synotr-namesyntax-palette"></div>
			</div>'
	synotr_form_help_btn "$_n" "$_h"
	echo '</div>'
	synotr_form_hint "$_n" "$_h"
	echo '</div>'
}

# name label current help [on] [off] [wrap_id] [hidden]
synotr_form_switch() {
	local _n="$1" _l="$2" _c="$3" _h="$4" _on="${5:-on}" _off="${6:-off}"
	local _chk="" _val="$_off"
	if [[ "$_c" == "$_on" ]]; then
		_chk=" checked"
		_val="$_on"
	fi
	synotr_field_open "$7" "$8"
	echo '<div class="synotr-form-row">
			<label for="'"$_n"'-switch">'"$_l"'</label>
			<div class="synotr-switch-wrap">
				<input type="hidden" name="'"$_n"'" id="'"$_n"'" value="'"$_val"'"/>
				<input class="synotr-switch" type="checkbox" role="switch" id="'"$_n"'-switch" data-synotr-switch="'"$_n"'" data-on="'"$_on"'" data-off="'"$_off"'"'"$_chk"'/>
			</div>'
	synotr_form_help_btn "$_n" "$_h"
	echo '</div>'
	synotr_form_hint "$_n" "$_h"
	echo '</div>'
}

# name label help options_html
synotr_form_select() {
	local _n="$1" _l="$2" _h="$3" _o="$4"
	synotr_field_open
	echo '<div class="synotr-form-row">
			<label for="'"$_n"'">'"$_l"'</label>
			<select class="synotr-form-control" name="'"$_n"'" id="'"$_n"'">'"$_o"'</select>'
	synotr_form_help_btn "$_n" "$_h"
	echo '</div>'
	synotr_form_hint "$_n" "$_h"
	echo '</div>'
}

synotr_option() {
	if [[ "$3" == "$1" ]]; then
		printf '<option value="%s" selected>%s</option>' "$1" "$2"
	else
		printf '<option value="%s">%s</option>' "$1" "$2"
	fi
}

synotr_int() {
	local _n="${1-0}"
	_n="${_n#"${_n%%[![:space:]]*}"}"
	_n="${_n%"${_n##*[![:space:]]}"}"
	[[ "$_n" =~ ^[+-]?[0-9]+$ ]] || _n=0
	printf '%s' "$_n"
}

synotr_clamp() {
	awk -v v="$1" -v lo="$2" -v hi="$3" -v st="${4:-1}" 'BEGIN {
		v = int(v); lo = int(lo); hi = int(hi); st = int(st);
		if (st < 1) st = 1;
		if (v < lo) v = lo;
		if (v > hi) v = hi;
		v = lo + int((v - lo) / st + 0.5) * st;
		if (v > hi) v = hi;
		if (v < lo) v = lo;
		printf "%d", v;
	}'
}

synotr_step_index() {
	awk -v v="$1" -v s="$2" 'BEGIN {
		n = split(s, a, ",");
		best = 0;
		bestd = 1e9;
		for (i = 1; i <= n; i++) {
			d = a[i] - v;
			if (d < 0) d = -d;
			if (d < bestd) { bestd = d; best = i - 1; }
		}
		printf "%d", best;
	}'
}

# name label value help min max step unit signed(0|1)
synotr_form_range() {
	local _n="$1" _l="$2" _v="$3" _h="$4" _min="$5" _max="$6" _step="$7" _unit="$8" _signed="${9:-0}"
	local _num _show
	_num=$(synotr_int "$_v")
	_num=$(synotr_clamp "$_num" "$_min" "$_max" "$_step")
	if [ "$_signed" = "1" ] && [ "$_num" -gt 0 ]; then
		_show="+${_num}"
	else
		_show="${_num}"
	fi
	[ -n "$_unit" ] && _show="${_show} ${_unit}"
	synotr_field_open
	echo '<div class="synotr-form-row">
			<label for="'"$_n"'-range">'"$_l"'</label>
			<div class="synotr-range-wrap">
				<input type="hidden" name="'"$_n"'" id="'"$_n"'" value="'"$_num"'"/>
				<input type="range" class="synotr-range" id="'"$_n"'-range" min="'"$_min"'" max="'"$_max"'" step="'"$_step"'" value="'"$_num"'" data-synotr-range="'"$_n"'" data-synotr-unit="'"$_unit"'" data-synotr-signed="'"$_signed"'"/>
				<span class="synotr-range-value" id="'"$_n"'-value">'"$_show"'</span>
			</div>'
	synotr_form_help_btn "$_n" "$_h"
	echo '</div>'
	synotr_form_hint "$_n" "$_h"
	echo '</div>'
}

# name label value help steps_csv unit suffix
synotr_form_range_steps() {
	local _n="$1" _l="$2" _v="$3" _h="$4" _steps="$5" _unit="$6" _suf="${7-}"
	local _num _idx _nsteps _show
	_num=$(synotr_int "${_v%k}")
	_idx=$(synotr_step_index "$_num" "$_steps")
	_nsteps=$(awk -v s="$_steps" 'BEGIN { printf "%d", split(s, a, ",") - 1 }')
	_num=$(awk -v s="$_steps" -v i="$_idx" 'BEGIN { split(s, a, ","); printf "%s", a[i+1] }')
	_show="${_num}"
	[ -n "$_unit" ] && _show="${_show} ${_unit}"
	synotr_field_open
	echo '<div class="synotr-form-row">
			<label for="'"$_n"'-range">'"$_l"'</label>
			<div class="synotr-range-wrap">
				<input type="hidden" name="'"$_n"'" id="'"$_n"'" value="'"${_num}${_suf}"'"/>
				<input type="range" class="synotr-range" id="'"$_n"'-range" min="0" max="'"$_nsteps"'" step="1" value="'"$_idx"'" data-synotr-range="'"$_n"'" data-synotr-steps="'"$_steps"'" data-synotr-unit="'"$_unit"'" data-synotr-suffix="'"$_suf"'"/>
				<span class="synotr-range-value" id="'"$_n"'-value">'"$_show"'</span>
			</div>'
	synotr_form_help_btn "$_n" "$_h"
	echo '</div>'
	synotr_form_hint "$_n" "$_h"
	echo '</div>'
}
