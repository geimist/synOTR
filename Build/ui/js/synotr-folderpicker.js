/**
 * synOTR folder picker (vanilla JS)
 *
 * Opens with synotr_openPicker(inputId) or a [data-synotr-pick] button.
 * Lists shares/folders via SYNO.FileStation.List. Auth:
 *   1) meta syno-token from login.cgi (this CGI session)
 *   2) SYNO.API.Auth method=token (v7, then v6)
 *   3) ?SynoToken= on this window, then the DSM parent iframe
 * Every webapi call sends SynoToken in the query and X-SYNO-TOKEN.
 * Paths are written as real volume paths (/volumeN/…) with a trailing slash.
 */
(function () {
	"use strict";

	var MODAL_ID = "synotrFolderPickerModal";
	var CONTENT_ID = "synotrFolderPickerContent";
	var LABEL_ID = "synotrFolderPickerModalLabel";
	var CONFIRM_ID = "synotrFolderPickerConfirm";
	var LANG_ID = "synotr-folderpicker-lang";

	var st = {
		input: null,
		currentPath: "",
		sharesRealMap: {},
		token: null,
		sid: null
	};
	var lang = {};

	function readLang() {
		var el = document.getElementById(LANG_ID);
		if (!el) return;
		try {
			var raw = el.textContent.trim();
			if (raw) lang = JSON.parse(raw);
		} catch (e) {
			lang = {};
		}
	}

	function L(k, fb) {
		return lang[k] != null ? lang[k] : fb;
	}

	function esc(s) {
		return String(s)
			.replace(/&/g, "&amp;")
			.replace(/</g, "&lt;")
			.replace(/>/g, "&gt;")
			.replace(/"/g, "&quot;");
	}

	function metaContent(name) {
		var m = document.querySelector('meta[name="' + name + '"]');
		var v = m && m.getAttribute("content");
		return v ? String(v).trim() : "";
	}

	function urlToken() {
		try {
			var t = new URLSearchParams(window.location.search).get("SynoToken");
			if (t) return t;
		} catch (e) {}
		try {
			if (window.parent !== window) {
				var p = new URLSearchParams(window.parent.location.search).get("SynoToken");
				if (p) return p;
			}
		} catch (e2) {}
		return "";
	}

	function tokenFromMetaOrUrl() {
		return metaContent("syno-token") || urlToken() || "";
	}

	function apiGet(params, cb) {
		var q = new URLSearchParams();
		var key;
		for (key in params) {
			if (Object.prototype.hasOwnProperty.call(params, key) && params[key] != null && params[key] !== "") {
				q.set(key, params[key]);
			}
		}
		if (st.token) q.set("SynoToken", st.token);
		if (st.sid) q.set("_sid", st.sid);
		var headers = { Accept: "application/json" };
		if (st.token) headers["X-SYNO-TOKEN"] = st.token;
		fetch("/webapi/entry.cgi?" + q.toString(), {
			method: "GET",
			credentials: "same-origin",
			headers: headers
		})
			.then(function (r) {
				return r.json();
			})
			.then(function (json) {
				cb(null, json);
			})
			.catch(function (err) {
				cb(err || new Error("fetch"), null);
			});
	}

	function authTokenApi(ver, cb) {
		apiGet({ api: "SYNO.API.Auth", version: String(ver), method: "token" }, function (err, resp) {
			if (!err && resp && resp.success && resp.data && resp.data.synotoken) {
				cb(resp.data.synotoken);
				return;
			}
			if (ver === 7) {
				authTokenApi(6, cb);
				return;
			}
			cb("");
		});
	}

	function resolveSynoToken(cb) {
		st.sid = st.sid || metaContent("syno-sid") || "";
		if (st.token) {
			cb(st.token);
			return;
		}
		var seeded = tokenFromMetaOrUrl();
		if (seeded) {
			st.token = seeded;
			cb(st.token);
			return;
		}
		authTokenApi(7, function (fresh) {
			st.token = fresh || "";
			cb(st.token);
		});
	}

	function isCsrf(resp) {
		return !!(resp && resp.error && Number(resp.error.code) === 119);
	}

	function fileStationGet(params, cb) {
		function run() {
			apiGet(params, function (err, resp) {
				cb(err, resp);
			});
		}
		resolveSynoToken(function (token) {
			if (!token) {
				cb(null, { success: false, error: { code: 119 } });
				return;
			}
			apiGet(params, function (err, resp) {
				if (!err && resp && isCsrf(resp)) {
					st.token = "";
					authTokenApi(7, function (fresh) {
						if (!fresh) {
							cb(err, resp);
							return;
						}
						st.token = fresh;
						run();
					});
					return;
				}
				cb(err, resp);
			});
		});
	}

	function csrfHtml() {
		return (
			'<div class="synotr-fp-msg synotr-fp-msg-warn"><strong>' +
			esc(L("not_available", "Folder Picker nicht verfuegbar")) +
			"</strong><br/><br/>" +
			esc(L("csrf", "Der Folder Picker kann innerhalb des DSM nicht verwendet werden, da der CSRF-Schutz aktiviert ist.")) +
			"<br/><br/>" +
			esc(L("csrf_fix", "Systemsteuerung → Sicherheit → Schutz gegen Cross-Site-Request-Forgery-Attacken verbessern deaktivieren, dann DSM neu anmelden.")) +
			"<br/><br/>" +
			esc(L("alternative", "Alternativ den Pfad manuell eintragen.")) +
			"</div>"
		);
	}

	function failHtml(msg) {
		return '<div class="synotr-fp-msg synotr-fp-msg-err">' + esc(msg) + "</div>";
	}

	function loadingHtml() {
		return '<div class="synotr-fp-loading"><img src="images/status_loading.gif" alt=""/></div>';
	}

	function contentEl() {
		return document.getElementById(CONTENT_ID);
	}

	function setContent(html) {
		var el = contentEl();
		if (el) el.innerHTML = html;
	}

	function withSlash(p) {
		if (!p) return p;
		return p.charAt(p.length - 1) === "/" ? p : p + "/";
	}

	function stripSlash(p) {
		if (!p || p === "/") return p || "";
		return String(p).replace(/\/+$/, "");
	}

	function getRelativePath(fullPath) {
		var best = "";
		var rp;
		for (rp in st.sharesRealMap) {
			if (Object.prototype.hasOwnProperty.call(st.sharesRealMap, rp) && fullPath.indexOf(rp) === 0 && rp.length > best.length) {
				best = rp;
			}
		}
		if (best) return st.sharesRealMap[best] + fullPath.substring(best.length);
		return fullPath;
	}

	function setCurrentPath(p) {
		st.currentPath = p || "";
		var btn = document.getElementById(CONFIRM_ID);
		if (btn) btn.disabled = !st.currentPath;
	}

	function wireList() {
		var box = contentEl();
		if (!box) return;
		box.onclick = function (ev) {
			var item = ev.target.closest("[data-synotr-fp]");
			if (!item) return;
			ev.preventDefault();
			var kind = item.getAttribute("data-synotr-fp");
			var p = item.getAttribute("data-path") || "";
			if (kind === "shares") {
				setCurrentPath("");
				loadShares();
				return;
			}
			setCurrentPath(p);
			loadFolders(p);
		};
	}

	function loadShares(after) {
		setContent(loadingHtml());
		fileStationGet(
			{
				api: "SYNO.FileStation.List",
				version: "2",
				method: "list_share",
				additional: '["name","path","isdir","perm","real_path"]'
			},
			function (err, resp) {
				if (err || !resp) {
					setContent(failHtml(L("failed_shares", "Fehler beim Laden der Freigaben.")));
					return;
				}
				if (!resp.success) {
					setContent(isCsrf(resp) ? csrfHtml() : failHtml(L("failed_shares", "Fehler beim Laden der Freigaben.") + " (" + (resp.error && resp.error.code ? resp.error.code : "?") + ")"));
					return;
				}
				st.sharesRealMap = {};
				var html = '<ul class="synotr-fp-list">';
				html += '<li class="synotr-fp-section">' + esc(L("shares", "Verfügbare Freigaben")) + "</li>";
				if (resp.data && resp.data.shares) {
					resp.data.shares.forEach(function (share) {
						if (!share.additional || !share.additional.real_path) return;
						st.sharesRealMap[share.additional.real_path] = share.path;
						html +=
							'<li class="synotr-fp-item" data-synotr-fp="folder" data-path="' +
							esc(share.additional.real_path) +
							'"><span class="synotr-fp-ico" aria-hidden="true"></span>' +
							esc(share.name) +
							"</li>";
					});
				}
				html += "</ul>";
				setContent(html);
				wireList();
				if (typeof after === "function") after();
			}
		);
	}

	function loadFolders(fullPath) {
		var folderPath = getRelativePath(fullPath);
		if (folderPath === fullPath) {
			loadShares();
			return;
		}
		setContent(loadingHtml());
		fileStationGet(
			{
				api: "SYNO.FileStation.List",
				version: "2",
				method: "list",
				folder_path: folderPath,
				additional: '["name","path","isdir","perm"]',
				sort_by: "name",
				sort_direction: "asc",
				limit: "500"
			},
			function (err, resp) {
					if (err || !resp) {
						setContent(failHtml(L("failed_folders", "Fehler beim Laden des Ordners.")));
						return;
					}
					if (!resp.success) {
						setContent(isCsrf(resp) ? csrfHtml() : failHtml(L("failed_folders", "Fehler beim Laden des Ordners.") + " (" + (resp.error && resp.error.code ? resp.error.code : "?") + ")"));
						return;
					}
					var html = '<ul class="synotr-fp-list">';
					html +=
						'<li class="synotr-fp-nav" data-synotr-fp="shares"><span class="synotr-fp-ico synotr-fp-ico-back" aria-hidden="true"></span>' +
						esc(L("back", "Zurück zu den Freigaben")) +
						"</li>";
					if (folderPath !== "/") {
						var parent = fullPath.substring(0, fullPath.lastIndexOf("/")) || "/";
						html +=
							'<li class="synotr-fp-nav" data-synotr-fp="folder" data-path="' +
							esc(parent) +
							'"><span class="synotr-fp-ico synotr-fp-ico-up" aria-hidden="true"></span>..</li>';
					}
					if (resp.data && resp.data.files) {
						resp.data.files.forEach(function (f) {
							if (!f.isdir) return;
							var rel = f.path.substring(folderPath.length);
							var next = fullPath + rel;
							var active = next === fullPath || next === st.currentPath ? " is-active" : "";
							html +=
								'<li class="synotr-fp-item' +
								active +
								'" data-synotr-fp="folder" data-path="' +
								esc(next) +
								'"><span class="synotr-fp-ico" aria-hidden="true"></span>' +
								esc(f.name) +
								"</li>";
						});
					}
					html += "</ul>";
					setContent(html);
					wireList();
				}
		);
	}

	function modalEl() {
		return document.getElementById(MODAL_ID);
	}

	function showModal() {
		var el = modalEl();
		if (!el) return;
		if (el.parentElement !== document.body) document.body.appendChild(el);
		el.removeAttribute("hidden");
		el.setAttribute("aria-hidden", "false");
		document.documentElement.classList.add("synotr-fp-open");
		var closeBtn = el.querySelector("[data-synotr-fp-close]");
		if (closeBtn) closeBtn.focus();
	}

	function hideModal() {
		var el = modalEl();
		if (!el) return;
		el.setAttribute("hidden", "hidden");
		el.setAttribute("aria-hidden", "true");
		document.documentElement.classList.remove("synotr-fp-open");
	}

	function selectPath(p) {
		if (st.input && p) st.input.value = withSlash(p);
		hideModal();
	}

	function confirmCurrent() {
		if (st.currentPath) selectPath(st.currentPath);
	}

	function tryOpenInitial(initial) {
		if (!initial) return;
		var mapped = getRelativePath(initial);
		if (mapped === initial) return;
		setCurrentPath(initial);
		loadFolders(initial);
	}

	window.synotr_openPicker = function (inputId) {
		readLang();
		st.input = typeof inputId === "string" ? document.getElementById(inputId) : inputId;
		st.currentPath = "";
		st.sharesRealMap = {};
		var label = document.getElementById(LABEL_ID);
		if (label) label.textContent = L("title", "Ordner auswaehlen");
		var conf = document.getElementById(CONFIRM_ID);
		if (conf) {
			conf.textContent = L("select", "Uebernehmen");
			conf.disabled = true;
			conf.onclick = confirmCurrent;
		}
		showModal();
		var initial = st.input ? stripSlash(st.input.value) : "";
		loadShares(function () {
			tryOpenInitial(initial);
		});
	};

	document.addEventListener("click", function (ev) {
		var pick = ev.target.closest("[data-synotr-pick]");
		if (pick) {
			ev.preventDefault();
			window.synotr_openPicker(pick.getAttribute("data-synotr-pick"));
			return;
		}
		if (ev.target.closest("[data-synotr-fp-close]")) {
			ev.preventDefault();
			hideModal();
			return;
		}
		var modal = modalEl();
		if (modal && !modal.hasAttribute("hidden") && ev.target === modal) {
			hideModal();
		}
	});

	document.addEventListener("keydown", function (ev) {
		if (ev.key !== "Escape") return;
		var modal = modalEl();
		if (modal && !modal.hasAttribute("hidden")) {
			ev.preventDefault();
			hideModal();
		}
	});
})();
