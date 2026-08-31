(function () {
	"use strict";

	var OTRKEY_TIP = "otrkey-AVI: Remux kann mehrere Minuten dauern. Packed-Bitstream kann am Schnitt zittern – nur Eigengebrauch, kein Upload nach cutlist.at.";

	function qs(name) {
		try {
			return new URLSearchParams(window.location.search).get(name) || "";
		} catch (e) {
			return "";
		}
	}

	var file = qs("file");
	var API = "index.cgi?page=cuteditor-api";
	var video = document.getElementById("ceVideo");
	var clock = document.getElementById("ceClock");
	var errEl = document.getElementById("ceErr");
	var stripEl = document.getElementById("ceStrip");
	var tl = document.getElementById("ceTl");
	var tlInner = document.getElementById("ceTlInner");
	var tlSegs = document.getElementById("ceTlSegs");
	var tlHead = document.getElementById("ceTlHead");
	var tlIn = document.getElementById("ceTlIn");
	var tlOut = document.getElementById("ceTlOut");
	var playBtn = document.querySelector('[data-act="play"]');
	var fps = 25;
	var duration = 0;
	var inMark = null;
	var outMark = null;
	var keeps = [];
	var selected = -1;
	var dragging = false;
	var savedOk = false;
	var aspect = "";
	var keyframes = [];
	var cachePurged = false;

	function storedAuthor() {
		try {
			return window.localStorage.getItem("synotr-ce-author") || "";
		} catch (e) {
			return "";
		}
	}

	function rememberAuthor(name) {
		if (!name) return;
		try {
			window.localStorage.setItem("synotr-ce-author", name);
		} catch (e) { /* ignore */ }
	}

	function markDirty() {
		savedOk = false;
		var cutBtn = document.getElementById("ceCutNow");
		if (cutBtn) cutBtn.disabled = true;
	}

	function collectInfo() {
		function on(id) {
			var el = document.getElementById(id);
			return el && el.checked ? "1" : "0";
		}
		return {
			Author: (document.getElementById("ceAuthor") || {}).value || "",
			RatingByAuthor: (document.getElementById("ceRating") || {}).value || "",
			SuggestedMovieName: (document.getElementById("ceSuggested") || {}).value || "",
			UserComment: (document.getElementById("ceComment") || {}).value || "",
			ActualContent: (document.getElementById("ceActual") || {}).value || "",
			OtherErrorDescription: (document.getElementById("ceOtherDesc") || {}).value || "",
			EPGError: on("ceEPG"),
			MissingBeginning: on("ceMissBeg"),
			MissingEnding: on("ceMissEnd"),
			MissingVideo: on("ceMissVid"),
			MissingAudio: on("ceMissAud"),
			OtherError: on("ceOther")
		};
	}

	function showErr(msg) {
		errEl.hidden = !msg;
		errEl.textContent = msg || "";
	}

	function frameOf(t) {
		return Math.round(t * fps);
	}

	function timeOf(f) {
		return f / fps;
	}

	function fmt(t) {
		var s = Math.max(0, t);
		var h = Math.floor(s / 3600);
		var m = Math.floor((s % 3600) / 60);
		var sec = s % 60;
		return (h ? h + ":" : "") + String(m).padStart(2, "0") + ":" + sec.toFixed(3).padStart(6, "0");
	}

	function pct(t) {
		if (!duration) return 0;
		return Math.max(0, Math.min(100, (t / duration) * 100));
	}

	function timeFromClientX(clientX) {
		var rect = tlInner.getBoundingClientRect();
		if (rect.width <= 0 || !duration) return 0;
		var x = (clientX - rect.left) / rect.width;
		var t = x * duration;
		if (t < 0) t = 0;
		if (t > duration) t = duration;
		return t;
	}

	function renderTimeline() {
		tlSegs.innerHTML = "";
		keeps.forEach(function (k, i) {
			var el = document.createElement("div");
			el.className = "ce-seg ce-keep" + (i === selected ? " ce-sel" : "");
			el.style.left = pct(k.start) + "%";
			el.style.width = Math.max(0.4, pct(k.duration)) + "%";
			el.textContent = String(i + 1);
			el.title = "Keep " + fmt(k.start) + " → " + fmt(k.start + k.duration);
			el.addEventListener("mousedown", function (ev) {
				ev.stopPropagation();
				selected = i;
				dragging = true;
				preciseSeek(timeFromClientX(ev.clientX));
				renderTimeline();
			});
			tlSegs.appendChild(el);
		});
		if (inMark != null && duration) {
			var a = inMark;
			var b = outMark != null ? Math.max(inMark, outMark) : duration;
			if (outMark != null) a = Math.min(inMark, outMark);
			var draft = document.createElement("div");
			draft.className = "ce-seg " + (outMark != null ? "ce-draft" : "ce-open");
			draft.style.left = pct(a) + "%";
			draft.style.width = Math.max(0.4, pct(b - a)) + "%";
			draft.title = outMark != null
				? "Entwurf " + fmt(a) + " → " + fmt(b)
				: "Ab hier Keep (davor verworfen)";
			tlSegs.appendChild(draft);
		}
		tlIn.hidden = inMark == null || !duration;
		tlOut.hidden = outMark == null || !duration;
		if (inMark != null) tlIn.style.left = pct(inMark) + "%";
		if (outMark != null) tlOut.style.left = pct(outMark) + "%";
		moveHead();
		renderKeepsTable();
	}

	function renderKeepsTable() {
		var body = document.getElementById("ceKeepsBody");
		var table = document.getElementById("ceKeepsTable");
		if (!body || !table) return;
		body.innerHTML = "";
		if (!keeps.length) {
			table.hidden = true;
			return;
		}
		table.hidden = false;
		keeps.forEach(function (k, i) {
			var tr = document.createElement("tr");
			if (i === selected) tr.className = "ce-row-sel";
			var end = k.start + k.duration;
			function cellBtn(t, label) {
				var td = document.createElement("td");
				var b = document.createElement("button");
				b.type = "button";
				b.className = "ce-time";
				b.textContent = label;
				b.title = "Springe zu " + label;
				b.addEventListener("click", function () {
					selected = i;
					preciseSeek(t);
					renderTimeline();
				});
				td.appendChild(b);
				return td;
			}
			var tdN = document.createElement("td");
			tdN.textContent = String(i + 1);
			tr.appendChild(tdN);
			tr.appendChild(cellBtn(k.start, fmt(k.start)));
			tr.appendChild(cellBtn(end, fmt(end)));
			var tdD = document.createElement("td");
			tdD.textContent = fmt(k.duration);
			tr.appendChild(tdD);
			body.appendChild(tr);
		});
	}

	function moveHead() {
		if (!duration) return;
		tlHead.style.left = pct(video.currentTime || 0) + "%";
	}

	function updateClock() {
		var t = video.currentTime || 0;
		clock.textContent = fmt(t) + "  ·  Frame " + frameOf(t) + "  ·  " + fps.toFixed(3) + " fps";
		moveHead();
		if (playBtn) playBtn.textContent = video.paused ? "▶" : "❚❚";
	}

	function preciseSeek(t) {
		if (t < 0) t = 0;
		if (duration && t > duration) t = duration;
		return new Promise(function (resolve) {
			function done() {
				video.removeEventListener("seeked", done);
				updateClock();
				resolve();
			}
			video.addEventListener("seeked", done);
			video.currentTime = t;
			window.setTimeout(done, 400);
		});
	}

	function stepFrame(dir) {
		var f = frameOf(video.currentTime || 0) + dir;
		if (f < 0) f = 0;
		video.pause();
		preciseSeek(timeOf(f));
	}

	function addKeep() {
		if (inMark == null || outMark == null) {
			showErr("Zuerst In (I) und Out (O) setzen.");
			return;
		}
		var a = Math.min(inMark, outMark);
		var b = Math.max(inMark, outMark);
		if (b - a < 1 / fps) {
			showErr("Intervall zu kurz.");
			return;
		}
		keeps.push({
			start: a,
			duration: b - a,
			start_frame: frameOf(a),
			duration_frames: Math.max(1, frameOf(b) - frameOf(a))
		});
		keeps.sort(function (x, y) { return x.start - y.start; });
		selected = keeps.findIndex(function (k) { return Math.abs(k.start - a) < 1e-6; });
		inMark = null;
		outMark = null;
		showErr("");
		markDirty();
		renderTimeline();
	}

	function deleteSelected() {
		if (selected < 0 || selected >= keeps.length) {
			showErr("Kein Keep gewählt (Segment auf der Leiste anklicken).");
			return;
		}
		keeps.splice(selected, 1);
		selected = -1;
		showErr("");
		markDirty();
		renderTimeline();
	}

	function splitAtPlayhead() {
		var t = video.currentTime || 0;
		var i;
		var k;
		var left;
		var right;
		for (i = 0; i < keeps.length; i++) {
			k = keeps[i];
			if (t <= k.start + 1 / fps || t >= k.start + k.duration - 1 / fps) continue;
			left = {
				start: k.start,
				duration: t - k.start,
				start_frame: frameOf(k.start),
				duration_frames: Math.max(1, frameOf(t) - frameOf(k.start))
			};
			right = {
				start: t,
				duration: k.start + k.duration - t,
				start_frame: frameOf(t),
				duration_frames: Math.max(1, frameOf(k.start + k.duration) - frameOf(t))
			};
			keeps.splice(i, 1, left, right);
			selected = i + 1;
			showErr("");
			markDirty();
			renderTimeline();
			return;
		}
		showErr("Playhead liegt in keinem Keep.");
	}

    function stepKeyframe(dir) {
		ensureKeyframes(function () {
			var t = video.currentTime || 0;
			var i;
			var target = null;
			if (!keyframes.length) {
				showErr("Keine Keyframes gefunden.");
				return;
			}
			if (dir < 0) {
				for (i = keyframes.length - 1; i >= 0; i--) {
					if (keyframes[i] < t - 0.02) {
						target = keyframes[i];
						break;
					}
				}
				if (target == null) target = 0;
			} else {
				for (i = 0; i < keyframes.length; i++) {
					if (keyframes[i] > t + 0.02) {
						target = keyframes[i];
						break;
					}
				}
				if (target == null && duration) target = duration;
			}
			video.pause();
			preciseSeek(target);
		});
	}

	function ensureKeyframes(done) {
		if (keyframes.length) {
			done();
			return;
		}
		if (ensureKeyframes.busy) {
			return;
		}
		ensureKeyframes.busy = true;
		showErr("Lade Keyframes …");
		fetch(API + "&action=keyframes&file=" + encodeURIComponent(file))
			.then(function (r) { return r.json(); })
			.then(function (data) {
				ensureKeyframes.busy = false;
				if (data.ok && data.keyframes && data.keyframes.length) {
					keyframes = data.keyframes;
					showErr("");
					done();
				} else {
					showErr("Keine Keyframes gefunden.");
				}
			})
			.catch(function () {
				ensureKeyframes.busy = false;
				showErr("Keyframes fehlgeschlagen");
			});
	}

	function purgeFrameCache() {
		if (cachePurged || !file) return;
		cachePurged = true;
		var url = API + "&action=purgecache&file=" + encodeURIComponent(file);
		fetch(url, { method: "GET", keepalive: true }).catch(function () {});
	}

	function stripSpan() {
		stripEl.hidden = false;
		var w = stripEl.clientWidth || (window.innerWidth - 24) || 800;
		var vh = 48;
		var ar = 16 / 9;
		if (video.videoWidth && video.videoHeight) {
			ar = video.videoWidth / video.videoHeight;
		}
		var thumbW = Math.max(48, Math.round(vh * ar)) + 8;
		var count = Math.floor(w / thumbW);
		if (count < 5) count = 5;
		if (count > 31) count = 31;
		if (count % 2 === 0) count -= 1;
		return Math.floor((count - 1) / 2);
	}

	function loadStrip() {
		var t = video.currentTime || 0;
		var span = stripSpan();
		stripEl.hidden = false;
		stripEl.textContent = "Lade " + (span * 2 + 1) + " Frames …";
		fetch(API + "&action=strip&file=" + encodeURIComponent(file) + "&t=" + encodeURIComponent(String(t)) + "&span=" + encodeURIComponent(String(span)))
			.then(function (r) { return r.json(); })
			.then(function (data) {
				stripEl.innerHTML = "";
				if (!data.ok) {
					stripEl.textContent = data.error || "Fehler";
					return;
				}
				(data.frames || []).forEach(function (fr) {
					var wrap = document.createElement("div");
					var img = document.createElement("img");
					img.src = "data:image/jpeg;base64," + fr.jpeg;
					img.alt = String(fr.t);
					if (fr.i === 0) img.className = "ce-on";
					img.addEventListener("click", function () {
						preciseSeek(fr.t);
					});
					var cap = document.createElement("span");
					cap.textContent = (fr.i > 0 ? "+" : "") + fr.i;
					wrap.appendChild(img);
					wrap.appendChild(cap);
					stripEl.appendChild(wrap);
				});
			})
			.catch(function () {
				stripEl.textContent = "Streifen fehlgeschlagen";
			});
	}

	function togglePlay() {
		if (video.paused) video.play();
		else video.pause();
	}

	document.querySelectorAll("[data-act]").forEach(function (btn) {
		btn.addEventListener("click", function () {
			var a = btn.getAttribute("data-act");
			if (a === "play") togglePlay();
			else if (a === "start") preciseSeek(0);
			else if (a === "end") preciseSeek(duration);
			else if (a === "back1") preciseSeek((video.currentTime || 0) - 1);
			else if (a === "fwd1") preciseSeek((video.currentTime || 0) + 1);
			else if (a === "prevf") stepFrame(-1);
			else if (a === "nextf") stepFrame(1);
			else if (a === "prevkf") stepKeyframe(-1);
			else if (a === "nextkf") stepKeyframe(1);
			else if (a === "markin") {
				inMark = video.currentTime || 0;
				showErr("In @ " + fmt(inMark));
				markDirty();
				renderTimeline();
			} else if (a === "markout") {
				outMark = video.currentTime || 0;
				showErr("Out @ " + fmt(outMark));
				markDirty();
				renderTimeline();
			} else if (a === "addkeep") addKeep();
			else if (a === "split") splitAtPlayhead();
			else if (a === "delkeep") deleteSelected();
			else if (a === "strip") loadStrip();
		});
	});

	video.addEventListener("click", function () { togglePlay(); });
	video.addEventListener("play", updateClock);
	video.addEventListener("pause", updateClock);

	document.addEventListener("keydown", function (ev) {
		if (ev.target && (ev.target.tagName === "INPUT" || ev.target.tagName === "TEXTAREA")) return;
		var k = ev.key;
		if (k === "k" || k === "K" || k === " ") {
			ev.preventDefault();
			togglePlay();
		} else if (k === "j" || k === "J") preciseSeek((video.currentTime || 0) - 1);
		else if (k === "l" || k === "L") preciseSeek((video.currentTime || 0) + 1);
		else if (k === "ArrowLeft") { ev.preventDefault(); stepKeyframe(-1); }
		else if (k === "ArrowRight") { ev.preventDefault(); stepKeyframe(1); }
		else if (k === ",") { ev.preventDefault(); stepFrame(-1); }
		else if (k === ".") { ev.preventDefault(); stepFrame(1); }
		else if (k === "Home") { ev.preventDefault(); preciseSeek(0); }
		else if (k === "End") { ev.preventDefault(); preciseSeek(duration); }
		else if (k === "i" || k === "I") {
			inMark = video.currentTime || 0;
			showErr("In @ " + fmt(inMark));
			markDirty();
			renderTimeline();
		} else if (k === "o" || k === "O") {
			outMark = video.currentTime || 0;
			showErr("Out @ " + fmt(outMark));
			markDirty();
			renderTimeline();
		} else if (k === "Enter") {
			ev.preventDefault();
			addKeep();
		} else if (k === "Delete" || k === "Backspace") {
			ev.preventDefault();
			deleteSelected();
		}
	});

	function seekFromEvent(ev) {
		if (!duration) return;
		video.currentTime = timeFromClientX(ev.clientX);
		updateClock();
	}

	tl.addEventListener("mousedown", function (ev) {
		dragging = true;
		seekFromEvent(ev);
	});
	window.addEventListener("mousemove", function (ev) {
		if (dragging) seekFromEvent(ev);
	});
	window.addEventListener("mouseup", function () { dragging = false; });
	video.addEventListener("timeupdate", updateClock);

	function applyLoaded(data) {
		keeps = (data.keeps || []).map(function (k) {
			return {
				start: Number(k.start) || 0,
				duration: Number(k.duration) || 0,
				start_frame: k.start_frame,
				duration_frames: k.duration_frames
			};
		});
		selected = keeps.length ? 0 : -1;
		inMark = null;
		outMark = null;
		if (data.fps) fps = Number(data.fps) || fps;
		var info = data.info || {};
		function setVal(id, v) {
			var el = document.getElementById(id);
			if (el) el.value = v || "";
		}
		function setChk(id, v) {
			var el = document.getElementById(id);
			if (el) el.checked = v === "1" || v === 1 || v === true;
		}
		setVal("ceAuthor", info.Author);
		if (info.Author) rememberAuthor(info.Author);
		setVal("ceRating", info.RatingByAuthor);
		setVal("ceSuggested", info.SuggestedMovieName);
		setVal("ceComment", info.UserComment);
		setVal("ceActual", info.ActualContent);
		setVal("ceOtherDesc", info.OtherErrorDescription);
		setChk("ceEPG", info.EPGError);
		setChk("ceMissBeg", info.MissingBeginning);
		setChk("ceMissEnd", info.MissingEnding);
		setChk("ceMissVid", info.MissingVideo);
		setChk("ceMissAud", info.MissingAudio);
		setChk("ceOther", info.OtherError);
		showErr("");
		savedOk = true;
		var cutBtn = document.getElementById("ceCutNow");
		if (cutBtn) cutBtn.disabled = false;
		renderTimeline();
		updateClock();
	}

	function postSave(overwrite) {
		return fetch(API + "&action=save", {
			method: "POST",
			headers: { "Content-Type": "application/json" },
			body: JSON.stringify({
				file: file,
				fps: fps,
				keeps: keeps,
				aspect: aspect,
				info: collectInfo(),
				overwrite: overwrite
			})
		}).then(function (r) { return r.json(); });
	}

	document.getElementById("ceLoad").addEventListener("click", function () {
		fetch(API + "&action=cutlist&file=" + encodeURIComponent(file))
			.then(function (r) { return r.json(); })
			.then(function (data) {
				if (!data.ok) {
					showErr(data.error || "Keine lokale Cutlist");
					return;
				}
				applyLoaded(data);
				var m = document.getElementById("ceSaveMsg");
				m.hidden = false;
				m.textContent = "Geladen: " + data.cutlist;
			})
			.catch(function () { showErr("Laden fehlgeschlagen"); });
	});

	document.getElementById("ceSave").addEventListener("click", function () {
		if (!keeps.length) {
			showErr("Keine Keep-Intervalle.");
			return;
		}
		postSave(false)
			.then(function (data) {
				if (data.exists) {
					if (!window.confirm("Cutlist überschreiben?\n" + (data.cutlist || ""))) {
						return null;
					}
					return postSave(true);
				}
				return data;
			})
			.then(function (data) {
				if (!data) return;
				var m = document.getElementById("ceSaveMsg");
				var cutBtn = document.getElementById("ceCutNow");
				if (data.ok) {
					m.hidden = false;
					m.textContent = "Gespeichert: " + data.cutlist;
					showErr("");
					savedOk = true;
					rememberAuthor(collectInfo().Author);
					if (cutBtn) cutBtn.disabled = false;
				} else {
					showErr(data.error || "Speichern fehlgeschlagen");
				}
			})
			.catch(function () { showErr("Speichern fehlgeschlagen"); });
	});

	document.getElementById("ceCutNow").addEventListener("click", function () {
		if (!savedOk) {
			showErr("Zuerst Cutlist speichern.");
			return;
		}
		purgeFrameCache();
		window.location.href = "index.cgi?page=status-run-synotr";
	});

	var back = document.getElementById("ceBack");
	if (back) {
		back.addEventListener("click", function () { purgeFrameCache(); });
	}

	["ceAuthor", "ceRating", "ceSuggested", "ceComment", "ceActual", "ceOtherDesc",
		"ceEPG", "ceMissBeg", "ceMissEnd", "ceMissVid", "ceMissAud", "ceOther"].forEach(function (id) {
		var el = document.getElementById(id);
		if (el) el.addEventListener("change", markDirty);
		if (el) el.addEventListener("input", markDirty);
	});

	if (!file) {
		showErr("Keine Datei angegeben.");
		return;
	}
	fetch(API + "&action=item&file=" + encodeURIComponent(file))
		.then(function (r) { return r.json(); })
		.then(function (data) {
			if (!data.ok) {
				showErr(data.error || "Datei nicht geladen");
				return;
			}
			var it = data.item;
			fps = Number(it.fps) || 25;
			duration = Number(it.duration) || 0;
			aspect = it.aspect || "";
			document.getElementById("ceTitle").textContent = it.file;
			document.getElementById("ceSuggested").value = it.title || "";
			var meta = (it.source || "") + (it.private ? " · Eigengebrauch" : "") +
				(it.sender ? " · " + it.sender : "");
			if (it.editor_mp4) {
				meta += " · Editor-MP4: " + it.editor_mp4;
			}
			document.getElementById("ceMeta").textContent = meta;
			var warn = document.getElementById("ceWarn");
			if (it.source === "otrkey") {
				warn.hidden = false;
				warn.title = OTRKEY_TIP;
			}
			if (it.loaded_cutlist && it.loaded_cutlist.keeps && it.loaded_cutlist.keeps.length) {
				applyLoaded(it.loaded_cutlist);
			} else {
				document.getElementById("ceAuthor").value = storedAuthor() || it.author || "";
			}
			var playBase = file;
			if (it.play_path) {
				var segs = String(it.play_path).split(/[/\\]/);
				var bn = segs[segs.length - 1] || "";
				if (/\.mp4$/i.test(bn)) playBase = bn;
			}
			if (it.needs_remux && !/\.mp4$/i.test(playBase)) {
				showErr("Für otrkey-AVI zuerst „Für Editor als MP4“ auf der Liste ausführen.");
				return;
			}
			video.addEventListener("error", function () {
				showErr("Video nicht ladbar. Datei: " + playBase);
			});
			video.src = API + "&action=media&file=" + encodeURIComponent(playBase);
			video.addEventListener("loadedmetadata", function () {
				if (!duration && video.duration && isFinite(video.duration)) {
					duration = video.duration;
				}
				renderTimeline();
				updateClock();
			});
		})
		.catch(function () { showErr("API nicht erreichbar"); });
})();
