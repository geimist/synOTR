(function () {
	"use strict";

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
	var seek = document.getElementById("ceSeek");
	var clock = document.getElementById("ceClock");
	var keepsEl = document.getElementById("ceKeeps");
	var errEl = document.getElementById("ceErr");
	var stripEl = document.getElementById("ceStrip");
	var fps = 25;
	var duration = 0;
	var inMark = null;
	var outMark = null;
	var keeps = [];
	var seeking = false;

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

	function updateClock() {
		var t = video.currentTime || 0;
		clock.textContent = fmt(t) + "  /  Frame " + frameOf(t) + "  (" + fps.toFixed(3) + " fps)";
		if (duration > 0 && !seeking) {
			seek.value = String(Math.round((t / duration) * 1000));
		}
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

	function renderKeeps() {
		keepsEl.innerHTML = "";
		keeps.forEach(function (k, i) {
			var li = document.createElement("li");
			li.textContent = fmt(k.start) + " → " + fmt(k.start + k.duration) + " (" + k.duration.toFixed(3) + " s)";
			var del = document.createElement("button");
			del.type = "button";
			del.textContent = "Löschen";
			del.addEventListener("click", function () {
				keeps.splice(i, 1);
				renderKeeps();
			});
			li.appendChild(del);
			keepsEl.appendChild(li);
		});
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
		inMark = null;
		outMark = null;
		showErr("");
		renderKeeps();
	}

	function loadStrip() {
		var t = video.currentTime || 0;
		stripEl.hidden = false;
		stripEl.textContent = "Lade Frames …";
		fetch(API + "&action=strip&file=" + encodeURIComponent(file) + "&t=" + encodeURIComponent(String(t)) + "&span=5")
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

	document.querySelectorAll("[data-act]").forEach(function (btn) {
		btn.addEventListener("click", function () {
			var a = btn.getAttribute("data-act");
			if (a === "play") {
				if (video.paused) video.play();
				else video.pause();
			} else if (a === "back1") preciseSeek((video.currentTime || 0) - 1);
			else if (a === "fwd1") preciseSeek((video.currentTime || 0) + 1);
			else if (a === "prevf") stepFrame(-1);
			else if (a === "nextf") stepFrame(1);
			else if (a === "markin") {
				inMark = video.currentTime || 0;
				showErr("In @ " + fmt(inMark));
			} else if (a === "markout") {
				outMark = video.currentTime || 0;
				showErr("Out @ " + fmt(outMark));
			} else if (a === "addkeep") addKeep();
			else if (a === "strip") loadStrip();
		});
	});

	document.addEventListener("keydown", function (ev) {
		if (ev.target && (ev.target.tagName === "INPUT" || ev.target.tagName === "TEXTAREA")) return;
		var k = ev.key;
		if (k === "k" || k === "K" || k === " ") {
			ev.preventDefault();
			if (video.paused) video.play();
			else video.pause();
		} else if (k === "j" || k === "J") preciseSeek((video.currentTime || 0) - 1);
		else if (k === "l" || k === "L") preciseSeek((video.currentTime || 0) + 1);
		else if (k === ",") { ev.preventDefault(); stepFrame(-1); }
		else if (k === ".") { ev.preventDefault(); stepFrame(1); }
		else if (k === "i" || k === "I") {
			inMark = video.currentTime || 0;
			showErr("In @ " + fmt(inMark));
		} else if (k === "o" || k === "O") {
			outMark = video.currentTime || 0;
			showErr("Out @ " + fmt(outMark));
		} else if (k === "Enter") {
			ev.preventDefault();
			addKeep();
		}
	});

	seek.addEventListener("input", function () {
		seeking = true;
		if (duration > 0) video.currentTime = (Number(seek.value) / 1000) * duration;
	});
	seek.addEventListener("change", function () { seeking = false; });
	video.addEventListener("timeupdate", updateClock);

	document.getElementById("ceSave").addEventListener("click", function () {
		if (!keeps.length) {
			showErr("Keine Keep-Intervalle.");
			return;
		}
		fetch(API + "&action=save", {
			method: "POST",
			headers: { "Content-Type": "application/json" },
			body: JSON.stringify({ file: file, fps: fps, keeps: keeps })
		})
			.then(function (r) { return r.json(); })
			.then(function (data) {
				var m = document.getElementById("ceSaveMsg");
				if (data.ok) {
					m.hidden = false;
					m.textContent = "Gespeichert: " + data.cutlist;
					showErr("");
				} else {
					showErr(data.error || "Speichern fehlgeschlagen");
				}
			})
			.catch(function () { showErr("Speichern fehlgeschlagen"); });
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
			document.getElementById("ceTitle").textContent = it.file;
			document.getElementById("ceMeta").textContent =
				(it.source || "") + (it.private ? " · Eigengebrauch" : "") +
				(it.sender ? " · " + it.sender : "");
			if (it.needs_remux || !it.play_path) {
				showErr("Für otrkey-AVI zuerst „Für Editor als MP4“ auf der Liste ausführen.");
				return;
			}
			video.src = API + "&action=media&file=" + encodeURIComponent(file);
		})
		.catch(function () { showErr("API nicht erreichbar"); });
})();
